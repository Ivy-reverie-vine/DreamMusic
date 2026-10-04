import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { LyricLine } from './LrcParser';

export interface DesktopLyricsSnapshot {
  enabled: boolean;
  visible: boolean;
  locked: boolean;
  supported: boolean;
  busy: boolean;
  canRetry: boolean;
  status: string;
}

/** 使用已经解析的时间轴，不请求另一份歌词；保留毫秒精度。 */
export function desktopLrc(lines: LyricLine[]): string {
  if (!lines.some((line: LyricLine) => line.text.trim() !== '')) { return ''; }
  return lines.map((line: LyricLine): string => {
    const ms = Math.max(0, Math.floor(line.timeMs));
    return '[' + String(Math.floor(ms / 60000)).padStart(2, '0') + ':' +
      String(Math.floor(ms / 1000) % 60).padStart(2, '0') + '.' +
      String(ms % 1000).padStart(3, '0') + ']' + line.text.replace(/[\r\n]/g, ' ');
  }).join('\n');
}

/** 桌面歌词失败只影响自身。所有原生操作串行，销毁前先排空并注销监听。 */
export class DesktopLyrics {
  private static instance: DesktopLyrics | null = null;
  private prefs: preferences.Preferences | null = null;
  private context: common.Context | null = null;
  private session: avSession.AVSession | null = null;
  private controller: avSession.AVSessionController | null = null;
  private chain: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private supported: boolean = false;
  private failed: boolean = false;
  private unsupported: boolean = false;
  private applying: boolean = false;
  private loaded: boolean = false;
  private wantedEnabled: boolean = false;
  private wantedVisible: boolean = true;
  private wantedLocked: boolean = false;
  private actualEnabled: boolean = false;
  private actualVisible: boolean = false;
  private actualLocked: boolean = false;
  private hasLyrics: boolean = false;
  private error: string = '';
  private storageError: string = '';
  private saveVersion: number = 0;
  private enabledListener: ((enabled: boolean) => void) | null = null;
  private visibleListener: ((visible: boolean) => void) | null = null;
  private stateListener: ((state: avSession.DesktopLyricState) => void) | null = null;
  onChange: ((snapshot: DesktopLyricsSnapshot) => void) | null = null;

  static getInstance(): DesktopLyrics {
    if (DesktopLyrics.instance === null) { DesktopLyrics.instance = new DesktopLyrics(); }
    return DesktopLyrics.instance;
  }

  get snapshot(): DesktopLyricsSnapshot {
    let status = this.error;
    if (status === '') {
      if (this.session === null) { status = '等待播放会话就绪'; }
      else if (!this.supported) { status = '正在检查设备支持情况'; }
      else if (this.applying) { status = '正在更新桌面歌词…'; }
      else if (!this.actualEnabled) { status = '已关闭'; }
      else if (!this.hasLyrics) { status = '当前暂无歌词，已自动隐藏'; }
      else if (!this.actualVisible) { status = '已隐藏'; }
      else { status = this.actualLocked ? '已显示 · 已锁定' : '已显示 · 可移动'; }
    }
    return { enabled: this.wantedEnabled, visible: this.wantedVisible, locked: this.wantedLocked,
      supported: this.supported, busy: this.applying, canRetry: this.failed && !this.unsupported,
      status: this.storageError !== '' ? status + '；' + this.storageError : status };
  }

  private publish(): void { this.onChange?.(this.snapshot); }

  private load(context: common.Context): void {
    if (this.loaded) { return; }
    try {
      this.prefs = preferences.getPreferencesSync(context, { name: 'desktop_lyrics' });
      this.wantedEnabled = this.prefs.getSync('enabled', false) === true;
      this.wantedVisible = this.prefs.getSync('visible', true) === true;
      this.wantedLocked = this.prefs.getSync('locked', false) === true;
      this.loaded = true;
      this.storageError = '';
    } catch (err) {
      this.prefs = null;
      this.wantedEnabled = false;
      this.wantedVisible = true;
      this.wantedLocked = false;
      this.storageError = '设置读取失败，本次默认关闭';
    }
  }

  private save(): void {
    const version = ++this.saveVersion;
    try {
      if (this.prefs === null) { this.storageError = '设置暂时无法保存'; return; }
      this.prefs.putSync('enabled', this.wantedEnabled);
      this.prefs.putSync('visible', this.wantedVisible);
      this.prefs.putSync('locked', this.wantedLocked);
      this.prefs.flush().then(() => {
        if (version === this.saveVersion) { this.storageError = ''; this.publish(); }
      }).catch(() => {
        if (version === this.saveVersion) { this.storageError = '设置保存失败，重启后可能无法恢复'; this.publish(); }
      });
    } catch (err) { this.storageError = '设置保存失败，重启后可能无法恢复'; }
  }

