/** 系统播控和后续桌面卡片共用的目的地；只导航，不触发自动播放。 */
export const PLAYBACK_DESTINATION_KEY: string = 'dreammusic.destination';
export const PLAYBACK_DESTINATION: string = 'now-playing';
export const PLAYLIST_DESTINATION: string = 'local-playlist';
export const PLAYLIST_ID_KEY: string = 'dreammusic.playlistId';

export interface ExternalDestination {
  destination: string;
  playlistId: number;
}

/** 冷启动先暂存，主壳挂载后消费；前后台已有主壳时直接派发。 */
export class PlaybackLaunch {
  private pending: boolean = false;
  private handler: ((target: ExternalDestination) => void) | null = null;
  private target: ExternalDestination = { destination: PLAYBACK_DESTINATION, playlistId: 0 };

  request(destination: string, playlistId: number = 0): void {
    if (destination !== PLAYBACK_DESTINATION && destination !== PLAYLIST_DESTINATION) { return; }
    if (destination === PLAYLIST_DESTINATION && (!Number.isSafeInteger(playlistId) || playlistId < 0)) { return; }
    this.target = { destination: destination, playlistId: playlistId };
    this.pending = true;
    this.deliver();
  }

  attach(handler: (target: ExternalDestination) => void): void {
    this.handler = handler;
    this.deliver();
  }

  detach(): void { this.handler = null; }

  private deliver(): void {
    if (!this.pending || this.handler === null) { return; }
    this.pending = false;
    this.handler(this.target);
  }
}

export const playbackLaunch: PlaybackLaunch = new PlaybackLaunch();
