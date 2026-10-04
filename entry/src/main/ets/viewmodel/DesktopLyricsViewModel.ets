import { DesktopLyrics, DesktopLyricsSnapshot } from '../service/lyrics/DesktopLyrics';

@Observed
export class DesktopLyricsViewModel {
  enabled: boolean = false;
  visible: boolean = true;
  locked: boolean = false;
  supported: boolean = false;
  busy: boolean = false;
  canRetry: boolean = false;
  status: string = '等待播放会话就绪';

  constructor() {
    const service = DesktopLyrics.getInstance();
    service.onChange = (snapshot: DesktopLyricsSnapshot): void => this.update(snapshot);
    this.update(service.snapshot);
  }

  private update(snapshot: DesktopLyricsSnapshot): void {
    this.enabled = snapshot.enabled;
    this.visible = snapshot.visible;
    this.locked = snapshot.locked;
    this.supported = snapshot.supported;
    this.busy = snapshot.busy;
    this.canRetry = snapshot.canRetry;
    this.status = snapshot.status;
  }

  setEnabled(value: boolean): void { DesktopLyrics.getInstance().setEnabled(value); }
  setVisible(value: boolean): void { DesktopLyrics.getInstance().setVisible(value); }
  setLocked(value: boolean): void { DesktopLyrics.getInstance().setLocked(value); }
  retry(): void { DesktopLyrics.getInstance().retry(); }
}

export const desktopLyricsViewModel: DesktopLyricsViewModel = new DesktopLyricsViewModel();
