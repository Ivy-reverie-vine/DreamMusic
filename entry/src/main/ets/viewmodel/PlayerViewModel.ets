import { common } from '@kit.AbilityKit';
import { PlayerSession, PlaybackCallbacks } from '../service/playback/PlayerSession';
import { PlayerState } from '../model/Playback';
import { Track } from '../model/Entities';

/** 播放状态容器(全局单例,音乐库页与正在播放页共享) */
@Observed
export class PlayerViewModel {
  currentTrack: Track | null = null;
  state: PlayerState = PlayerState.IDLE;
  positionMs: number = 0;
  durationMs: number = 0;
  volume: number = 0.8;
  errorText: string = '';
  private session: PlayerSession = new PlayerSession();

  async playTrack(track: Track, context: common.Context): Promise<void> {
    this.currentTrack = track;
    this.errorText = '';
    this.positionMs = 0;
    this.durationMs = track.durationMs > 0 ? track.durationMs : 0;
    const abs = context.filesDir + '/' + track.path;
    const callbacks: PlaybackCallbacks = {
      onStateChange: (s: PlayerState): void => {
        this.state = s;
      },
      onPositionUpdate: (ms: number): void => {
        this.positionMs = ms;
        if (this.durationMs <= 0) {
          this.durationMs = this.session.getDuration();
        }
      },
      onTrackEnded: (): void => {
        this.state = PlayerState.COMPLETED;
        // issue-06 队列域在此接入自动切下一首
      },
      onError: (msg: string): void => {
        this.errorText = msg;
      }
    };
    try {
      await this.session.playFile(abs, callbacks);
      this.session.setVolume(this.volume);
    } catch (err) {
      const e = err as Error;
      this.errorText = e.message;
      this.state = PlayerState.ERROR;
    }
  }

  async togglePause(): Promise<void> {
    await this.session.togglePause();
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
