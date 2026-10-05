import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlayerSession, PlaybackCallbacks } from '../service/playback/PlayerSession';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { LibraryStore } from '../service/library/LibraryStore';
import { PlayMode } from '../service/playback/QueueEngine';
import { PlayerState } from '../model/Playback';
import { OnlineSong, Track } from '../model/Entities';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { SleepTimer, SleepTimerSnapshot } from '../service/playback/SleepTimer';
import { NetEaseApi, PlaybackResolution } from '../service/network/NetEaseApi';
import { ApiError } from '../service/network/ApiClient';

const DOMAIN = 0x0000;
const TAG = 'PlayerViewModel';

/** 播放状态容器(全局单例,音乐库页与正在播放页共享;队列域经钩子接管切歌) */
@Observed
export class PlayerViewModel {
  /** 状态/元数据变化及进度心跳；只用于卡片展示投影。 */
  playbackChangedHandler: (() => void) | null = null;
  currentTrack: Track | null = null;
  state: PlayerState = PlayerState.IDLE;
  positionMs: number = 0;
  durationMs: number = 0;
  volume: number = 0.8;
  errorText: string = '';
  errorCode: string = '';
  recoveryAction: string = '';
  private requestVersion: number = 0;
  private resolutionCancel: (() => void) | null = null;
  private playbackReadyHandler: ((request: number) => void) | null = null;

  get statusText(): string {
    switch (this.state) {
      case PlayerState.PREPARING: return '正在加载音乐…';
      case PlayerState.PLAYING: return '正在播放';
      case PlayerState.PAUSED: return '已暂停';
      case PlayerState.COMPLETED: return '播放已结束';
      case PlayerState.ERROR: return this.errorText !== '' ? this.errorText : '播放失败，请重试';
      default: return '请选择音乐';
    }
  }

  get requestId(): number { return this.requestVersion; }

  get playbackSourceText(): string {
    if (this.state === PlayerState.ERROR || this.state === PlayerState.PREPARING) { return ''; }
    const source = this.currentTrack?.playbackSource;
    if (source === 'api-enhanced') { return '网易云'; }
    if (source === 'meting-tencent') { return '腾讯 / QQ'; }
    if (source === 'meting-kugou') { return '酷狗'; }
    if (source === 'meting-kuwo') { return '酷我'; }
    if (source === 'bilibili') { return 'Bilibili'; }
    return source !== undefined ? source : '';
  }

  isCurrentRequest(request: number): boolean { return request === this.requestVersion; }

  get sourceOptions(): OnlineSong[] { return this.currentTrack?.sourceOptions ?? []; }

  /** 只变更当前条目的音频；搜索新建条目时不复制这个选择。 */
  async selectSource(mediaRef: string): Promise<void> {
    const track = this.currentTrack;
    if (track === null || this.lastContext === null || this.state === PlayerState.PREPARING ||
      !track.sourceSearchSession || !track.catalogRef ||
      !this.sourceOptions.some((song: OnlineSong): boolean => song.mediaRef === mediaRef)) { return; }
    const position = this.positionMs;
    track.manualPlaybackRef = mediaRef;
    track.audioIntegrity = undefined;
    const request = this.beginTrack(track, this.lastContext);
    await this.playTrack(track, this.lastContext, position, request);
  }

  setResolutionCancel(request: number, cancel: () => void): void {
    if (!this.isCurrentRequest(request)) { cancel(); return; }
    this.resolutionCancel = cancel;
  }

  /** 在本地查找/在线解析前即选择音轨，取消旧会话并显示准备状态。 */
  beginTrack(track: Track, context: common.Context,
    onReady: ((request: number) => void) | null = null): number {
    if (this.sleepTimer.consumeIfDue()) {
      this.clearSleepTimerHandle();
      this.notifySleepTimerChanged();
    }
    this.resolutionCancel?.();
    this.resolutionCancel = null;
    const request = ++this.requestVersion;
    const previous = this.session;
    this.session = new PlayerSession();
    previous.release().catch(() => {});
    this.lastContext = context;
    this.currentTrack = track;
    this.playbackReadyHandler = onReady;
    this.errorText = '';
    this.errorCode = '';
    this.recoveryAction = '';
    this.state = PlayerState.PREPARING;
    this.positionMs = 0;
    this.durationMs = Math.max(0, track.durationMs);
    this.sleepTimerPausePending = false;
    this.notifyTrackMetadata(track);
    this.syncBackground(true);
    return request;
  }

