import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlayerState } from '../../model/Playback';
import {
  DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE,
  DIAGNOSTIC_CATEGORY_PLAYBACK_FAILURE,
  DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE,
  playbackDiagnostics
} from './PlaybackDiagnostics';

const DOMAIN = 0x0000;
const TAG = 'PlayerSession';

export interface PlaybackCallbacks {
  onStateChange: (s: PlayerState) => void;
  onPositionUpdate: (ms: number) => void;
  /** 领域事件:单曲自然播放结束(issue-06 队列域消费) */
  onTrackEnded: () => void;
  onError: (msg: string) => void;
}

/**
 * AVPlayer 会话适配层(issue-05,真机验证项):
 * 沙箱文件经 fdSrc 播放;AVPlayer 状态字符串收敛为领域 PlayerState。
 * API 对照 SDK d.ts 核实:createAVPlayer/fdSrc/prepare/play/pause/seek/setVolume/
 * on('stateChange'|'timeUpdate')、AVPlayerState 字符串联合类型。
 */
export class PlayerSession {
  private player: media.AVPlayer | null = null;
  private fd: number = -1;
  private cb: PlaybackCallbacks | null = null;
  /** 等待 initialized 状态(issue-14 修复:fdSrc 后需等 initialized 才能 prepare) */
  private initResolve: (() => void) | null = null;
  private initReject: ((e: Error) => void) | null = null;
  private initTimer: number = -1;
  private diagnosticStage: string = 'avplayer_initialization';
  private diagnosticSource: string = 'local';
  private cancelled: boolean = false;

  private async createPlayer(): Promise<media.AVPlayer> {
    if (this.cancelled) { throw new Error('播放请求已取消'); }
    const avp = await media.createAVPlayer();
    if (this.cancelled) {
      await avp.release();
      throw new Error('播放请求已取消');
    }
    this.player = avp;
    avp.on('stateChange', (state: string) => {
      if (this.player === avp && !this.cancelled) { this.handleState(state); }
    });
    avp.on('error', () => {
      if (this.player === avp && !this.cancelled) { this.handleState('error'); }
    });
    avp.on('timeUpdate', (ms: number) => {
      if (this.player === avp && !this.cancelled && this.cb !== null) { this.cb.onPositionUpdate(ms); }
    });
    return avp;
  }

  private checkActive(): void {
    if (this.cancelled) { throw new Error('播放请求已取消'); }
  }

  async playFile(absPath: string, callbacks: PlaybackCallbacks): Promise<void> {
    this.checkActive();
    this.cb = callbacks;
    this.diagnosticSource = 'local';
    const file = fileIo.openSync(absPath, fileIo.OpenMode.READ_ONLY);
    this.fd = file.fd;
    const stat = fileIo.statSync(absPath);
    const avp = await this.createPlayer();
    callbacks.onStateChange(PlayerState.PREPARING);
    avp.fdSrc = { fd: this.fd, offset: 0, length: stat.size };
    // 必须等状态到 initialized 才能 prepare,否则报 unsupported prepare operation
    await this.waitInitialized();
    this.checkActive();
    await avp.prepare();
    this.checkActive();
    await avp.play();
    this.checkActive();
  }

  /** 网络直链流式播放：只交给 AVPlayer，不落盘。 */
  async playUrl(url: string, callbacks: PlaybackCallbacks): Promise<void> {
    this.checkActive();
    this.cb = callbacks;
    this.diagnosticSource = 'api-enhanced';
    const avp = await this.createPlayer();
    callbacks.onStateChange(PlayerState.PREPARING);
    // 网络源: idle 状态设置 url → initialized → prepare → play
    const initializedAt = Date.now();
    this.diagnosticStage = 'avplayer_initialization';
    try {
      avp.url = url;
      await this.waitInitialized();
      this.checkActive();
      playbackDiagnostics.record({
        source: this.diagnosticSource, capability: 'playback', stage: 'avplayer_initialization',
        durationMs: Date.now() - initializedAt, ok: true
      });
    } catch (err) {
      playbackDiagnostics.record({
        source: this.diagnosticSource, capability: 'playback', stage: 'avplayer_initialization',
        durationMs: Date.now() - initializedAt, ok: false,
        errorCategory: DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE
      });
      if (err instanceof Error) {
        throw err;
      }
      throw new Error('AVPlayer 初始化失败');
    }

    const preparedAt = Date.now();
    this.diagnosticStage = 'url_response';
    try {
      await avp.prepare();
      this.checkActive();
      playbackDiagnostics.record({
        source: this.diagnosticSource, capability: 'playback', stage: 'url_response',
        durationMs: Date.now() - preparedAt, ok: true
      });
    } catch (err) {
      playbackDiagnostics.record({
        source: this.diagnosticSource, capability: 'playback', stage: 'url_response',
        durationMs: Date.now() - preparedAt, ok: false,
        errorCategory: DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE
      });
      if (err instanceof Error) {
        throw err;
      }
      throw new Error('音频地址准备失败');
    }

    const playingAt = Date.now();
    this.diagnosticStage = 'playing';
    try {
      await avp.play();
      this.checkActive();
      playbackDiagnostics.record({
        source: this.diagnosticSource, capability: 'playback', stage: 'playing',
        durationMs: Date.now() - playingAt, ok: true
      });
    } catch (err) {
      playbackDiagnostics.record({
        source: this.diagnosticSource, capability: 'playback', stage: 'playing',
        durationMs: Date.now() - playingAt, ok: false,
        errorCategory: DIAGNOSTIC_CATEGORY_PLAYBACK_FAILURE
      });
      if (err instanceof Error) {
        throw err;
      }
      throw new Error('音频播放失败');
    }
  }