  attach(context: common.Context, session: avSession.AVSession): Promise<void> {
    if (this.session === session) { return this.chain; }
    this.load(context);
    this.context = context;
    this.session = session;
    const generation = ++this.generation;
    this.failed = false;
    this.unsupported = false;
    this.error = '';
    this.supported = false;
    this.publish();
    this.chain = this.chain.then(async () => {
      if (generation !== this.generation) { return; }
      try {
        this.supported = await avSession.isDesktopLyricSupported();
        if (generation !== this.generation) { return; }
        if (!this.supported) { this.unsupported = true; this.error = '当前设备不支持系统桌面歌词'; return; }
        const controller = await session.getController();
        if (generation !== this.generation) { await controller.destroy().catch(() => {}); return; }
        this.controller = controller;
        this.enabledListener = (enabled: boolean): void => {
          if (generation !== this.generation) { return; }
          this.actualEnabled = enabled;
          if (!this.applying && enabled !== this.wantedEnabled) {
            this.wantedEnabled = enabled;
            this.save();
            this.reconcile();
          }
          this.publish();
        };
        this.visibleListener = (visible: boolean): void => {
          if (generation !== this.generation) { return; }
          this.actualVisible = visible;
          // 自动隐藏（无歌词/关闭）不改变用户对下一首的显示意愿。
          if (!this.applying && this.hasLyrics && this.actualEnabled) {
            this.wantedVisible = visible;
            this.save();
          }
          this.publish();
        };
        this.stateListener = (state: avSession.DesktopLyricState): void => {
          if (generation !== this.generation) { return; }
          this.actualLocked = state.isLocked;
          if (!this.applying) { this.wantedLocked = state.isLocked; this.save(); }
          this.publish();
        };
        controller.onDesktopLyricEnabled(this.enabledListener);
        session.onDesktopLyricVisibilityChanged(this.visibleListener);
        session.onDesktopLyricStateChanged(this.stateListener);
        this.actualEnabled = await controller.isDesktopLyricEnabled();
        if (generation !== this.generation) { return; }
        await this.apply(session, generation);
      } catch (err) {
        if (generation === this.generation) {
          await this.unregister(session);
          this.fail(err as BusinessError);
        }
      }
      finally { this.publish(); }
    });
    return this.chain;
  }

  setEnabled(enabled: boolean): void {
    this.wantedEnabled = enabled;
    this.save();
    this.retry();
  }

  setVisible(visible: boolean): void {
    this.wantedVisible = visible;
    this.save();
    this.retry();
  }

  setLocked(locked: boolean): void {
    this.wantedLocked = locked;
    this.save();
    this.retry();
  }

  retry(): void {
    if (this.failed && !this.unsupported && this.controller === null && this.session !== null && this.context !== null) {
      const session = this.session;
      this.session = null;
      this.attach(this.context, session);
      return;
    }
    if (!this.supported) { this.publish(); return; }
    this.failed = false;
    this.error = '';
    this.reconcile();
  }

  setContentAvailable(available: boolean): void {
    if (available === this.hasLyrics) { return; }
    this.hasLyrics = available;
    this.reconcile();
  }

  private reconcile(): void {
    const session = this.session;
    const generation = this.generation;
    this.publish();
    this.chain = this.chain.then(async () => {
      if (session === null || generation !== this.generation || !this.supported || this.failed) { return; }
      try { await this.apply(session, generation); }
      catch (err) { if (generation === this.generation) { this.fail(err as BusinessError); } }
      finally { this.publish(); }
    });
  }

  private async apply(session: avSession.AVSession, generation: number): Promise<void> {
    this.applying = true;
    this.publish();
    try {
      const enabled = this.wantedEnabled;
      // 开启后立即按当前歌词和用户意愿同步窗口。
      await session.enableDesktopLyric(enabled);
      if (generation !== this.generation) { return; }
      this.actualEnabled = enabled;
      if (!enabled) { this.actualVisible = false; return; }
      await session.setDesktopLyricVisible(this.wantedVisible && this.hasLyrics);
      if (generation !== this.generation) { return; }
      await session.setDesktopLyricState({ isLocked: this.wantedLocked });
      if (generation !== this.generation) { return; }
      this.actualVisible = await session.isDesktopLyricVisible();
      if (generation !== this.generation) { return; }
      this.actualLocked = (await session.getDesktopLyricState()).isLocked;
    } finally { this.applying = false; }
  }

  private fail(err: BusinessError): void {
    this.failed = true;
    if (err?.code === 6600111 || err?.code === 801) {
      this.unsupported = true;
      this.supported = false;
      this.error = '当前设备不支持系统桌面歌词';
    } else {
      this.error = '桌面歌词暂时不可用，可重试；音乐播放不受影响';
    }
  }

  private async unregister(session: avSession.AVSession | null): Promise<void> {
    // 分别清理，单个 off 失败不能跳过其余监听。
    try { if (this.enabledListener !== null) { this.controller?.offDesktopLyricEnabled(this.enabledListener); } } catch (err) {}
    try { if (this.visibleListener !== null) { session?.offDesktopLyricVisibilityChanged(this.visibleListener); } } catch (err) {}
    try { if (this.stateListener !== null) { session?.offDesktopLyricStateChanged(this.stateListener); } } catch (err) {}
    const controller = this.controller;
    this.controller = null;
    this.enabledListener = null;
    this.visibleListener = null;
    this.stateListener = null;
    if (controller !== null) { await controller.destroy().catch(() => {}); }
  }

  async detach(): Promise<void> {
    ++this.generation;
    const session = this.session;
    this.session = null;
    await this.chain;
    await this.unregister(session);
    try { if (session !== null && this.supported) { await session.enableDesktopLyric(false); } } catch (err) {}
    this.actualEnabled = false;
    this.actualVisible = false;
    this.hasLyrics = false;
    this.supported = false;
    this.failed = false;
    this.error = '';
    this.publish();
  }
}