  private notifyTrackMetadata(track: Track): void {
    try {
      if (this.trackChangeHandler !== null) { this.trackChangeHandler(track); }
    } catch (err) {
      // 歌词失败由歌词域展示，不改变音频播放状态。
    }
    try {
      if (this.coverColorHandler !== null) { this.coverColorHandler(track); }
    } catch (err) {
      // 封面/取色失败使用自身回退，不改变音频播放状态。
    }
  }

  failRequest(request: number, code: string = ''): void {
    if (!this.isCurrentRequest(request)) { return; }
    this.errorCode = code;
    this.recoveryAction = code === 'FILE_MISSING' ? 'library' : 'retry';
    if (code === 'FILE_MISSING') {
      this.errorText = '音频文件已不在设备上，请到音乐库重新导入';
    } else if (code === 'NEED_LOGIN' || code === 'UNAUTHORIZED' || code === 'FORBIDDEN' || code === 'BIND_INVALID') {
      this.errorText = '在线播放需要登录并绑定账号，请到设置完成后重试';
      this.recoveryAction = 'settings';
    } else if (code === 'AUDIO_PREVIEW') {
      this.errorText = '当前来源只提供试听片段，请重试或在搜索结果中选择其他来源';
    } else if (code === 'AUDIO_UNKNOWN') {
      this.errorText = '暂时无法确认音频是否完整，请重试或在搜索结果中选择其他来源';
    } else if (code === 'PLAYBACK_TIMEOUT') {
      this.errorText = '寻找完整版已超时，请重试或在搜索结果中选择来源';
    } else if (code === 'PLAYBACK_EXHAUSTED') {
      this.errorText = '音乐平台暂无可靠完整版，请重试或在搜索结果中选择来源';
    } else if (code === 'PLAYBACK_CANCELLED') {
      this.errorText = '播放解析已取消';
    } else if (code === 'INVALID_SEARCH_SESSION') {
      this.errorText = '搜索结果已过期，请重新搜索后点播';
    } else if (code === 'MEDIA_READ_FAILED') {
      this.errorText = '音频读取失败，请重试或在搜索结果中选择其他来源';
    } else if (code === 'EMPTY_URL' || code === 'AUDIO_UNAVAILABLE') {
      this.errorText = '暂时没有可播放的音频，可能受版权或会员限制，请稍后重试';
    } else if (code === 'NETWORK' || code === 'TIMEOUT' || code === 'UPSTREAM_DOWN') {
      this.errorText = '音乐暂时加载失败，请检查网络后重试';
    } else {
      this.errorText = '这首音乐暂时无法播放，请重试';
    }
    if (this.currentTrack?.manualPlaybackRef !== undefined && this.recoveryAction === 'retry') {
      this.errorText += '；可重试所选来源或重新选择';
    }
    if (this.currentTrack !== null && (this.currentTrack.id < 0 ||
      (this.currentTrack.streamUrl !== undefined && this.currentTrack.streamUrl !== '')) &&
      code !== 'AUDIO_PREVIEW' && code !== 'AUDIO_UNKNOWN') {
      const integrity = this.currentTrack.audioIntegrity;
      this.currentTrack.audioIntegrity = {
        status: 'unavailable', reason: code === 'EMPTY_URL' ? 'empty_url' :
          code === 'MEDIA_READ_FAILED' ? 'media_read_failed' :
            code === 'AUDIO_UNAVAILABLE' ? (integrity?.reason ?? 'unavailable') : code.toLowerCase(),
        catalogDurationMs: integrity?.catalogDurationMs ?? this.currentTrack.durationMs,
        resourceDurationMs: integrity?.resourceDurationMs ?? 0, evidence: integrity?.evidence ?? []
      };
    }
    this.state = PlayerState.ERROR;
    this.syncBackground(true);
  }

