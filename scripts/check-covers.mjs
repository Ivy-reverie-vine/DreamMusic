// Node.js 24+：执行真实 ArkTS 封面逻辑，替身只覆盖 ImageKit/HTTP/文件/AVSession 边界。
// 不代表设备解码、系统媒体卡片或真实网络验收。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8').replace(/^import[\s\S]*?;\r?\n/gm, '')
    .replace(/^@Observed\r?\n/gm, '').replace(/^export /gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { ArrayBuffer, Uint8Array, Date: Clock, $r: name => name, ...dependencies }, { filename: path });
}
let now = 100000;
class Clock extends Date { static now() { return now; } }
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject }; };
const files = new Map();
const handles = new Map();
let nextFd = 1;
const put = (path, data = new Uint8Array([1, 2, 3]).buffer) => files.set(path, { data, mtime: ++now });
const fileIo = {
  OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
  accessSync: path => files.has(path),
  mkdirSync: path => put(path, ''),
  statSync(path) { const f = files.get(path); if (!f) throw new Error('missing');
    return { size: f.data.byteLength ?? f.data.length, mtime: f.mtime }; },
  readTextSync(path) { const f = files.get(path); if (!f) throw new Error('missing'); return f.data; },
  unlinkSync: path => { if (!files.delete(path)) throw new Error('missing'); },
  listFileSync: dir => [...files.keys()].filter(p => p.startsWith(dir + '/')).map(p => p.slice(dir.length + 1)),
  openSync(path) { const fd = nextFd++; handles.set(fd, path); put(path); return { fd }; },
  writeSync: (fd, data) => { assert.ok(handles.has(fd)); put(handles.get(fd), data); },
  closeSync: fd => { assert.ok(handles.delete(fd)); }
};
const maps = [];
const sources = [];
const decodeGates = new Map();
const image = {
  PixelMapFormat: { RGBA_8888: 3 },
  createImageSource(input) {
    const source = { input, releases: 0,
      async createPixelMap(options) {
        const gate = decodeGates.get(input);
        if (gate) await gate.promise;
        if (typeof input === 'string' && (!files.has(input) || files.get(input).data === 'corrupt')) {
          throw new Error('decode failed');
        }
        const pm = { input, size: options.desiredSize.width, releases: 0,
          async release() { assert.equal(this.releases++, 0, 'PixelMap double release'); },
          async getImageInfo() { assert.equal(this.releases, 0); return { size: { width: this.size, height: this.size } }; },
          async readPixelsToBuffer(buf) { assert.equal(this.releases, 0); new Uint8Array(buf).fill(127); }
        };
        maps.push(pm); return pm;
      },
      async release() { assert.equal(this.releases++, 0, 'ImageSource double release'); }
    };
    sources.push(source); return source;
  }
};
const requests = [];
const networkGates = new Map();
let offline = false;
let httpDestroyed = 0;
const http = { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 1 },
  createHttp() { return {
    async request(url, options) {
      requests.push({ url, options });
      const gate = networkGates.get(url);
      if (gate) return await gate.promise;
      if (offline) throw new Error('offline');
      return { responseCode: 200, result: new Uint8Array([1, 2, 3]).buffer };
    }, destroy() { httpDestroyed++; }
  }; }
};
const ctx = { filesDir: '/files', cacheDir: '/cache', resourceManager: {
  async getMediaContent() { return new Uint8Array([9, 9, 9]); }
} };
const { extractColors } = load('service/color/ColorExtract.ets', ['extractColors']);
const { CoverArtService } = load('service/cover/CoverArtService.ets', ['CoverArtService'], { fileIo, image, http, extractColors });
const covers = CoverArtService.getInstance();
const track = (id, coverPath = '', streamCoverUrl = '') => ({ id, coverPath, streamCoverUrl,
  path: `music/${id}.mp3`, title: `song ${id}`, artist: '', album: '', durationMs: 60000, neteaseId: id });
put('/files/local.jpg');
assert.equal(CoverArtService.resolve(ctx, track(1, 'local.jpg', 'https://img/1')), 'file:///files/local.jpg');
assert.equal(CoverArtService.resolve(ctx, track(1, 'missing.jpg', 'https://img/1')), 'https://img/1');
assert.equal(CoverArtService.resolve(ctx, track(2)), '');

// 同图并发合并，96/512 分档；clear 时仍被借用的图不得提前释放。
const [small, same, large] = await Promise.all([covers.acquire(ctx, 'file:///files/local.jpg', 96),
  covers.acquire(ctx, 'file:///files/local.jpg', 96), covers.acquire(ctx, 'file:///files/local.jpg', 512)]);