  private waitInitialized(): Promise<void> {
    this.checkActive();
    if (this.player !== null && this.player.state === 'initialized') { return Promise.resolve(); }
    if (this.player !== null && this.player.state === 'error') {
      return Promise.reject(new Error('AVPlayer 初始化失败'));
    }
    return new Promise<void>((resolve, reject) => {
      this.initResolve = resolve;
      this.initReject = reject;
      this.initTimer = setTimeout(() => {
        this.initTimer = -1;
        this.initResolve = null;
        this.initReject = null;
        reject(new Error('AVPlayer 初始化超时'));
      }, 8000);
    });
  }

  private handleState(state: string): void {
    if (state === 'initialized') {
      if (this.initTimer >= 0) {
        clearTimeout(this.initTimer);
        this.initTimer = -1;
      }
      const r = this.initResolve;
      this.initResolve = null;
      this.initReject = null;
      if (r !== null) {
        r();
      }
      return;
    }
    if (state === 'error') {
      const wasPlaying = this.diagnosticStage === 'playing' && this.initReject === null;
      if (this.initTimer >= 0) {
        clearTimeout(this.initTimer);
        this.initTimer = -1;
      }
      const rj = this.initReject;
      this.initResolve = null;
      this.initReject = null;
      if (rj !== null) {
        rj(new Error('AVPlayer 初始化失败'));
      }
      if (wasPlaying) {
        playbackDiagnostics.record({
          source: this.diagnosticSource, capability: 'playback', stage: 'playing',
          durationMs: 0, ok: false, errorCategory: DIAGNOSTIC_CATEGORY_PLAYBACK_FAILURE
        });
      }
    }
    if (this.cb === null) {
      return;
    }
    switch (state) {
      case 'playing':
        this.cb.onStateChange(PlayerState.PLAYING);
        break;
      case 'paused':
        this.cb.onStateChange(PlayerState.PAUSED);
        break;
      case 'completed':
        this.cb.onStateChange(PlayerState.COMPLETED);
        this.cb.onTrackEnded();
        break;
      case 'error':
        this.cb.onStateChange(PlayerState.ERROR);
        this.cb.onError('AVPlayer 进入 error 状态');
        break;
      default:
        break;
    }
  }

  async togglePause(): Promise<void> {
    const p = this.player;
    if (p === null) {
      return;
    }
    if (p.state === 'playing') {
      await p.pause();
    } else if (p.state === 'paused' || p.state === 'completed') {
      await p.play();
    }
  }

  async pause(): Promise<void> {
    const p = this.player;
    if (p !== null && p.state === 'playing') {
      await p.pause();
    }
  }

  seekTo(ms: number): void {
    const p = this.player;
    if (p !== null && p.state !== 'idle' && p.state !== 'released') {
      p.seek(Math.max(0, ms));
    }
  }

  setVolume(v: number): void {
    const p = this.player;
    if (p !== null) {
      p.setVolume(Math.max(0.0, Math.min(1.0, v)));
    }
  }

  getCurrentTime(): number {
    return this.player !== null ? this.player.currentTime : 0;
  }

  getDuration(): number {
    return this.player !== null ? this.player.duration : 0;
  }

  get isPlaying(): boolean {
    return this.player !== null && this.player.state === 'playing';
  }

  get isLoaded(): boolean {
    return this.player !== null;
  }

  async release(): Promise<void> {
    this.cancelled = true;
    if (this.initTimer >= 0) {
      clearTimeout(this.initTimer);
      this.initTimer = -1;
    }
    const reject = this.initReject;
    this.initResolve = null;
    this.initReject = null;
    if (reject !== null) { reject(new Error('播放请求已取消')); }
    const p = this.player;
    const fd = this.fd;
    this.player = null;
    this.fd = -1;
    this.cb = null;
    if (p !== null) {
      try {
        await p.release();
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'release failed: %{public}s', e.message);
      }
    }
    if (fd >= 0) {
      try {
        fileIo.closeSync(fd);
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'close fd failed: %{public}s', e.message);
      }
      this.fd = -1;
    }
    this.cb = null;
    this.diagnosticStage = 'avplayer_initialization';
    this.diagnosticSource = 'local';
  }
}