  async retry(): Promise<void> {
    if (this.state !== PlayerState.ERROR || this.recoveryAction === 'library' ||
      this.currentTrack === null || this.lastContext === null) { return; }
    const track = this.currentTrack;
    const context = this.lastContext;
    const position = this.positionMs;
    const ready = this.playbackReadyHandler;
    const request = this.beginTrack(track, context, ready);
    await this.playTrack(track, context, position, request);
  }
  /** 播放模式由队列域持有,此处镜像供后台会话同步 */
  playMode: PlayMode = PlayMode.SEQUENTIAL;
  /** issue-06 队列域钩子:单曲自然播完 */
  endedHandler: (() => void) | null = null;
  /** issue-06 队列域钩子:暂停时落盘进度 */
  pausePositionHandler: ((ms: number) => void) | null = null;
  /** issue-08 歌词域钩子:切歌 */
  trackChangeHandler: ((t: Track) => void) | null = null;
  /** issue-08 歌词域钩子:位置滴答 */
  positionTickHandler: ((ms: number) => void) | null = null;
  /** issue-00 封面取色钩子:切歌时从封面提取主题色(正在播放页注入) */
  coverColorHandler: ((t: Track) => void) | null = null;
  private session: PlayerSession = new PlayerSession();
  private lastContext: common.Context | null = null;
  private lastStatsReportedMs: number = 0;
  private statsReporting: boolean = false;
  private sleepTimer: SleepTimer = new SleepTimer();
  private sleepTimerHandle: number = -1;
  private sleepTimerPausePending: boolean = false;
  sleepTimerChangedHandler: (() => void) | null = null;

  get sleepTimerSnapshot(): SleepTimerSnapshot {
    return this.sleepTimer.snapshot;
  }

  get sleepTimerActive(): boolean {
    return this.sleepTimer.snapshot.active;
  }

  get sleepTimerRemainingMs(): number {
    return this.sleepTimer.remainingMs();
  }

  setSleepTimer(durationMs: number): void {
    this.sleepTimer.startAfter(durationMs);
    this.scheduleSleepTimer();
    this.notifySleepTimerChanged();
  }

  cancelSleepTimer(): void {
    this.sleepTimer.cancel();
    this.clearSleepTimerHandle();
    this.notifySleepTimerChanged();
  }

  restoreSleepTimer(snapshot: SleepTimerSnapshot, nowMs: number = Date.now()): boolean {
    const wasActive = snapshot.active;
    this.sleepTimer.restore(snapshot, nowMs);
    if (this.sleepTimerActive) {
      this.scheduleSleepTimer();
    } else {
      this.clearSleepTimerHandle();
    }
    const expired = wasActive && !this.sleepTimerActive && snapshot.deadlineMs <= nowMs;
    return expired;
  }

  checkSleepTimer(nowMs: number = Date.now()): boolean {
    if (!this.sleepTimer.consumeIfDue(nowMs)) {
      return false;
    }
    this.clearSleepTimerHandle();
    this.notifySleepTimerChanged();
    if (this.state === PlayerState.PLAYING) {
      const request = this.requestVersion;
      this.pause().catch((err: Error) => {
        if (this.isCurrentRequest(request)) { this.setSleepTimerPauseError(err); }
      });
    } else if (this.state === PlayerState.PREPARING) {
      this.sleepTimerPausePending = true;
    } else {
      this.syncBackground(true);
    }
    return true;
  }

  private setSleepTimerPauseError(err: Error): void {
    hilog.error(DOMAIN, TAG, 'Sleep timer pause failed: %{public}s', err.message);
    this.errorText = '定时暂停未能完成，请稍后重试';
  }

  private notifySleepTimerChanged(): void {
    if (this.sleepTimerChangedHandler !== null) {
      this.sleepTimerChangedHandler();
    }
  }

  private clearSleepTimerHandle(): void {
    if (this.sleepTimerHandle >= 0) {
      clearTimeout(this.sleepTimerHandle);
      this.sleepTimerHandle = -1;
    }
  }

