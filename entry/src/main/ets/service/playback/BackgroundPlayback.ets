import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, common } from '@kit.AbilityKit';
import { CoverArtService, CoverLease } from '../cover/CoverArtService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Track } from '../../model/Entities';
import { PlayerState } from '../../model/Playback';
import { PlayMode } from '../playback/QueueEngine';
import { PLAYBACK_DESTINATION } from '../../model/PlaybackLaunch';
import { DesktopLyrics } from '../lyrics/DesktopLyrics';

const DOMAIN = 0x0000;
const TAG = 'BackgroundPlayback';
const BUNDLE_NAME = 'com.example.ivyreveriemusic';
const ABILITY_NAME = 'EntryAbility';

/**
 * 后台播控适配层(issue-07,真机验证项):
 * AVSession(锁屏/控制中心媒体信息与播控命令)+ audioPlayback 长时任务。
 * API 对照 SDK d.ts 核实:createAVSession(context, tag, 'audio')/activate/
 * setAVMetadata/setAVPlaybackState(PlaybackPosition)/on('play'|'pause'|'playNext'|...)、
 * backgroundTaskManager.startBackgroundRunning(context, BackgroundMode.AUDIO_PLAYBACK, wantAgent)、
 * wantAgent.getWantAgent(WantAgentInfo)。
 */
export class BackgroundPlayback {
  private static instance: BackgroundPlayback | null = null;
  private session: avSession.AVSession | null = null;
  private context: common.Context | null = null;
  /** WantAgent 类型在 @ohos.wantAgent 为 type WantAgent = object,此处以 object 承载 */
  private agent: object | null = null;
  private longTaskRunning: boolean = false;
  private lastPositionSync: number = 0;
  private metadataSignature: string = '';
  private metadataRevision: number = 0;
  private artworkIdentity: string = '';
  private metadataChain: Promise<void> = Promise.resolve();
  private artwork: CoverLease | null = null;
  private initializing: Promise<void> | null = null;
  private releasing: boolean = false;
  private longTaskWanted: boolean = false;
  private longTaskChain: Promise<void> = Promise.resolve();
  private stateChain: Promise<void> = Promise.resolve();
  private stateRevision: number = 0;
  private stateSignature: string = '';
  private commandChain: Promise<void> = Promise.resolve();
  private lyricIdentity: string = '';
  private lyric: string = '';

  // 系统播控命令处理器(由队列域注入)
  onPlayCommand: (() => Promise<void>) | null = null;
  onPauseCommand: (() => Promise<void>) | null = null;
  onNextCommand: (() => Promise<void>) | null = null;
  onPrevCommand: (() => Promise<void>) | null = null;
  onSeekCommand: ((ms: number) => void) | null = null;

