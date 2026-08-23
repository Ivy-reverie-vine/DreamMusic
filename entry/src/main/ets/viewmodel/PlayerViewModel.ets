import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlayerSession, PlaybackCallbacks } from '../service/playback/PlayerSession';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { LibraryStore } from '../service/library/LibraryStore';
import { PlayMode } from '../service/playback/QueueEngine';
import { PlayerState } from '../model/Playback';
import { Track } from '../model/Entities';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { SleepTimer, SleepTimerSnapshot } from '../service/playback/SleepTimer';

const DOMAIN = 0x0000;
const TAG = 'PlayerViewModel';

/** 播放状态容器(全局单例,音乐库页与正在播放页共享;队列域经钩子接管切歌) */
@Observed
export class PlayerViewModel {
  currentTrack: Track | null = null;
  state: PlayerState = PlayerState.IDLE;
  positionMs: number = 0;
  durationMs: number = 0;
  volume: number = 0.8;
  errorText: string = '';
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
      this.pause().catch((err: Error) => {
        this.setSleepTimerPauseError(err);
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

  private syncBackground(force: boolean): void {
    const bp = BackgroundPlayback.getInstance();
    bp.sync(this.currentTrack, this.state, this.positionMs, this.durationMs, this.playMode, force);
    if (this.state === PlayerState.PLAYING) {
      bp.startLongTask();
    } else if (this.state === PlayerState.PAUSED || this.state === PlayerState.COMPLETED ||
      this.state === PlayerState.IDLE) {
      bp.stopLongTask();
    }
  }

  async playTrack(track: Track, context: common.Context, startMs: number = 0): Promise<void> {
    if (this.sleepTimer.consumeIfDue()) {
      this.clearSleepTimerHandle();
      this.notifySleepTimerChanged();
    }
    this.sleepTimerPausePending = false;
    this.lastContext = context;
    this.currentTrack = track;
    this.errorText = '';
    this.positionMs = startMs;
    this.lastStatsReportedMs = startMs;
    this.durationMs = track.durationMs > 0 ? track.durationMs : 0;
    if (this.trackChangeHandler !== null) {
      this.trackChangeHandler(track);
    }
    if (this.coverColorHandler !== null) {
      this.coverColorHandler(track);
    }
    // 瞬态在线音轨:直链流式播放(阶段 v2.3),不检查本地文件
    const streaming = track.streamUrl !== undefined && track.streamUrl !== '';
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
          this.errorText = '文件缺失,请重新导入这首歌';
          this.state = PlayerState.ERROR;
          return;
        }
      } catch (err) {
        this.errorText = '文件缺失,请重新导入这首歌';
        this.state = PlayerState.ERROR;
        return;
      }
    }
    const callbacks: PlaybackCallbacks = {
      onStateChange: (s: PlayerState): void => {
        this.state = s;
        this.syncBackground(true);
      },
      onPositionUpdate: (ms: number): void => {
        this.positionMs = ms;
        this.checkSleepTimer();
        if (this.durationMs <= 0) {
          this.durationMs = this.session.getDuration();
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
        this.state = PlayerState.COMPLETED;
        if (this.endedHandler !== null) {
          this.endedHandler();
        }
      },
      onError: (msg: string): void => {
        this.errorText = msg;
      }
    };
    try {
      if (streaming) {
        await this.session.playUrl(track.streamUrl!, callbacks);
      } else {
        await this.session.playFile(abs, callbacks);
      }
      this.session.setVolume(this.volume);
      if (startMs > 0) {
        this.session.seekTo(startMs);
      }
      this.syncBackground(true);
      if (this.sleepTimerPausePending) {
        this.sleepTimerPausePending = false;
        try {
          await this.pause();
        } catch (err) {
          this.setSleepTimerPauseError(err as Error);
        }
      }
      // 播放历史自动记录(issue-09,500 条滚动淘汰)
      // 普通在线播放是瞬态负 ID，不写入本地播放历史；本地音轨才进入历史。
      if (track.id > 0) {
        LibraryStore.getInstance().insertHistory(track.id).catch(() => {
        });
      }
    } catch (err) {
      const e = err as Error;
      this.errorText = e.message;
      this.state = PlayerState.ERROR;
    }
  }

  /** 仅上报在线歌曲;本地导入歌曲不上传播放行为。 */
  private reportOnlineStats(positionMs: number): void {
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
        this.lastStatsReportedMs += seconds * 1000;
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
  }

  async togglePause(): Promise<void> {
    if (this.state === PlayerState.PLAYING) {
      await this.session.togglePause();
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
    if (this.state !== PlayerState.PLAYING && !this.session.isPlaying) {
      return;
    }
    await this.session.pause();
    if (this.pausePositionHandler !== null) {
      this.pausePositionHandler(this.positionMs);
    }
    this.syncBackground(true);
  }

  seekTo(ms: number): void {
    this.session.seekTo(ms);
    this.positionMs = ms;
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