  private scheduleSleepTimer(): void {
    this.clearSleepTimerHandle();
    const remaining = this.sleepTimer.remainingMs();
    if (remaining <= 0) {
      return;
    }
    this.sleepTimerHandle = setTimeout(() => {
      this.sleepTimerHandle = -1;
      this.checkSleepTimer();
    }, remaining);
  }

  /** 会话就绪和前台恢复时使用同一快照重同步系统状态与长时任务。 */
  refreshBackground(): void {
    this.checkSleepTimer();
    this.syncBackground(true);
  }

  private syncBackground(force: boolean): void {
    try { this.playbackChangedHandler?.(); } catch (err) {}
    const bp = BackgroundPlayback.getInstance();
    bp.sync(this.currentTrack, this.state, this.positionMs, this.durationMs, this.playMode, force);
    if (this.state === PlayerState.PLAYING) {
      bp.startLongTask();
    } else if (this.state === PlayerState.PAUSED || this.state === PlayerState.COMPLETED ||
      this.state === PlayerState.IDLE || this.state === PlayerState.ERROR || this.state === PlayerState.PREPARING) {
      bp.stopLongTask();
    }
  }

  async playTrack(track: Track, context: common.Context, startMs: number = 0,
    expectedRequest: number = -1, prepared: PlaybackResolution | null = null): Promise<void> {
    const request = expectedRequest < 0 ? this.beginTrack(track, context) : expectedRequest;
    if (!this.isCurrentRequest(request)) { return; }
    const session = this.session;
    this.lastContext = context;
    if (this.currentTrack !== track) {
      this.currentTrack = track;
      this.notifyTrackMetadata(track);
    }
    this.errorText = '';
    this.positionMs = startMs;
    this.lastStatsReportedMs = startMs;
    this.durationMs = track.durationMs > 0 ? track.durationMs : 0;
    // 瞬态在线音轨:直链流式播放(阶段 v2.3),不检查本地文件
    const streaming = track.manualPlaybackRef !== undefined || track.id < 0 ||
      (track.streamUrl !== undefined && track.streamUrl !== '');
    let streamUrl = track.streamUrl !== undefined ? track.streamUrl : '';
    if (streaming) {
      try {
        const manual = track.manualPlaybackRef !== undefined;
        const playbackRef = manual ? track.manualPlaybackRef! :
          track.automaticSearchSession !== undefined ? (track.catalogRef ?? '') :
          track.playbackRef !== undefined ? track.playbackRef :
          (track.mediaRef !== undefined ? track.mediaRef : '');
        const resolution = prepared !== null ? prepared :
          await NetEaseApi.resolvePlayback(context, track.neteaseId, playbackRef,
            (manual ? track.sourceSearchSession : track.automaticSearchSession) ?? '',
            (cancel: () => void): void => { this.setResolutionCancel(request, cancel); }, manual ? track.catalogRef ?? '' : '');
        if (!this.isCurrentRequest(request)) { return; }
        if (track.catalogRef !== undefined && track.catalogRef !== '' &&
          resolution.catalogRef !== track.catalogRef) {
          this.failRequest(request, 'IDENTITY_MISMATCH'); return;
        }
        if (manual && (resolution.playbackRef !== playbackRef || resolution.lyricsRef !== track.lyricsRef)) {
          this.failRequest(request, 'IDENTITY_MISMATCH'); return;
        }
        streamUrl = resolution.url;
        if (!manual) { track.playbackOutcome = resolution.playback; }
        track.audioIntegrity = resolution.audioIntegrity;
        if (resolution.playback !== undefined && resolution.playback.status !== 'success') {
          this.failRequest(request, 'PLAYBACK_' + resolution.playback.status.toUpperCase()); return;
        }
        if (streamUrl === '') { this.failRequest(request, 'EMPTY_URL'); return; }
        if (resolution.audioIntegrity?.status !== 'full') {
          this.failRequest(request, 'AUDIO_' + (resolution.audioIntegrity?.status ?? 'unknown').toUpperCase()); return;
        }
        track.playbackRef = resolution.playbackRef;
        track.lyricsRef = resolution.lyricsRef;
        track.playbackSource = resolution.playbackSource;
        track.lyricsSource = resolution.lyricsSource;
        if (!this.isCurrentRequest(request)) { return; }
        if (streamUrl === '') { this.failRequest(request, 'EMPTY_URL'); return; }
        track.streamUrl = streamUrl;
        if (manual) { this.notifyTrackMetadata(track); }
      } catch (err) {
        this.failRequest(request, err instanceof ApiError ? err.code : 'RESOLUTION');
        return;
      }
    }
    let abs = context.filesDir + '/' + track.path;
    if (!streaming) {
      // 播放前检查文件存在(issue-14:旧数据文件缺失时给出友好提示;兼容无 music/ 前缀的历史路径)
      try {
        if (!fileIo.accessSync(abs) && !track.path.startsWith('music/')) {
          const alt = context.filesDir + '/' + 'music/' + track.path;
          if (fileIo.accessSync(alt)) {
            abs = alt;
          }
        }
      } catch (err) {
        // 走下方统一检查
      }
      try {
        if (!fileIo.accessSync(abs)) {
          this.failRequest(request, 'FILE_MISSING');
          return;
        }
      } catch (err) {
        this.failRequest(request, 'FILE_MISSING');
        return;
      }
    }
    const callbacks: PlaybackCallbacks = {
      onStateChange: (s: PlayerState): void => {
        if (!this.isCurrentRequest(request)) { return; }
        this.state = s;
        if (s === PlayerState.PLAYING || s === PlayerState.PAUSED) {
          this.errorText = ''; this.errorCode = ''; this.recoveryAction = '';
        }
        this.syncBackground(true);
      },
      onPositionUpdate: (ms: number): void => {
        if (!this.isCurrentRequest(request)) { return; }
        this.positionMs = ms;
        this.checkSleepTimer();
        if (this.durationMs <= 0) {
          this.durationMs = session.getDuration();
        }
        if (this.positionTickHandler !== null) {
          this.positionTickHandler(ms);
        }
        if (this.state === PlayerState.PLAYING) {
          this.reportOnlineStats(ms);
        }
        this.syncBackground(false);
      },
      onTrackEnded: (): void => {
        if (!this.isCurrentRequest(request)) { return; }
        this.state = PlayerState.COMPLETED;
        this.syncBackground(true);
        if (this.endedHandler !== null) {
          this.endedHandler();
        }
      },
      onError: (msg: string): void => {
        this.failRequest(request, streaming ? 'MEDIA_READ_FAILED' : '');
      }
    };
    try {
      if (streaming) {
        await session.playUrl(streamUrl, callbacks);
      } else {
        await session.playFile(abs, callbacks);
      }
      if (!this.isCurrentRequest(request) || this.state === PlayerState.ERROR) { return; }
      session.setVolume(this.volume);
      if (startMs > 0) {
        session.seekTo(startMs);
      }
      this.syncBackground(true);
      if (this.sleepTimerPausePending) {
        this.sleepTimerPausePending = false;
        try {
          await this.pause();
        } catch (err) {
          if (this.isCurrentRequest(request)) { this.setSleepTimerPauseError(err as Error); }
        }
      }
      if (!this.isCurrentRequest(request)) { return; }
      // 播放历史自动记录(issue-09,500 条滚动淘汰)
      // 普通在线播放是瞬态负 ID，不写入本地播放历史；本地音轨才进入历史。
      if (track.id > 0) {
        LibraryStore.getInstance().insertHistory(track.id).catch(() => {
        });
      }
      if (this.isCurrentRequest(request) && this.playbackReadyHandler !== null) {
        try {
          this.playbackReadyHandler(request);
        } catch (err) {
          // 后台下载/封面补齐不影响已开始的音频播放。
        }
      }
    } catch (err) {
      this.failRequest(request, streaming ? 'MEDIA_READ_FAILED' : '');
      await session.release();
    }
  }

