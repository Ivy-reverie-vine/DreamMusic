import { common } from '@kit.AbilityKit';
import { queueViewModel } from './QueueViewModel';
import { playerViewModel } from './PlayerViewModel';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { MusicFormPublisher } from '../service/form/MusicFormPublisher';
import { PlayerState } from '../model/Playback';
import { isMusicCardCommand } from '../model/MusicCard';
import { lyricsViewModel } from './LyricsViewModel';
import { desktopLrc } from '../service/lyrics/DesktopLyrics';

/** 页面、冷启动 call 共用一次恢复；后台操作不依赖页面生命周期。 */
export class PlaybackRuntime {
  private ready: Promise<void> | null = null;
  private publisher: MusicFormPublisher | null = null;
  private commandChain: Promise<void> = Promise.resolve();
  private generation: number = 0;

  ensureReady(context: common.Context): Promise<void> {
    if (this.ready !== null) { return this.ready; }
    this.publisher = new MusicFormPublisher(context);
    playerViewModel.playbackChangedHandler = () => this.publish();
    this.ready = this.initialize(context).catch((err: Error) => {
      this.ready = null;
      throw err;
    });
    return this.ready;
  }

  private async initialize(context: common.Context): Promise<void> {
    lyricsViewModel.lyricsChangedHandler = () => {
      BackgroundPlayback.getInstance().setLyrics(playerViewModel.currentTrack,
        lyricsViewModel.timelineTrusted ? desktopLrc(lyricsViewModel.lines) : '');
      playerViewModel.refreshBackground();
    };
    lyricsViewModel.setContext(context);
    await queueViewModel.restore(context);
    await BackgroundPlayback.getInstance().init(context);
    BackgroundPlayback.getInstance().setLyrics(playerViewModel.currentTrack,
      lyricsViewModel.timelineTrusted ? desktopLrc(lyricsViewModel.lines) : '');
    playerViewModel.refreshBackground();
  }

  private publish(): void {
    const vm = playerViewModel;
    this.publisher?.sync(vm.currentTrack, vm.state.toLowerCase(), vm.statusText,
      vm.currentTrack !== null && vm.state !== PlayerState.PREPARING &&
      !(vm.state === PlayerState.ERROR && (vm.recoveryAction === 'library' || vm.recoveryAction === 'settings')));
  }

  dispatch(context: common.Context, command: string): Promise<void> {
    if (!isMusicCardCommand(command)) { return Promise.resolve(); }
    const generation = this.generation;
    this.commandChain = this.commandChain.then(async () => {
      if (generation !== this.generation) { return; }
      await this.ensureReady(context);
      if (generation !== this.generation || playerViewModel.currentTrack === null ||
        playerViewModel.state === PlayerState.PREPARING) { return; }
      const vm = playerViewModel;
      if (command === 'pause') { await vm.pause(); }
      else if (vm.checkSleepTimer()) { return; }
      else if (command === 'play') {
        if (vm.state === PlayerState.ERROR && vm.recoveryAction === 'retry') { await vm.retry(); }
        else if (vm.state === PlayerState.PAUSED || vm.state === PlayerState.COMPLETED) { await vm.togglePause(); }
      } else if (command === 'previous') { await queueViewModel.playPrev(); }
      else if (command === 'next') { await queueViewModel.playNext(); }
    }).catch(() => {
      // 音频/在线错误沿既有 PlayerViewModel 恢复边界展示，不阻断后续命令。
    }).finally(() => this.publish());
    return this.commandChain;
  }

  async dispose(): Promise<void> {
    this.generation++;
    const stopped = playerViewModel.dispose();
    lyricsViewModel.dispose();
    await this.commandChain;
    if (this.ready !== null) { await this.ready.catch(() => {}); }
    await stopped;
    // A pending persisted restore may have projected a paused track during teardown.
    if (playerViewModel.currentTrack !== null) { await playerViewModel.dispose(); }
    lyricsViewModel.dispose();
    playerViewModel.playbackChangedHandler = null;
    lyricsViewModel.lyricsChangedHandler = null;
    await this.publisher?.dispose();
    this.publisher = null;
    this.ready = null;
  }
}

export const playbackRuntime: PlaybackRuntime = new PlaybackRuntime();