assert.equal(small.pixelMap, same.pixelMap);
assert.equal(small.pixelMap.size, 96);
assert.equal(large.pixelMap.size, 512);
covers.clear();
assert.equal(small.pixelMap.releases, 0);
small.release(); small.release(); assert.equal(same.pixelMap.releases, 0);
same.release(); large.release();
assert.equal(small.pixelMap.releases, 1);
// 文件同路径更新重新解码。
const before = await covers.acquire(ctx, 'file:///files/local.jpg', 96);
put('/files/local.jpg', new Uint8Array([5, 4, 3, 2]).buffer);
const after = await covers.acquire(ctx, 'file:///files/local.jpg', 96);
assert.notEqual(before.pixelMap, after.pixelMap); before.release(); after.release();

// 三种解码尺寸只下载一次；清内存/离线后仍用磁盘，不发请求。
const url = 'https://img/shared';
const art = await Promise.all([64, 96, 512].map(size => covers.acquire(ctx, url, size)));
assert.equal(requests.filter(r => r.url === url).length, 1);
assert.equal(art.every(a => !a.placeholder), true);
art.forEach(a => a.release()); covers.clear(); offline = true;
const cached = await covers.acquire(ctx, url, 512);
assert.equal(cached.placeholder, false); cached.release();
assert.equal(requests.filter(r => r.url === url).length, 1);
const failCount = requests.length;
const failed = await covers.acquire(ctx, 'https://img/offline', 512);
assert.equal(failed.placeholder, true); failed.release();
const failedAgain = await covers.acquire(ctx, 'https://img/offline', 512);
assert.equal(failedAgain.placeholder, true); failedAgain.release();
assert.equal(requests.length, failCount + 1, 'negative cache suppresses repeated requests');
offline = false; now += 30001;
const retry = await covers.acquire(ctx, 'https://img/offline', 512);
assert.equal(retry.placeholder, false); retry.release();

// 本地损坏/缺失/无封面统一占位，取色不提取占位颜色；异常路径释放 ImageSource。
put('/files/bad.jpg', 'corrupt');
const bad = await covers.acquire(ctx, 'file:///files/bad.jpg', 96);
assert.equal(bad.placeholder, true); bad.release();
assert.equal(await covers.colors(ctx, ''), null);
assert.equal(await covers.colors(ctx, 'file:///files/bad.jpg'), null);
assert.ok(await covers.colors(ctx, 'file:///files/local.jpg'));
assert.equal(sources.every(s => s.releases === 1), true);
assert.equal(handles.size, 0);

// HTTP 非成功/超尺寸也统一回退，未持久化失败数据。
for (const [suffix, response] of [['404', { responseCode: 404, result: new ArrayBuffer(2) }],
  ['oversize', { responseCode: 200, result: new ArrayBuffer(8 * 1024 * 1024 + 1) }]]) {
  const gate = deferred(); gate.resolve(response); networkGates.set(`https://img/${suffix}`, gate);
  const lease = await covers.acquire(ctx, `https://img/${suffix}`, 512);
  assert.equal(lease.placeholder, true); lease.release();
}
// 磁盘最多 32 项/32MiB，旧条目清理不触碰本地 filesDir。
for (let i = 0; i < 36; i++) {
  const lease = await covers.acquire(ctx, `https://img/disk-${i}`, 96); lease.release();
}
const diskImages = () => [...files].filter(([path]) => path.startsWith('/cache/cover-art/') && path.endsWith('.img'));
assert.ok(diskImages().length <= 32);
for (let i = 0; i < 6; i++) {
  const gate = deferred(); gate.resolve({ responseCode: 200, result: new ArrayBuffer(6 * 1024 * 1024) });
  networkGates.set(`https://img/large-${i}`, gate);
  const lease = await covers.acquire(ctx, `https://img/large-${i}`, 96); lease.release();
}
assert.ok(diskImages().reduce((bytes, [, f]) => bytes + f.data.byteLength, 0) <= 32 * 1024 * 1024);
assert.ok(files.has('/files/local.jpg'));

// 缓存容量约束，活跃图不会被淘汰；归还后释放。
const pinned = await covers.acquire(ctx, 'file:///files/local.jpg', 512);
for (let i = 0; i < 40; i++) {
  put(`/files/${i}.jpg`);
  const lease = await covers.acquire(ctx, `file:///files/${i}.jpg`, 512); lease.release();
}
assert.equal(pinned.pixelMap.releases, 0);
assert.ok(maps.filter(m => m.releases === 0).length <= 9);
pinned.release(); covers.clear();
assert.ok(maps.every(m => m.releases === 1));