  /** 仅上报在线歌曲;本地导入歌曲不上传播放行为。 */
  private reportOnlineStats(positionMs: number): void {
    const request = this.requestVersion;
    const track = this.currentTrack;
    const context = this.lastContext;
    if (track === null || context === null || track.neteaseId <= 0 || this.statsReporting) {
      return;
    }
    const elapsedMs = positionMs - this.lastStatsReportedMs;
    if (elapsedMs < 30 * 1000) {
      return;
    }
    const seconds = Math.min(120, Math.floor(elapsedMs / 1000));
    this.statsReporting = true;
    DreamMusicAuth.reportStats(context, seconds, track.neteaseId)
      .then(() => {
        if (this.isCurrentRequest(request)) { this.lastStatsReportedMs += seconds * 1000; }
      })
      .catch(() => {
        // 统计失败不打断播放;下一个 30 秒窗口继续尝试。
      })
      .finally(() => {
        this.statsReporting = false;
      });
  }

  /** 启动恢复:只还原界面状态与进度,不打开文件;按播放时从断点续播 */
  restorePaused(track: Track, positionMs: number, context: common.Context): void {
    this.resolutionCancel?.();
    this.resolutionCancel = null;
    this.requestVersion++;
    this.session.release().catch(() => {});
    this.session = new PlayerSession();
    this.playbackReadyHandler = null;
    this.errorCode = '';
    this.recoveryAction = '';
    this.lastContext = context;
    this.currentTrack = track;
    this.positionMs = positionMs;
    this.durationMs = track.durationMs > 0 ? track.durationMs : 0;
    this.errorText = '';
    this.state = PlayerState.PAUSED;
    if (this.trackChangeHandler !== null) {
      this.trackChangeHandler(track);
    }
    if (this.coverColorHandler !== null) {
      this.coverColorHandler(track);
    }
    if (this.positionTickHandler !== null) {
      this.positionTickHandler(positionMs);
    }
    this.syncBackground(true);
  }

