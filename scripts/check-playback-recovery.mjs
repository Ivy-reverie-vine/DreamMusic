// Node 24+：执行真实 ArkTS 状态/会话逻辑；Kit、网络与存储边界使用替身。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, deps = {}) {
  const source = readFileSync(new URL(path, root), 'utf8').replace(/^import[\s\S]*?;\r?\n/gm, '')
    .replace(/^@Observed\r?\n/gm, '').replace(/^export /gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { Error, Date, setTimeout, clearTimeout, ...deps }, { filename: path });
}
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject }; };
const flush = () => new Promise(resolve => setImmediate(resolve));
const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
const identity = load('model/OnlineTrackIdentity.ets', ['createOnlineTrack', 'canDownloadNetEase']);
class ApiError extends Error { constructor(code, message) { super(message); this.code = code; } }
const sessions = [], resolutions = [], history = [], saved = [];
let resolveUrl = async () => 'https://audio/fresh';
const api = { async resolvePlayback(...args) {
  resolutions.push(args);
  const ref = args[2] || undefined;
  return { audioIntegrity: { status: 'full', reason: 'controlled_full', catalogDurationMs: 90000, resourceDurationMs: 90000, evidence: ['controlled'] }, url: await resolveUrl(...args), playbackSource: 'api-enhanced',
    catalogRef: ref, playbackRef: ref, lyricsRef: ref };
} };
let playGate = null, nativeFailure = false;
class Session {
  constructor() { sessions.push(this); this.isLoaded = false; this.isPlaying = false; }
  async playFile(path, cb) { this.path = path; return this.playUrl(path, cb); }
  async playUrl(url, cb) {
    this.url = url; this.cb = cb; this.isLoaded = true;
    cb.onStateChange(PlayerState.PREPARING);
    const gate = playGate;
    if (gate) await gate.promise;
    if (nativeFailure) throw new Error('native detail including URL');
    this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING);
  }
  async release() { this.released = true; this.isLoaded = false; this.isPlaying = false; }
  setVolume(v) { this.volume = v; }
  seekTo(ms) { this.seek = ms; }
  getDuration() { return 90000; }
  async pause() { this.isPlaying = false; this.cb.onStateChange(PlayerState.PAUSED); }
  async togglePause() { if (this.isPlaying) await this.pause();
    else { this.isPlaying = true; this.cb.onStateChange(PlayerState.PLAYING); } }
}
const store = { async insertHistory(id) { history.push(id); },
  async savePlayerState(snapshot, pos) { saved.push({ ids: Array.from(snapshot.tracks), pos }); } };
const background = { sync() {}, startLongTask() {}, stopLongTask() {} };
const files = new Set(['/files/music/1.mp3', '/files/music/2.mp3']);
const { PlayerViewModel, playerViewModel: player } = load('viewmodel/PlayerViewModel.ets',
  ['PlayerViewModel', 'playerViewModel'], {
    PlayerSession: Session, SleepTimer, PlayerState, PlayMode, ApiError,
    NetEaseApi: api,
    fileIo: { accessSync: path => files.has(path) }, hilog: { error() {} },
    LibraryStore: { getInstance: () => store }, BackgroundPlayback: { getInstance: () => background }
  });
const ctx = { filesDir: '/files' };
const track = (id, ref = '') => ({ id, path: `music/${id}.mp3`, title: `song ${id}`, artist: '', album: '',
  durationMs: 90000, coverPath: '', importedAt: 0, missing: false, neteaseId: id < 0 ? -id : 0,
  streamUrl: id < 0 ? 'https://audio/expired' : undefined, mediaRef: ref });
const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
  ...identity, QueueEngine, PlayMode, PlayerState, playerViewModel: player, setInterval() {},
  LibraryStore: { getInstance: () => store }, BackgroundPlayback: { getInstance: () => background }
});
const queue = new QueueViewModel();

