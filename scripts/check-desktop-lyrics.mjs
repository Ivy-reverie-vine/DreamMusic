// Node 24+，运行真实 ArkTS；AVSession/Preferences/文件/网络为边界替身，不代表设备验收。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8')
    .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^@Observed\r?\n/gm, '').replace(/^export /gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { Error, Date, ...dependencies }, { filename: path });
}
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
};
const flush = () => new Promise(resolve => setImmediate(resolve));
const ctx = { filesDir: '/files' }, saved = new Map(), calls = [];
let supported = true, probeError = null, probeGate = null, nativeError = null, nativeGate = null;
let storageError = false;
const avSession = {
  async isDesktopLyricSupported() {
    calls.push('probe');
    if (probeGate) await probeGate.promise;
    if (probeError) throw probeError;
    return supported;
  }
};
const { DesktopLyrics, desktopLrc } = load('service/lyrics/DesktopLyrics.ets', ['DesktopLyrics', 'desktopLrc'], {
  avSession,
  preferences: { getPreferencesSync: () => ({
    getSync: (key, fallback) => saved.has(key) ? saved.get(key) : fallback,
    putSync(key, value) { saved.set(key, value); },
    async flush() { if (storageError) throw new Error('storage'); }
  }) }
});
function session() {
  const handlers = new Map();
  const register = (key, cb) => { assert.equal(handlers.has(key), false, 'no duplicate listener'); handlers.set(key, cb); };
  const unregister = (key, cb) => { assert.equal(handlers.get(key), cb); handlers.delete(key); };
  const native = async () => {
    if (nativeGate) { const gate = nativeGate; nativeGate = null; await gate.promise; }
    if (nativeError) throw nativeError;
  };
  return {
    handlers, enabled: false, visible: false, locked: false, destroyedControllers: 0,
    async getController() {
      return {
        onDesktopLyricEnabled: cb => this.onDesktopLyricEnabled(cb),
        offDesktopLyricEnabled: cb => this.offDesktopLyricEnabled(cb),
        isDesktopLyricEnabled: () => this.isDesktopLyricEnabled(),
        destroy: async () => { this.destroyedControllers++; }
      };
    },
    onDesktopLyricEnabled(cb) { register('enabled', cb); },
    offDesktopLyricEnabled(cb) { unregister('enabled', cb); },
    onDesktopLyricVisibilityChanged(cb) { register('visible', cb); },
    offDesktopLyricVisibilityChanged(cb) { unregister('visible', cb); },
    onDesktopLyricStateChanged(cb) { register('state', cb); },
    offDesktopLyricStateChanged(cb) { unregister('state', cb); },
    async isDesktopLyricEnabled() { return this.enabled; },
    async isDesktopLyricVisible() { return this.visible; },
    async getDesktopLyricState() { return { isLocked: this.locked }; },
    async enableDesktopLyric(value) {
      calls.push(['enable', value]); await native(); this.enabled = value;
      if (!value) this.visible = false;
      handlers.get('enabled')?.(value);
    },
    async setDesktopLyricVisible(value) {
      calls.push(['visible', value]); await native(); this.visible = value; handlers.get('visible')?.(value);
    },
    async setDesktopLyricState(value) {
      calls.push(['locked', value.isLocked]); await native(); this.locked = value.isLocked; handlers.get('state')?.(value);
    }
  };
}
async function idle(service) { await service.chain; await flush(); await service.chain; }
const service = DesktopLyrics.getInstance();
const { desktopLyricsViewModel: settings } = load('viewmodel/DesktopLyricsViewModel.ets', ['desktopLyricsViewModel'], { DesktopLyrics });
let s = session();
await service.attach(ctx, s);
assert.equal(settings.enabled, false); assert.equal(s.enabled, false);
assert.equal(s.handlers.size, 3);
await service.attach(ctx, s); assert.equal(s.handlers.size, 3);
settings.setEnabled(true); await idle(service);
assert.equal(s.enabled, true); assert.equal(s.visible, false); assert.match(settings.status, /暂无歌词/);
service.setContentAvailable(true); await idle(service); assert.equal(s.visible, true);
settings.setLocked(true); await idle(service); assert.equal(s.locked, true);
settings.setVisible(false); await idle(service); assert.equal(s.visible, false);
service.setContentAvailable(false); service.setContentAvailable(true); await idle(service);
assert.equal(s.visible, false, 'new lyrics preserve user hide');
settings.setVisible(true); await idle(service);
service.setContentAvailable(false); await idle(service);
assert.equal(settings.visible, true, 'automatic hide never overwrites user preference');
assert.equal(saved.get('visible'), true);
service.setContentAvailable(true); await idle(service);
s.locked = false; s.handlers.get('state')({ isLocked: false });
assert.equal(settings.locked, false); assert.equal(saved.get('locked'), false);
s.visible = false; s.handlers.get('visible')(false);
assert.equal(settings.visible, false); assert.equal(saved.get('visible'), false);
s.enabled = false; s.handlers.get('enabled')(false); await idle(service);
assert.equal(settings.enabled, false); assert.equal(saved.get('enabled'), false);
settings.setEnabled(true); settings.setVisible(true); settings.setLocked(true); await idle(service);
const oldListener = s.handlers.get('enabled');
await service.detach(); assert.equal(s.handlers.size, 0); assert.equal(s.enabled, false);
assert.equal(s.destroyedControllers, 1);
oldListener(false); assert.equal(saved.get('enabled'), true, 'detached callbacks cannot overwrite settings');
s = session(); await service.attach(ctx, s); assert.equal(s.enabled, true); assert.equal(s.locked, true);
assert.equal(s.visible, false, 'new session waits for current metadata');
service.setContentAvailable(true); await idle(service); assert.equal(s.visible, true);
// 原生操作挂起时，最终意图必须胜出，期间状态正确标忙。
nativeGate = deferred(); const gate = nativeGate;
settings.setVisible(false); await flush(); assert.equal(settings.busy, true);
settings.setEnabled(false); gate.resolve(); await idle(service);
assert.equal(s.enabled, false); assert.equal(settings.enabled, false);
// 原生错误只报告一次，不因歌词变化/播放心跳持续重试；可显式恢复。
nativeError = { code: 6600101 };
settings.setEnabled(true); await idle(service); assert.equal(settings.canRetry, true);
const failedCalls = calls.length;
service.setContentAvailable(false); service.setContentAvailable(true); await idle(service);
assert.equal(calls.length, failedCalls);
nativeError = null; settings.retry(); await idle(service);
assert.equal(s.enabled, true); assert.equal(s.visible, false, 'user hide survives a failed apply');
assert.equal(settings.canRetry, false);
storageError = true; settings.setLocked(false); await idle(service); assert.match(settings.status, /保存失败/);
storageError = false;
await service.detach();
// 不支持设备完全不触碰桌面歌词原生接口；不会重复抛错。
supported = false; const unsupportedSession = session(); const count = calls.length;
await service.attach(ctx, unsupportedSession);
assert.equal(calls.length, count + 1); assert.equal(unsupportedSession.handlers.size, 0);
assert.equal(settings.supported, false); assert.match(settings.status, /不支持/);
service.setContentAvailable(true); await idle(service); assert.equal(calls.length, count + 1);
await service.detach();
// 探测服务异常可在同一播放会话重试；生命周期中过期探测不能注册监听。
supported = true; probeError = { code: 6600101 }; s = session();
await service.attach(ctx, s); assert.equal(settings.canRetry, true);
probeError = null; settings.retry(); await idle(service); assert.equal(s.handlers.size, 3);
await service.detach();
probeGate = deferred(); const stale = session();
const attaching = service.attach(ctx, stale); await flush();
const detaching = service.detach(); probeGate.resolve(); probeGate = null;
await Promise.all([attaching, detaching]); assert.equal(stale.handlers.size, 0);
// 重建服务模拟进程重启，从 Preferences 读取而非默认开启。
const restored = new DesktopLyrics(); s = session(); await restored.attach(ctx, s);
assert.equal(restored.snapshot.enabled, saved.get('enabled'));
assert.equal(restored.snapshot.visible, saved.get('visible'));
assert.equal(restored.snapshot.locked, saved.get('locked'));
await restored.detach();