// 快速切歌/组件离开/clear 期间解码迟到：旧图不提交且归还。
const { CoverLoadState } = load('service/cover/CoverLoadState.ets', ['CoverLoadState'], { CoverArtService });
const loader = new CoverLoadState();
put('/files/slow.jpg'); const slow = deferred(); decodeGates.set('/files/slow.jpg', slow);
const displayed = [];
const pendingOld = loader.load(ctx, 'file:///files/slow.jpg', 96, pm => displayed.push(pm?.input ?? null));
await loader.load(ctx, 'file:///files/local.jpg', 96, pm => displayed.push(pm?.input ?? null));
covers.clear(); slow.resolve(); await pendingOld;
assert.equal(displayed.at(-1), '/files/local.jpg');
assert.equal(displayed.includes('/files/slow.jpg'), false);
loader.clear();
assert.ok(maps.every(m => m.releases === 1));

// 同音轨换成本地封面时保留当前图，完成后才归还旧 lease，不插入占位帧。
const continuity = [];
await loader.load(ctx, 'file:///files/local.jpg', 96, pm => continuity.push(pm?.input ?? null));
const localGate = deferred(); put('/files/downloaded.jpg'); decodeGates.set('/files/downloaded.jpg', localGate);
const oldPicture = maps.at(-1);
const transition = loader.load(ctx, 'file:///files/downloaded.jpg', 96,
  pm => continuity.push(pm?.input ?? null), true);
assert.equal(continuity.at(-1), '/files/local.jpg');
assert.equal(oldPicture.releases, 0);
localGate.resolve(); await transition;
assert.equal(continuity.at(-1), '/files/downloaded.jpg');
assert.equal(continuity.filter(p => p === null).length, 1);
loader.clear(); covers.clear();

// 真实 BackgroundPlayback：封面迟到不阻塞进度；媒体信息提交串行且最新音轨最终胜出。
const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
const metadata = [], playback = [];
let setterGate = null, sessionDestroyed = false;
const session = { async activate() {}, async setLaunchAbility() {}, on() {},
  async setAVMetadata(meta) {
    assert.equal(sessionDestroyed, false);
    const snapshot = { asset: meta.assetId, map: meta.mediaImage };
    if (setterGate) { const gate = setterGate; setterGate = null; await gate.promise; }
    if (snapshot.map) assert.equal(snapshot.map.releases, 0, 'released during metadata submission');
    metadata.push(snapshot);
  },
  async setAVPlaybackState(state) { playback.push(state); },
  async destroy() { sessionDestroyed = true; }
};
const { BackgroundPlayback } = load('service/playback/BackgroundPlayback.ets', ['BackgroundPlayback'], {
  DesktopLyrics: { getInstance: () => ({ attach() {}, async detach() {}, setContentAvailable() {} }) },
  CoverArtService, PlayerState, PlayMode, PLAYBACK_DESTINATION: 'now-playing', hilog: { error() {}, warn() {} },
  avSession: { async createAVSession() { return session; }, PlaybackState: {}, LoopMode: {} },
  wantAgent: { async getWantAgent() { return {}; }, OperationType: { START_ABILITY: 1 },
    WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 } },
  backgroundTaskManager: { async stopBackgroundRunning() {}, async startBackgroundRunning() {}, BackgroundMode: {} }
});
const bp = BackgroundPlayback.getInstance(); await bp.init(ctx);
const slowUrl = 'https://img/slow-system'; const netSlow = deferred(); networkGates.set(slowUrl, netSlow);
const a = track(-1, '', slowUrl); a.mediaRef = 'source-a:1';
await bp.sync(a, PlayerState.PLAYING, 1000, 60000, PlayMode.SEQUENTIAL, true);
await flush();
assert.equal(playback.length, 1, 'state synchronization must not wait for cover');
assert.equal(metadata.at(-1).asset, 'source-a:1');
const b = track(-1, 'local.jpg'); b.mediaRef = 'source-b:1';
await bp.sync(b, PlayerState.PLAYING, 2000, 60000, PlayMode.SEQUENTIAL, true); await flush();
assert.equal(metadata.at(-1).asset, 'source-b:1');
assert.equal(metadata.at(-1).map.input, '/files/local.jpg');
const writes = metadata.length, mapCount = maps.length;
for (let i = 0; i < 20; i++) await bp.sync(b, PlayerState.PLAYING, 3000 + i, 60000, PlayMode.SEQUENTIAL, true);
await flush(); assert.equal(metadata.length, writes); assert.equal(maps.length, mapCount);
netSlow.resolve({ responseCode: 200, result: new Uint8Array([1, 2, 3]).buffer }); await flush();
assert.equal(metadata.at(-1).asset, 'source-b:1');

