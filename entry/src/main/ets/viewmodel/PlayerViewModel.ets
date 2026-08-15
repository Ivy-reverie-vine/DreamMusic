import { common } from '@kit.AbilityKit';
import { PlayerSession, PlaybackCallbacks } from '../service/playback/PlayerSession';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { LibraryStore } from '../service/library/LibraryStore';
import { PlayMode } from '../service/playback/QueueEngine';
import { PlayerState } from '../model/Playback';
import { Track } from '../model/Entities';

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
  private session: PlayerSession = new PlayerSession();
  private lastContext: common.Context | null = null;

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
    this.lastContext = context;
    this.currentTrack = track;
    this.errorText = '';
    this.positionMs = startMs;
    this.durationMs = track.durationMs > 0 ? track.durationMs : 0;
    if (this.trackChangeHandler !== null) {
      this.trackChangeHandler(track);
    }
    const abs = context.filesDir + '/' + track.path;
    const callbacks: PlaybackCallbacks = {
      onStateChange: (s: PlayerState): void => {
        this.state = s;
        this.syncBackground(true);
      },
      onPositionUpdate: (ms: number): void => {
        this.positionMs = ms;
        if (this.durationMs <= 0) {
          this.durationMs = this.session.getDuration();
        }
        if (this.positionTickHandler !== null) {
          this.positionTickHandler(ms);
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
      await this.session.playFile(abs, callbacks);
      this.session.setVolume(this.volume);
      if (startMs > 0) {
        this.session.seekTo(startMs);
      }
      this.syncBackground(true);
      // 播放历史自动记录(issue-09,500 条滚动淘汰)
      LibraryStore.getInstance().insertHistory(track.id).catch(() => {
      });
    } catch (err) {
      const e = err as Error;
      this.errorText = e.message;
      this.state = PlayerState.ERROR;
    }
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
      if (!this.session.isLoaded && this.currentTrack !== null && this.lastContext !== null) {
        // 恢复场景:重新打开文件并从断点播放
        await this.playTrack(this.currentTrack, this.lastContext, this.positionMs);
      } else {
        await this.session.togglePause();
      }
    }
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