  async togglePause(): Promise<void> {
    const request = this.requestVersion;
    if (this.state === PlayerState.PLAYING) {
      await this.session.togglePause();
      if (!this.isCurrentRequest(request)) { return; }
      if (this.pausePositionHandler !== null) {
        this.pausePositionHandler(this.positionMs);
      }
    } else if (this.state === PlayerState.PAUSED || this.state === PlayerState.COMPLETED) {
      if (this.checkSleepTimer()) {
        return;
      }
      if (!this.session.isLoaded && this.currentTrack !== null && this.lastContext !== null) {
        // 恢复场景:重新打开文件并从断点播放
        await this.playTrack(this.currentTrack, this.lastContext, this.positionMs);
      } else {
        await this.session.togglePause();
      }
    }
  }

  async pause(): Promise<void> {
    const request = this.requestVersion;
    if (this.state !== PlayerState.PLAYING && !this.session.isPlaying) {
      return;
    }
    await this.session.pause();
    if (!this.isCurrentRequest(request)) { return; }
    if (this.pausePositionHandler !== null) {
      this.pausePositionHandler(this.positionMs);
    }
    this.syncBackground(true);
  }

  seekTo(ms: number): void {
    if (!Number.isFinite(ms) || this.currentTrack === null ||
      (this.state !== PlayerState.PLAYING && this.state !== PlayerState.PAUSED &&
        this.state !== PlayerState.COMPLETED)) { return; }
    const position = Math.max(0, Math.min(ms, this.durationMs > 0 ? this.durationMs : ms));
    this.session.seekTo(position);
    this.positionMs = position;
    if (this.positionTickHandler !== null) { this.positionTickHandler(position); }
    this.syncBackground(true);
    if (this.state !== PlayerState.PLAYING && this.pausePositionHandler !== null) {
      this.pausePositionHandler(position);
    }
  }

  setVolume(v: number): void {
    this.volume = v;
    this.session.setVolume(v);
  }

  get isPlaying(): boolean {
    return this.state === PlayerState.PLAYING;
  }
}

export const playerViewModel: PlayerViewModel = new PlayerViewModel();