// 准备 -> 播放 -> 暂停 -> 恢复；旧 error 在新选择时立即清除。
playGate = deferred();
const first = queue.playFromList([track(1), track(2)], 0, ctx);
assert.equal(player.state, PlayerState.PREPARING);
assert.match(player.statusText, /加载/);
playGate.resolve(); await first; playGate = null;
assert.equal(player.state, PlayerState.PLAYING);
await player.togglePause(); assert.equal(player.state, PlayerState.PAUSED);
await player.togglePause(); assert.equal(player.state, PlayerState.PLAYING);

// 缺失文件不显示底层错误；恢复入口明确指向音乐库。
await player.playTrack(track(99), ctx);
assert.equal(player.state, PlayerState.ERROR);
assert.equal(player.recoveryAction, 'library');
await player.retry(); assert.equal(player.recoveryAction, 'library');

// 在线网络/解析/空 URL/认证/原生准备失败：同来源重试，不改队列、模式和位置。
for (const code of ['NETWORK', 'TIMEOUT', 'RESOLUTION', 'EMPTY_URL', 'FORBIDDEN', 'NATIVE']) {
  resolveUrl = code === 'EMPTY_URL' ? async () => '' : code === 'NATIVE' ? async () => 'https://audio/fresh'
    : async () => { throw new ApiError(code, 'raw internal message'); };
  nativeFailure = code === 'NATIVE';
  const online = track(-7, 'v2:source:7');
  await queue.playFromList([online], 0, ctx);
  assert.equal(player.state, PlayerState.ERROR);
  assert.ok(!player.errorText.includes('raw'));
  assert.ok(!player.errorText.includes('native'));
  assert.equal(player.recoveryAction, code === 'FORBIDDEN' ? 'settings' : 'retry');
  player.positionMs = 1234;
  const before = queue.queueTracks.map(t => t.id), mode = queue.mode;
  resolveUrl = async () => 'https://audio/fresh'; nativeFailure = false;
  await player.retry();
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.errorText, ''); assert.equal(player.recoveryAction, '');
  assert.equal(player.currentTrack, online);
  assert.equal(resolutions.at(-1)[2], 'v2:source:7');
  assert.equal(queue.mode, mode); assert.deepEqual(queue.queueTracks.map(t => t.id), before);
  assert.equal(sessions.at(-1).seek, 1234);
}

// 旧 native 回调/准备结果/失败/自然结束不能覆盖新音轨或回写旧队列。
playGate = deferred(); const slowGate = playGate;
const slow = queue.playFromList([track(1), track(2)], 0, ctx);
const oldSession = sessions.at(-1), count = history.length;
playGate = null; await queue.playFromList([track(2)], 0, ctx);
oldSession.cb.onError('old'); oldSession.cb.onStateChange(PlayerState.ERROR);
oldSession.cb.onPositionUpdate(8888); oldSession.cb.onTrackEnded();
slowGate.resolve(); await slow; await flush();
assert.equal(player.currentTrack.id, 2); assert.equal(queue.currentId, 2);
assert.equal(player.state, PlayerState.PLAYING); assert.equal(player.positionMs, 0);
assert.equal(player.errorText, ''); assert.equal(history.length, count + 1);
assert.deepEqual(saved.at(-1).ids, [2]); assert.ok(oldSession.released);

// 新音轨的文件恢复入口不得被旧 playing/error 回调清除或替换。
const prior = sessions.at(-1);
await player.playTrack(track(99), ctx);
const currentFailure = player.errorText;
prior.cb.onStateChange(PlayerState.PLAYING); prior.cb.onError('late error');
assert.equal(player.state, PlayerState.ERROR); assert.equal(player.errorText, currentFailure);
assert.equal(player.recoveryAction, 'library');
playGate = deferred(); const failedPreparation = playGate;
const failedOld = player.playTrack(track(1), ctx);
playGate = null; await player.playTrack(track(2), ctx);
failedPreparation.reject(new Error('old prepare failed')); await failedOld;
assert.equal(player.state, PlayerState.PLAYING); assert.equal(player.errorText, '');

