import { playerViewModel } from './PlayerViewModel';

/** 播控执行期间忽略重复点击，避免 AVPlayer 的准备/切歌/暂停调用重叠。 */
@Observed
export class PlaybackControlGate {
  busy: boolean = false;

  async run(command: () => Promise<void>): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const request = playerViewModel.requestId;
    try {
      await command();
    } catch (err) {
      playerViewModel.failRequest(request);
    } finally {
      this.busy = false;
    }
  }
}

export const playbackControlGate: PlaybackControlGate = new PlaybackControlGate();
