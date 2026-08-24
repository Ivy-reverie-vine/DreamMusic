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

  async playFile(absPath: string, callbacks: PlaybackCallbacks): Promise<void> {
    await this.release();
    this.cb = callbacks;
    this.diagnosticSource = 'local';
    const file = fileIo.openSync(absPath, fileIo.OpenMode.READ_ONLY);
    this.fd = file.fd;
    const stat = fileIo.statSync(absPath);
    const avp = await media.createAVPlayer();
    this.player = avp;
    avp.on('stateChange', (state: string) => {
      this.handleState(state);
    });
    avp.on('timeUpdate', (ms: number) => {
      if (this.cb !== null) {
        this.cb.onPositionUpdate(ms);
      }
    });
    callbacks.onStateChange(PlayerState.PREPARING);
    avp.fdSrc = { fd: this.fd, offset: 0, length: stat.size };
    // 必须等状态到 initialized 才能 prepare,否则报 unsupported prepare operation
    await this.waitInitialized();
    await avp.prepare();
    await avp.play();
  }

  /** 网络直链流式播放：只交给 AVPlayer，不落盘。 */
  async playUrl(url: string, callbacks: PlaybackCallbacks): Promise<void> {
    await this.release();
    this.cb = callbacks;
    this.diagnosticSource = 'api-enhanced';
    const avp = await media.createAVPlayer();
    this.player = avp;
    avp.on('stateChange', (state: string) => {
      this.handleState(state);
    });
    avp.on('timeUpdate', (ms: number) => {
      if (this.cb !== null) {
        this.cb.onPositionUpdate(ms);
      }
    });
    callbacks.onStateChange(PlayerState.PREPARING);
    // 网络源: idle 状态设置 url → initialized → prepare → play
    const initializedAt = Date.now();
    this.diagnosticStage = 'avplayer_initialization';
    try {
      avp.url = url;
      await this.waitInitialized();
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
      throw err;
    }

    const preparedAt = Date.now();
    this.diagnosticStage = 'url_response';
    try {
      await avp.prepare();
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
      throw err;
    }

    const playingAt = Date.now();
    this.diagnosticStage = 'playing';
    try {
      await avp.play();
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
      throw err;
    }
  }

  private waitInitialized(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      this.initResolve = resolve;
      this.initReject = reject;
      this.initTimer = setTimeout(() => {
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
    } else if (p.state === 'paused') {
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
    if (this.initTimer >= 0) {
      clearTimeout(this.initTimer);
      this.initTimer = -1;
    }
    this.initResolve = null;
    this.initReject = null;
    const p = this.player;
    this.player = null;
    if (p !== null) {
      try {
        await p.release();
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'release failed: %{public}s', e.message);
      }
    }
    if (this.fd >= 0) {
      try {
        fileIo.closeSync(this.fd);
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