// 已开始的旧 setAVMetadata 卡住，新写入排在其后；旧图直到提交结束仍存活。
const stalled = deferred(); setterGate = stalled;
await bp.sync(track(3, 'local.jpg'), PlayerState.PLAYING, 0, 60000, PlayMode.SEQUENTIAL, true); await flush();
await bp.sync(track(4), PlayerState.PAUSED, 0, 60000, PlayMode.SEQUENTIAL, true);
stalled.resolve(); await flush();
assert.equal(metadata.at(-1).asset, '4');
assert.equal(metadata.at(-1).map instanceof Object, true);
await bp.sync(null, PlayerState.IDLE, 0, 0, PlayMode.SEQUENTIAL, true); await flush();
assert.equal(metadata.at(-1).asset, '');
// 销毁会话后仍在网络中的封面迟到，不写已销毁会话、不泄漏借用。
const dying = deferred(); networkGates.set('https://img/destroying', dying);
await bp.sync(track(5, '', 'https://img/destroying'), PlayerState.PLAYING, 0, 60000, PlayMode.SEQUENTIAL, true);
await flush();
await bp.release(); covers.clear();
const destroyedWrites = metadata.length;
dying.resolve({ responseCode: 200, result: new Uint8Array([1, 2, 3]).buffer }); await flush(); covers.clear();
assert.equal(metadata.length, destroyedWrites);
assert.equal(sessionDestroyed, true);
assert.ok(maps.every(m => m.releases === 1));
assert.equal(httpDestroyed, requests.length);

// 在线转本地保留同音轨封面回退、当前音频会话/位置，系统元数据立即更新。
let systemUpdates = 0;
const playerViewModel = { currentTrack: null, positionMs: 2345, durationMs: 60000,
  requestId: 0, isCurrentRequest(request) { return request === this.requestId; },
  state: PlayerState.PLAYING, trackChangeHandler: null, coverColorHandler: null,
  async playTrack(t) { this.currentTrack = t; } };
const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
  QueueEngine, PlayMode, PlayerState, playerViewModel, setInterval() {},
  LibraryStore: { getInstance() { return { async savePlayerState() {} }; } },
  BackgroundPlayback: { getInstance() { return { sync() { systemUpdates++; } }; } }
});
const queue = new QueueViewModel(); const online = track(-7, '', url); online.neteaseId = 7;
await queue.playFromList([online], 0, ctx);
const local = track(70, 'missing.jpg'); local.neteaseId = 7;
queue.swapCurrentWithLocal(local);
assert.equal(playerViewModel.positionMs, 2345);
assert.equal(playerViewModel.currentTrack, local);
assert.equal(CoverArtService.identity(local), CoverArtService.identity(online));
assert.equal(queue.queueTracks[0], local);
assert.equal(CoverArtService.resolve(ctx, local), url);
assert.equal(systemUpdates, 1);
put('/files/missing.jpg'); assert.equal(CoverArtService.resolve(ctx, local), 'file:///files/missing.jpg');
await queue.playFromList([online], 0, ctx);
queue.updateCurrentCover(online, 'https://img/late-detail');
assert.equal(playerViewModel.currentTrack.streamCoverUrl, 'https://img/late-detail');
assert.equal(queue.queueTracks[0], playerViewModel.currentTrack);
queue.updateCurrentCover(online, 'https://img/stale');
assert.equal(playerViewModel.currentTrack.streamCoverUrl, 'https://img/late-detail');
assert.equal(playerViewModel.positionMs, 2345);

// 在线音乐 VM 的封面详情迟迟不返回时，播放与下载入口仍能完成。
const details = deferred(), started = [];
const coverPlayer = { errorText: '', currentTrack: null,
  beginTrack(track, context, ready) { this.currentTrack = track; this.ready = ready; return 1; },
  isCurrentRequest(request) { return request === 1; } };
const { OnlineMusicViewModel } = load('viewmodel/OnlineMusicViewModel.ets', ['OnlineMusicViewModel'], {
  NetEaseApi: { async resolveUrl() { return 'https://audio/1'; }, songDetailCover() { return details.promise; } },
  OnlineDownloadService: { async findLocal() { return null; }, async ensureLocal() { return track(10); } },
  queueViewModel: { async playFromList(tracks) { started.push(tracks[0]); coverPlayer.currentTrack = tracks[0]; coverPlayer.ready(1); }, updateCurrentCover() {}, swapCurrentWithLocal() {} },
  playerViewModel: coverPlayer, PlayerState
});
await new OnlineMusicViewModel().playSong(ctx, { id: 1, name: 'slow-cover', artist: '', album: '',
  durationMs: 0, coverUrl: '' });
assert.equal(started.length, 1);
details.resolve('https://img/details'); await flush();
console.log('PASS: cover resolution, size/cache bounds, offline/retry, native-resource ownership, stale loads, AVSession ordering/progress, online-to-local continuity.');