  static getInstance(): BackgroundPlayback {
    if (BackgroundPlayback.instance === null) {
      BackgroundPlayback.instance = new BackgroundPlayback();
    }
    return BackgroundPlayback.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.releasing || this.session !== null) { return; }
    if (this.initializing !== null) { return this.initializing; }
    this.initializing = this.createSession(context);
    try { await this.initializing; } finally { this.initializing = null; }
  }

  private enqueueCommand(session: avSession.AVSession, command: (() => Promise<void>) | null): void {
    this.commandChain = this.commandChain.then(async () => {
      if (this.releasing || this.session !== session || command === null) { return; }
      await command();
    }).catch(() => { hilog.warn(DOMAIN, TAG, 'system command failed'); });
  }

  private async createSession(context: common.Context): Promise<void> {
    this.context = context;
    let session: avSession.AVSession | null = null;
    try {
      session = await avSession.createAVSession(context, 'ivy_playback', 'audio');
      const created = session;
      session.on('play', () => {
        this.enqueueCommand(created, this.onPlayCommand);
      });
      session.on('pause', () => {
        this.enqueueCommand(created, this.onPauseCommand);
      });
      session.on('stop', () => {
        this.enqueueCommand(created, this.onPauseCommand);
      });
      session.on('playNext', () => {
        this.enqueueCommand(created, this.onNextCommand);
      });
      session.on('playPrevious', () => {
        this.enqueueCommand(created, this.onPrevCommand);
      });
      session.on('seek', (time: number) => {
        this.enqueueCommand(created, async () => {
          if (this.onSeekCommand !== null) { this.onSeekCommand(time); }
        });
      });
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: BUNDLE_NAME, abilityName: ABILITY_NAME,
          parameters: { 'dreammusic.destination': PLAYBACK_DESTINATION } }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 15,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await session.setLaunchAbility(agent);
      await session.activate();
      this.agent = agent;
      this.session = session;
      // 桌面歌词探测和恢复不阻塞会话或 audioPlayback。
      DesktopLyrics.getInstance().attach(context, session);
      await this.reconcileLongTask();
    } catch (err) {
      if (session !== null) { await session.destroy().catch(() => {}); }
      this.session = null;
      this.agent = null;
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', e.message);
    }
  }

  async startLongTask(): Promise<void> {
    if (this.releasing) { return; }
    this.longTaskWanted = true;
    await this.reconcileLongTask();
  }

  async stopLongTask(): Promise<void> {
    this.longTaskWanted = false;
    await this.reconcileLongTask();
  }

  private reconcileLongTask(): Promise<void> {
    this.longTaskChain = this.longTaskChain.then(async () => {
      const context = this.context;
      const agent = this.agent;
      if (context === null || agent === null) { return; }
      // 每次 await 后重新核对最新意图，暂停不会被迟到的 start 覆盖。
      while (this.longTaskRunning !== (this.longTaskWanted && !this.releasing)) {
        if (this.longTaskWanted && !this.releasing) {
          await backgroundTaskManager.startBackgroundRunning(context,
            backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
          this.longTaskRunning = true;
        } else {
          await backgroundTaskManager.stopBackgroundRunning(context);
          this.longTaskRunning = false;
        }
      }
    }).catch(() => { hilog.warn(DOMAIN, TAG, 'background task update failed'); });
    return this.longTaskChain;
  }

  private static mapState(s: PlayerState): avSession.PlaybackState {
    switch (s) {
      case PlayerState.PLAYING:
        return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
      case PlayerState.PAUSED:
        return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
      case PlayerState.PREPARING:
        return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
      case PlayerState.COMPLETED:
        return avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
      case PlayerState.ERROR:
        return avSession.PlaybackState.PLAYBACK_STATE_ERROR;
      default:
        return avSession.PlaybackState.PLAYBACK_STATE_INITIAL;
    }
  }

  private static mapLoop(mode: PlayMode): avSession.LoopMode {
    switch (mode) {
      case PlayMode.REPEAT_ONE:
        return avSession.LoopMode.LOOP_MODE_SINGLE;
      case PlayMode.REPEAT_ALL:
        return avSession.LoopMode.LOOP_MODE_LIST;
      case PlayMode.SHUFFLE:
        return avSession.LoopMode.LOOP_MODE_SHUFFLE;
      default:
        return avSession.LoopMode.LOOP_MODE_SEQUENCE;
    }
  }

  /** 歌词快照与来源身份绑定，不能把上一首歌词带到新音轨。 */
  setLyrics(track: Track | null, lyric: string): void {
    this.lyricIdentity = CoverArtService.identity(track);
    this.lyric = track !== null ? lyric : '';
  }

  /** 同步媒体信息与播放状态到系统会话;positionSync 节流 1s */
  async sync(track: Track | null, state: PlayerState, positionMs: number,
    durationMs: number, mode: PlayMode, force: boolean = false): Promise<void> {
    const s = this.session;
    if (s === null || this.releasing) {
      return;
    }
    const now = Date.now();
    const context = this.context;
    const uri = context !== null ? CoverArtService.resolve(context, track) : '';
    const lyric = this.lyricIdentity === CoverArtService.identity(track) ? this.lyric : '';
    const desktopLyrics = DesktopLyrics.getInstance();
    if (lyric === '' || state === PlayerState.ERROR || state === PlayerState.IDLE) {
      desktopLyrics.setContentAvailable(false);
    }
    const signature = track !== null
      ? JSON.stringify([track.mediaRef, track.id, track.path, track.title, track.artist, track.album, durationMs, uri, lyric,
        state === PlayerState.ERROR || state === PlayerState.IDLE])
      : 'empty';
    // 进度和播放状态不等待封面；同一媒体信息只申请一次封面。
    if (context !== null && signature !== this.metadataSignature) {
      this.metadataSignature = signature;
      const revision = ++this.metadataRevision;
      const identity = CoverArtService.identity(track);
      const resetArtwork = identity === '' || identity !== this.artworkIdentity;
      const meta: avSession.AVMetadata = {
        assetId: track !== null ? (track.mediaRef !== undefined && track.mediaRef !== ''
          ? track.mediaRef : String(track.id)) : '',
        title: track !== null ? (track.title !== '' ? track.title : track.path) : '',
        artist: track !== null ? track.artist : '',
        album: track !== null ? track.album : '',
        duration: durationMs,
        lyric: lyric,
        avQueueName: '音乐队列'
      };
      // 歌词先于封面下载提交，并与封面共用同一条元数据写队列。
      const metadataTask = this.metadataChain.then(async () => {
        if (revision !== this.metadataRevision || this.session !== s) { return; }
        meta.mediaImage = !resetArtwork && this.artwork?.pixelMap !== null
          ? (this.artwork?.pixelMap ?? '') : '';
        await s.setAVMetadata(meta);
        if (revision === this.metadataRevision && this.session === s) {
          desktopLyrics.setContentAvailable(lyric !== '' && state !== PlayerState.ERROR && state !== PlayerState.IDLE);
        }
      });
      this.metadataChain = metadataTask.catch(() => {});
      metadataTask.then(() => this.updateArtwork(context, s, meta, uri, revision, resetArtwork, identity)).catch(() => {
        if (revision === this.metadataRevision) {
          this.metadataSignature = '';
        }
      });
    }
    const stateSignature = JSON.stringify([track?.id, track?.mediaRef, state, mode]);
    if (!force && stateSignature === this.stateSignature && now - this.lastPositionSync < 1000) {
      return;
    }
    this.lastPositionSync = now;
    this.stateSignature = stateSignature;
    const stateRevision = ++this.stateRevision;
    const task = this.stateChain.then(async () => {
      if (this.releasing || this.session !== s || stateRevision !== this.stateRevision) { return; }
      const pbState: avSession.AVPlaybackState = {
        state: BackgroundPlayback.mapState(state),
        speed: 1,
        position: { elapsedTime: positionMs, updateTime: now },
        loopMode: BackgroundPlayback.mapLoop(mode)
      };
      await s.setAVPlaybackState(pbState);
    }).catch(() => {
      if (stateRevision === this.stateRevision) { this.stateSignature = ''; }
      hilog.warn(DOMAIN, TAG, 'state sync failed');
    });
    this.stateChain = task;
    await task;
  }

  private async updateArtwork(context: common.Context, session: avSession.AVSession,
    meta: avSession.AVMetadata, uri: string, revision: number, resetArtwork: boolean,
    identity: string): Promise<void> {
    const covers = CoverArtService.getInstance();
    // 新音轨先明确清掉旧封面，远程加载再慢也不显示上一首的图。
    if (resetArtwork || uri === '') {
      const placeholder = await covers.acquire(context, '', 512);
      await this.commitArtwork(session, meta, placeholder, revision, identity);
    }
    if (uri === '' || revision !== this.metadataRevision || this.session !== session) {
      return;
    }
    const cover = await covers.acquire(context, uri, 512);
    await this.commitArtwork(session, meta, cover, revision, identity);
  }

  private commitArtwork(session: avSession.AVSession, meta: avSession.AVMetadata,
    lease: CoverLease, revision: number, identity: string): Promise<void> {
    // setAVMetadata 也串行；已开始的旧写入完成后，新音轨写入一定在其后。
    const task = this.metadataChain.then(async () => {
      if (revision !== this.metadataRevision || this.session !== session) {
        lease.release();
        return;
      }
      try {
        meta.mediaImage = lease.pixelMap !== null ? lease.pixelMap : '';
        await session.setAVMetadata(meta);
        const previous = this.artwork;
        this.artwork = lease;
        this.artworkIdentity = identity;
        if (previous !== null) {
          previous.release();
        }
      } catch (err) {
        lease.release();
        if (err instanceof Error) {
          throw err;
        }
        throw new Error('AVSession artwork update failed');
      }
    });
    this.metadataChain = task.catch(() => {});
    return task;
  }

  async release(): Promise<void> {
    this.releasing = true;
    this.longTaskWanted = false;
    if (this.initializing !== null) { await this.initializing; }
    this.metadataRevision++;
    this.stateRevision++;
    this.stateSignature = '';
    this.metadataSignature = '';
    this.artworkIdentity = '';
    const session = this.session;
    this.session = null;
    await DesktopLyrics.getInstance().detach();
    await this.metadataChain;
    await this.stateChain;
    await this.stopLongTask();
    if (session !== null) {
      try {
        await session.destroy();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'session destroy failed');
      }
    }
    if (this.artwork !== null) {
      this.artwork.release();
      this.artwork = null;
    }
    this.context = null;
    this.agent = null;
    this.lastPositionSync = 0;
    this.releasing = false;
  }
}