// 地址解析迟到/失败，连同相同来源重复点播仍只提交最后一次。
for (const reject of [false, true]) {
  const gate = deferred(); resolveUrl = () => gate.promise;
  const late = player.playTrack(track(-7, 'same-source'), ctx);
  await player.playTrack(track(2), ctx);
  if (reject) gate.reject(new ApiError('NETWORK', 'old'));
  else gate.resolve('https://audio/old');
  await late;
  assert.equal(player.currentTrack.id, 2); assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.errorText, '');
}
const sameGate = deferred(); resolveUrl = () => sameGate.promise;
const sameOld = player.playTrack(track(-7, 'same-source'), ctx);
resolveUrl = async () => 'https://audio/latest';
await player.playTrack(track(-7, 'same-source'), ctx);
sameGate.resolve('https://audio/old'); await sameOld;
assert.equal(sessions.at(-1).url, 'https://audio/latest');

// 在线入口在本地查询前显示准备状态；查询竞争与旧下载不得替换新选择。
let localGate = null, downloadGate = deferred();
const { OnlineMusicViewModel } = load('viewmodel/OnlineMusicViewModel.ets', ['OnlineMusicViewModel'], {
  ...identity, playerViewModel: player, queueViewModel: queue, ApiError, PlayerState,
  NetEaseApi: { ...api, songDetailCover: async () => { throw new Error('cover failed'); } },
  OnlineDownloadService: { findLocal: () => localGate ? localGate.promise : Promise.resolve(null),
    ensureLocal: () => downloadGate.promise }
});
const onlineVM = new OnlineMusicViewModel();
const song = { id: 7, name: 'online', artist: '', album: '', durationMs: 90000, coverUrl: '', mediaRef: 'source:7' };
localGate = deferred(); const localWait = localGate;
const lookup = onlineVM.playSong(ctx, song);
assert.equal(player.state, PlayerState.PREPARING);
await queue.playFromList([track(2)], 0, ctx);
localWait.resolve(track(1)); await lookup; localGate = null;
assert.equal(player.currentTrack.id, 2);
await onlineVM.playSong(ctx, song);
await queue.playFromList([track(2)], 0, ctx);
downloadGate.resolve(track(70)); await flush();
assert.equal(player.currentTrack.id, 2);
assert.equal(player.errorText, '');

// 在线入口先确认实际来源再使用缓存；本地音乐库播放仍不请求网络。
const resolutionCount = resolutions.length;
localGate = { promise: Promise.resolve(track(1)) };
await onlineVM.playSong(ctx, song); localGate = null;
assert.equal(player.currentTrack.id, 1); assert.equal(resolutions.length, resolutionCount + 1);
downloadGate = deferred(); resolveUrl = async () => { throw new ApiError('NETWORK', 'offline'); };
await assert.rejects(onlineVM.playSong(ctx, song));
resolveUrl = async () => 'https://audio/recovered'; await player.retry();
downloadGate.resolve({ ...track(70), neteaseId: 7 }); await flush();

assert.equal(player.currentTrack.id, 70); assert.equal(player.state, PlayerState.PLAYING);

// 定时暂停在在线本地查询/地址准备期间到期，准备完成后仍暂停。
player.setSleepTimer(10000); localGate = deferred(); const timerLookup = localGate;
downloadGate = deferred();
const timed = onlineVM.playSong(ctx, song);
assert.equal(player.checkSleepTimer(Date.now() + 20000), true);
timerLookup.resolve(null); await timed; localGate = null;
assert.equal(player.state, PlayerState.PAUSED);
await queue.playFromList([track(2)], 0, ctx);
downloadGate.resolve({ ...track(70), neteaseId: 7 }); await flush();
assert.equal(player.currentTrack.id, 2);

