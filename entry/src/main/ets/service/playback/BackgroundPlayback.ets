import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Track } from '../../model/Entities';
import { PlayerState } from '../../model/Playback';
import { PlayMode } from '../playback/QueueEngine';

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

  // 系统播控命令处理器(由队列域注入)
  onPlayCommand: (() => void) | null = null;
  onPauseCommand: (() => void) | null = null;
  onNextCommand: (() => void) | null = null;
  onPrevCommand: (() => void) | null = null;
  onSeekCommand: ((ms: number) => void) | null = null;

  static getInstance(): BackgroundPlayback {
    if (BackgroundPlayback.instance === null) {
      BackgroundPlayback.instance = new BackgroundPlayback();
    }
    return BackgroundPlayback.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.session !== null) {
      return;
    }
    this.context = context;
    try {
      const session = await avSession.createAVSession(context, 'ivy_playback', 'audio');
      this.session = session;
      await session.activate();
      session.on('play', () => {
        if (this.onPlayCommand !== null) {
          this.onPlayCommand();
        }
      });
      session.on('pause', () => {
        if (this.onPauseCommand !== null) {
          this.onPauseCommand();
        }
      });
      session.on('stop', () => {
        if (this.onPauseCommand !== null) {
          this.onPauseCommand();
        }
      });
      session.on('playNext', () => {
        if (this.onNextCommand !== null) {
          this.onNextCommand();
        }
      });
      session.on('playPrevious', () => {
        if (this.onPrevCommand !== null) {
          this.onPrevCommand();
        }
      });
      session.on('seek', (time: number) => {
        if (this.onSeekCommand !== null) {
          this.onSeekCommand(time);
        }
      });
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: BUNDLE_NAME, abilityName: ABILITY_NAME }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      };
      this.agent = await wantAgent.getWantAgent(info);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', e.message);
    }
  }

  async startLongTask(): Promise<void> {
    if (this.context === null || this.agent === null || this.longTaskRunning) {
      return;
    }
    try {
      await backgroundTaskManager.startBackgroundRunning(this.context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, this.agent);
      this.longTaskRunning = true;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed: %{public}s', e.message);
    }
  }

  async stopLongTask(): Promise<void> {
    if (this.context === null || !this.longTaskRunning) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
      this.longTaskRunning = false;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', e.message);
    }
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

  /** 同步媒体信息与播放状态到系统会话;positionSync 节流 1s */
  async sync(track: Track | null, state: PlayerState, positionMs: number,
    durationMs: number, mode: PlayMode, force: boolean = false): Promise<void> {
    const s = this.session;
    if (s === null) {
      return;
    }
    const now = Date.now();
    if (!force && now - this.lastPositionSync < 1000 && track !== null) {
      return;
    }
    this.lastPositionSync = now;
    try {
      if (track !== null) {
        const cover = await this.loadCover(track);
        const meta: avSession.AVMetadata = {
          assetId: String(track.id),
          title: track.title !== '' ? track.title : track.path,
          artist: track.artist,
          album: track.album,
          duration: durationMs,
          avQueueName: '音乐队列'
        };
        if (cover !== null) {
          meta.mediaImage = cover;
        }
        await s.setAVMetadata(meta);
      }
      const pbState: avSession.AVPlaybackState = {
        state: BackgroundPlayback.mapState(state),
        speed: 1,
        position: { elapsedTime: positionMs, updateTime: now },
        loopMode: BackgroundPlayback.mapLoop(mode)
      };
      await s.setAVPlaybackState(pbState);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'sync failed: %{public}s', e.message);
    }
  }

  private async loadCover(track: Track): Promise<image.PixelMap | null> {
    if (track.coverPath === '' || this.context === null) {
      return null;
    }
    try {
      const uri = 'file://' + this.context.filesDir + '/' + track.coverPath;
      const source: image.ImageSource = image.createImageSource(uri);
      const pm = await source.createPixelMap({ desiredSize: { width: 512, height: 512 } });
      return pm;
    } catch (err) {
      return null;
    }
  }
}