const parser = load('service/lyrics/LrcParser.ets', ['parseLrc', 'parseYrc', 'findActiveLine']);
assert.equal(desktopLrc([]), ''); assert.equal(desktopLrc([{ timeMs: 0, text: ' ' }]), '');
const lrc = '[00:01.234]第一行\n[01:02.005]第二行';
assert.equal(desktopLrc(parser.parseLrc(lrc)), lrc);
assert.equal(desktopLrc(parser.parseYrc('[1200,300](1200,300,0)字')), '[00:01.200]字');

// 真实 LyricsViewModel -> Runtime -> BackgroundPlayback -> AVSession。封面可无限慢，歌词/时间先更新。
saved.clear(); service.storageError = '';
const metadata = [], playback = [], sessions = [];
const coverGate = deferred(); let coverWait = true;
const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
const { PlayMode } = load('service/playback/QueueEngine.ets', ['PlayMode']);
avSession.PlaybackState = Object.fromEntries(['PLAY', 'PAUSE', 'PREPARE', 'COMPLETED', 'INITIAL', 'ERROR'].map(v => [`PLAYBACK_STATE_${v}`, v]));
avSession.LoopMode = {};
avSession.createAVSession = async () => {
  const nativeSession = session(); sessions.push(nativeSession);
  Object.assign(nativeSession, {
    destroyed: false, on() {}, async activate() {}, async setLaunchAbility() {},
    async setAVMetadata(meta) { assert.equal(this.destroyed, false); metadata.push({ ...meta }); },
    async setAVPlaybackState(state) { playback.push({ ...state }); },
    async destroy() { assert.equal(this.handlers.size, 0); this.destroyed = true; }
  }); return nativeSession;
};
const { BackgroundPlayback } = load('service/playback/BackgroundPlayback.ets', ['BackgroundPlayback'], {
  avSession, DesktopLyrics, PlayerState, PlayMode, PLAYBACK_DESTINATION: 'now-playing',
  hilog: { warn() {}, error() {} },
  CoverArtService: {
    identity: t => t?.mediaRef || t?.path || '', resolve: () => 'cover',
    getInstance: () => ({ async acquire() { if (coverWait) await coverGate.promise; return { pixelMap: null, release() {} }; } })
  },
  wantAgent: { getWantAgent: async () => ({}), OperationType: {}, WantAgentFlags: {} },
  backgroundTaskManager: { BackgroundMode: {}, startBackgroundRunning: async () => {}, stopBackgroundRunning: async () => {} }
});
const bp = BackgroundPlayback.getInstance();
const player = {
  currentTrack: null, positionMs: 0, state: PlayerState.PAUSED,
  async dispose() { this.currentTrack = null; this.state = PlayerState.IDLE; },
  refreshBackground() { bp.sync(this.currentTrack, this.state, this.positionMs, 100000, PlayMode.SEQUENTIAL, true); }
};
const online = [], localLines = parser.parseLrc(lrc);
const { lyricsViewModel: lyrics } = load('viewmodel/LyricsViewModel.ets', ['lyricsViewModel'], {
  ...parser, playerViewModel: player,
  LrcLoader: { loadForTrack: path => path.includes('local') ? localLines : null },
  NetEaseApi: { lyricRaw: () => { const request = deferred(); online.push(request); return request.promise; } }
});
const { PlaybackRuntime } = load('viewmodel/PlaybackRuntime.ets', ['PlaybackRuntime'], {
  lyricsViewModel: lyrics, playerViewModel: player, BackgroundPlayback, PlayerState, desktopLrc,
  queueViewModel: { restore: async () => {} }, MusicFormPublisher: class { sync() {} async dispose() {} }
});
const runtime = new PlaybackRuntime(); await runtime.ensureReady(ctx); await idle(service);
settings.setEnabled(true); settings.setVisible(true); await idle(service);
// 本地音轨为正 ID；未解析 URL 的瞬态在线播放为负 ID，与真实模型保持一致。
function track(path, mediaRef = '') { return { id: mediaRef ? -1 : 1, path, mediaRef, title: path, artist: '', album: '', neteaseId: mediaRef ? 1 : 0, streamUrl: mediaRef ? 'https://stream' : '' }; }
async function change(t) { player.currentTrack = t; player.trackChangeHandler(t); player.refreshBackground(); await flush(); await idle(service); }
await change(track('local'));
assert.equal(metadata.at(-1).lyric, lrc); assert.equal(sessions.at(-1).visible, true);
player.positionMs = 63000; player.positionTickHandler(63000); player.refreshBackground(); await flush();
assert.equal(lyrics.activeIndex, 1); assert.equal(playback.at(-1).position.elapsedTime, 63000);
assert.equal(playback.at(-1).state, 'PAUSE');
player.positionMs = 1500; player.positionTickHandler(1500); player.state = PlayerState.PLAYING;
player.refreshBackground(); await flush();
assert.equal(lyrics.activeIndex, 0); assert.equal(playback.at(-1).state, 'PLAY');
assert.equal(playback.at(-1).position.elapsedTime, 1500);
await change(track('online-a', 'source-a:1')); assert.equal(metadata.at(-1).lyric, '');
assert.equal(sessions.at(-1).visible, false);
await change(track('online-b', 'source-b:1'));
online[0].resolve({ lrc: '[00:01.000]旧歌', yrc: '' }); await flush();
assert.equal(metadata.at(-1).lyric, '', 'stale online lyrics cannot reappear');
online[1].resolve({ lrc: '[00:02.000]新歌', yrc: '', lyrics: { status: 'available', timeline: 'trusted', reason: 'same_resource' } }); await flush(); await idle(service);
assert.equal(metadata.at(-1).lyric, '[00:02.000]新歌'); assert.equal(sessions.at(-1).visible, true);
// T11: a source change withdraws the system timeline even if readable text exists.
await change(track('online-static', 'source-b:2'));
online[2].resolve({ lrc: '[00:02.000]静态歌词', yrc: '', lyrics: { status: 'available', timeline: 'uncertain', reason: 'audio_relation_unverified' } });
await flush(); await idle(service);
assert.equal(lyrics.lines[0].text, '静态歌词'); assert.equal(lyrics.timelineTrusted, false);
assert.equal(metadata.at(-1).lyric, ''); assert.equal(sessions.at(-1).visible, false);
await change(track('empty')); assert.equal(metadata.at(-1).lyric, ''); assert.equal(sessions.at(-1).visible, false);
await change(track('online-error', 'error:1'));
online[3].reject(new Error('network')); await flush(); await idle(service);
assert.equal(metadata.at(-1).lyric, ''); assert.equal(sessions.at(-1).visible, false);
await change(track('local')); player.state = PlayerState.ERROR; player.refreshBackground(); await flush(); await idle(service);
assert.equal(sessions.at(-1).visible, false);
await runtime.dispose(); await bp.release();
const beforeLateCover = metadata.length;
coverWait = false; coverGate.resolve(); await flush();
assert.equal(metadata.length, beforeLateCover, 'late artwork cannot restore metadata after destroy');
assert.equal(sessions.at(-1).destroyed, true);
console.log('PASS: desktop lyric preferences, system feedback, retry/degradation, async lifecycle, parsed LRC/YRC, cold runtime, metadata-before-artwork, seek/pause/resume, stale/empty/error lyrics and cleanup.');