// 封面/歌词钩子异常不冒充播放失败。
player.trackChangeHandler = () => { throw new Error('lyrics unavailable'); };
player.coverColorHandler = () => { throw new Error('cover unavailable'); };
await player.playTrack(track(1), ctx);
assert.equal(player.state, PlayerState.PLAYING); assert.equal(player.errorText, '');
player.trackChangeHandler = null; player.coverColorHandler = null;

// 缓存查询失败仍完成当前在线队列选择，可使用播放器恢复。
localGate = { promise: Promise.reject(new Error('cache read failed')) };
downloadGate = deferred();
await onlineVM.playSong(ctx, song); localGate = null;
assert.ok(queue.currentId < -1); assert.equal(player.state, PlayerState.PLAYING);
await queue.playFromList([track(2)], 0, ctx);
downloadGate.resolve({ ...track(70), neteaseId: 7 }); await flush();

// 会话边界：createAVPlayer 迟到释放、initialized 等待取消、prepare 未完成取消、旧回调隔离。
const nativePlayers = [], fds = new Set(); let createGate = null, prepareGate = null;
function nativePlayer() {
  const handlers = {};
  const p = { state: 'idle', releases: 0, plays: 0, on: (event, fn) => { handlers[event] = fn; },
    emit(state) { this.state = state; handlers.stateChange?.(state); },
    set url(value) { this.source = value; }, set fdSrc(value) { this.source = value; },
    async prepare() { const gate = prepareGate; if (gate) await gate.promise; this.state = 'prepared'; },
    async play() { this.plays++; this.emit('playing'); },
    async release() { this.releases++; this.emit('released'); }, handlers };
  nativePlayers.push(p); return p;
}
const { PlayerSession } = load('service/playback/PlayerSession.ets', ['PlayerSession'], {
  PlayerState, media: { createAVPlayer: () => createGate ? createGate.promise : Promise.resolve(nativePlayer()) },
  fileIo: { OpenMode: { READ_ONLY: 1 }, openSync() { fds.add(1); return { fd: 1 }; },
    statSync() { return { size: 42 }; }, closeSync(fd) { assert.ok(fds.delete(fd)); } },
  hilog: { warn() {} }, playbackDiagnostics: { record() {} },
  DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE: 'init',
  DIAGNOSTIC_CATEGORY_PLAYBACK_FAILURE: 'play', DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE: 'url'
});
let callbacks = 0;
const cb = { onStateChange() { callbacks++; }, onPositionUpdate() { callbacks++; }, onError() { callbacks++; }, onTrackEnded() {} };
createGate = deferred(); const createWait = createGate;
let session = new PlayerSession(); let pending = session.playFile('/file', cb);
const rejected = assert.rejects(pending, /取消/);
await session.release(); const latePlayer = nativePlayer(); createWait.resolve(latePlayer);
await rejected; createGate = null;
assert.equal(latePlayer.releases, 1); assert.equal(fds.size, 0);
session = new PlayerSession(); pending = session.playUrl('https://audio', cb);
const initRejected = assert.rejects(pending, /取消/); await flush();
await session.release(); await initRejected;
const old = nativePlayers.at(-1), callsBefore = callbacks;
old.emit('playing'); old.handlers.timeUpdate(100); old.handlers.error();
assert.equal(callbacks, callsBefore);
session = new PlayerSession(); prepareGate = deferred(); const prepareWait = prepareGate;
pending = session.playUrl('https://audio', cb);
const prepareRejected = assert.rejects(pending, /取消/); await flush();
const preparing = nativePlayers.at(-1); preparing.emit('initialized'); await flush();
await session.release(); prepareWait.resolve(); await prepareRejected; prepareGate = null;
assert.equal(preparing.plays, 0); assert.equal(preparing.releases, 1);
assert.ok(nativePlayers.every(p => p.releases === 1));
console.log('PASS: playback states, classified recovery, same-source retry, queue/position preservation, stale resolution/native/download races, confirmed-source cache lookup and cancelled native resource ownership.');
