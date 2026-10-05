// Node 24+: actual ArkTS queue/player/online/download logic; only Kit, HTTP and SQLite boundaries are controlled.
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
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const flush = async () => { for (let i = 0; i < 5; i++) await new Promise(r => setImmediate(r)); };
const identity = load('model/OnlineTrackIdentity.ets', ['createOnlineTrack', 'canDownloadNetEase']);
const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
class ApiError extends Error { constructor(code, message) { super(message); this.code = code; } }
const refs = { netease: 'catalog:netease:123', qq: 'resource:qq:string-a', kugou: 'resource:kugou:string-b' };
const song = (source, id = 123, ref = refs.netease) => ({ id, source, sourceId: String(id), mediaRef: ref,
  catalogRef: ref, playbackRef: ref, lyricsRef: ref, name: `目录 ${ref}`, artist: '目录歌手',
  album: '目录专辑', coverUrl: 'https://cover/original', durationMs: 90000 });
const original = song('api-enhanced');
const local = (id = 70) => ({ id, path: 'music/123.mp3', title: '本地旧名', artist: '本地歌手', album: '',
  durationMs: 90000, coverPath: 'covers/123.jpg', importedAt: 1, missing: false, neteaseId: 123 });
const context = { filesDir: '/sandbox' };
const files = new Set(['/sandbox/music/offline.mp3']);
const resolutions = [], downloads = [], reads = [], inserts = [], deletions = [], history = [];
const favorites = new Set([70]);
let stored = null, downloadGate = null, downloadFailure = false;
let response = ref => ({ audioIntegrity: { status: 'full', reason: 'controlled_full', catalogDurationMs: 90000, resourceDurationMs: 90000, evidence: ['controlled'] }, url: 'https://audio/current.mp3', catalogRef: ref, playbackRef: ref,
  lyricsRef: ref, playbackSource: ref === refs.netease ? 'api-enhanced' : 'meting-tencent', lyricsSource: 'api-enhanced' });
const api = {
  async resolvePlayback(_context, id, ref = '') {
    resolutions.push({ id, ref });
    return ref ? response(ref) : { audioIntegrity: { status: 'full', reason: 'controlled_full', catalogDurationMs: 90000, resourceDurationMs: 90000, evidence: ['controlled'] }, url: 'https://audio/legacy.mp3', playbackSource: 'api-enhanced' };
  },
  async songDetailCover() { return 'https://cover/original'; },
  async lyricRaw() { return { lrc: '[00:00]目录歌词', yrc: '' }; }
};
const store = {
  async getTrackByNeteaseId(id) { reads.push(id); return stored; },
  async deleteTrack(id) { deletions.push(id); stored = null; },
  async insertTrack(track) { inserts.push({ ...track }); stored = { ...track, id: 70 }; return 70; },
  async indexTrackMeta() {}, async savePlayerState() {}, async updateTrackCover() {},
  async insertHistory(id) { history.push(id); }
};
const fileIo = {
  OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 }, accessSync: path => files.has(path),
  statSync: () => ({ size: 42 }), mkdirSync: path => files.add(path),
  openSync: path => ({ fd: path }), writeSync: path => files.add(path), closeSync() {}
};
const { OnlineDownloadService } = load('service/network/OnlineDownloadService.ets', ['OnlineDownloadService'], {
  ...identity, NetEaseApi: api, LibraryStore: { getInstance: () => store }, fileIo,
  hilog: { error() {} }, parseYrc: () => [], formatLrc: () => '',
  ApiClient: { async download(url, path) {
    downloads.push({ url, path });
    if (downloadGate && path.includes('/music/')) await downloadGate.promise;
    if (downloadFailure && path.includes('/music/')) throw new Error('controlled transport failure');
    files.add(path);
  } }
});
const sessions = [];
class Session {
  constructor() { sessions.push(this); }
  async release() { this.isLoaded = false; }
  async playUrl(url, cb) { this.url = url; this.callbacks = cb; this.isLoaded = true; this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING); }
  async playFile(path, cb) { this.file = path; return this.playUrl(path, cb); }
  setVolume() {} getDuration() { return 90000; } seekTo() {}
}
const background = { sync() {}, startLongTask() {}, stopLongTask() {} };
const deps = { ...identity, ApiError, NetEaseApi: api, OnlineDownloadService, PlayerState, SleepTimer, PlayMode,
  PlayerSession: Session, fileIo, hilog: { error() {} },
  LibraryStore: { getInstance: () => store }, BackgroundPlayback: { getInstance: () => background } };
const { playerViewModel: player } = load('viewmodel/PlayerViewModel.ets', ['playerViewModel'], deps);
const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
  ...deps, QueueEngine, playerViewModel: player, setInterval() {}
});
const queue = new QueueViewModel();
const { onlineMusicViewModel: online } = load('viewmodel/OnlineMusicViewModel.ets', ['onlineMusicViewModel'], {
  ...deps, playerViewModel: player, queueViewModel: queue
});
// Online favorites and playlist rows share this production handler.
const pageSource = readFileSync(new URL('pages/PlaylistsPage.ets', root), 'utf8');
const pageMethod = pageSource.match(/private async playOnlineSong\([\s\S]*?\n  }/)[0].replace(/^private /, '');
const page = runInNewContext(stripTypeScriptTypes(`class Page { ${pageMethod} }\nnew Page()`, { mode: 'transform' }),
  { playerViewModel: player, Error });
page.ctx = () => context; page.onlineVm = online;

// Same numeric IDs across platforms, opaque string IDs, repeated selections and zero-ID entries coexist.
const selections = [original, song('meting-tencent', 123, refs.qq),
  { ...song('meting-kugou', 0, refs.kugou), sourceId: 'hash-B' },
  { ...song('meting-tencent', 0, 'resource:qq:string-c'), sourceId: 'mid-C' },
  song('meting-tencent', 0, refs.qq), song('meting-tencent', 0, refs.qq)];
const tracks = selections.map(identity.createOnlineTrack);
assert.equal(new Set(tracks.map(t => t.id)).size, selections.length);
assert.ok(tracks.every(t => t.id < -1));
await queue.playFromList(tracks, 0, context);
assert.equal(queue.queueTracks.length, selections.length);
for (let i = 1; i < tracks.length; i++) {
  await queue.playNext();
  assert.equal(player.currentTrack.id, tracks[i].id);
  assert.equal(player.currentTrack.title, selections[i].name);
}
queue.move(5, 0); assert.equal(queue.currentId, tracks[5].id);
assert.equal(queue.queueTracks[0].catalogRef, selections[5].catalogRef);
assert.equal(downloads.length, 0);

// Catalog and search hints say NetEase; the actual playback source says QQ. Never read/delete/insert NetEase cache.
stored = local(); files.add('/sandbox/music/123.mp3');
response = ref => ({ audioIntegrity: { status: 'full', reason: 'controlled_full', catalogDurationMs: 90000, resourceDurationMs: 90000, evidence: ['controlled'] }, url: 'https://audio/qq.mp3', catalogRef: ref, playbackRef: refs.qq,
  lyricsRef: ref, playbackSource: 'meting-tencent', lyricsSource: 'api-enhanced' });
for (const selected of [original, { ...original, mediaRef: undefined, catalogRef: undefined, playbackRef: undefined, lyricsRef: undefined }]) {
  // The second selection represents the existing v1 online profile/playlist entry.
  const oldResolve = api.resolvePlayback;
  if (!selected.mediaRef) api.resolvePlayback = async () => ({ ...response(undefined), catalogRef: undefined });
  const counts = [reads.length, downloads.length, inserts.length, deletions.length];
  await page.playOnlineSong(selected); await flush();
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack.playbackSource, 'meting-tencent');
  assert.equal(player.currentTrack.title, original.name);
  assert.ok(player.currentTrack.id < -1);
  assert.deepEqual([reads.length, downloads.length, inserts.length, deletions.length], counts);
  api.resolvePlayback = oldResolve;
}

// A late result from an old row cannot overwrite the currently selected row's feedback.
const rowResolve = api.resolvePlayback, lateRow = deferred(); let firstRow = true;
api.resolvePlayback = async () => { if (firstRow) { firstRow = false; return lateRow.promise; } return response(refs.netease); };
const oldRow = page.playOnlineSong({ ...original, name: '旧点播' });
await page.playOnlineSong({ ...original, name: '新点播' });
lateRow.resolve(response(refs.netease)); await oldRow; await flush();
assert.equal(player.currentTrack.title, '新点播');
assert.equal(page.onlineStatus, '正在播放「新点播」');
assert.equal(downloads.length, 0);
api.resolvePlayback = rowResolve;

// Defense at the download boundary rejects cross-source data before any SQLite/file action.
const cross = { ...player.currentTrack };
const before = [reads.length, downloads.length, inserts.length, deletions.length];
await assert.rejects(OnlineDownloadService.ensureLocal(context, original, () => {}, cross));
assert.deepEqual([reads.length, downloads.length, inserts.length, deletions.length], before);

// Same recording switches only audio: a local/favorited ID and catalog/cover remain stable.
const favored = { ...local(), catalogRef: refs.netease, mediaRef: refs.netease,
  playbackRef: refs.qq, streamUrl: 'https://audio/old.mp3', streamCoverUrl: original.coverUrl };
await queue.playFromList([favored], 0, context);
assert.equal(player.currentTrack.id, 70); assert.equal(favorites.has(player.currentTrack.id), true);
assert.equal(player.currentTrack.title, '本地旧名'); assert.equal(player.currentTrack.catalogRef, refs.netease);
assert.equal(player.currentTrack.streamCoverUrl, original.coverUrl);
const independent = identity.createOnlineTrack(song('meting-tencent', 0, 'different-recording'));
assert.notEqual(independent.id, favored.id); assert.equal(favorites.has(independent.id), false);

// Real NetEase path writes the resolved audio URL, then replaces only its matching transient selection.
response = ref => ({ audioIntegrity: { status: 'full', reason: 'controlled_full', catalogDurationMs: 90000, resourceDurationMs: 90000, evidence: ['controlled'] }, url: 'https://audio/resolved-full.flac?token=controlled', catalogRef: ref,
  recoveryToken: 'netease-recovery',
  playbackRef: ref, lyricsRef: ref, playbackSource: 'api-enhanced', lyricsSource: 'api-enhanced' });
stored = null; files.delete('/sandbox/music/123.mp3'); downloadGate = deferred();
const count = resolutions.length;
await online.playSong(context, original); await flush();
const pendingTrack = player.currentTrack, request = player.requestId;
player.positionMs = 2345;
assert.equal(downloads.at(-1).url, response(refs.netease).url);
assert.equal(resolutions.length, count + 1, 'download must use playback result rather than resolving again');
downloadGate.resolve(); downloadGate = null; await flush();
assert.equal(player.currentTrack.id, 70); assert.equal(queue.currentId, 70);
assert.equal(player.currentTrack.title, original.name); assert.equal(player.positionMs, 2345);
assert.equal(player.state, PlayerState.PLAYING); assert.equal(favorites.has(70), true);
assert.equal(inserts.at(-1).neteaseId, 123); assert.equal(inserts.at(-1).path, 'music/123.flac');
const current = player.currentTrack;
assert.equal(current.recoveryToken, pendingTrack.recoveryToken);
assert.equal(current.recoveryToken, 'netease-recovery');
queue.swapCurrentWithLocal(local(), pendingTrack, request, refs.netease, response(refs.netease).url);
assert.equal(player.currentTrack, current, 'duplicate completion has no effect');
// Download completion changes the queue's database identity while its open stream still owns errors.
const activeStream = sessions.at(-1), recoveryCount = resolutions.length, downloadedId = current.id;
activeStream.callbacks.onError('controlled media failure'); await flush();
assert.equal(player.state, PlayerState.PLAYING);
assert.equal(player.currentTrack, current); assert.equal(queue.currentId, downloadedId);
assert.equal(resolutions.length, recoveryCount + 1);
assert.equal(sessions.at(-1).url, response(refs.netease).url);
assert.equal(player.positionMs, 2345);
assert.equal(current.streamUrl, '', 'recovered downloaded entries retain local replay semantics');

// Existing cached record remains the favored ID after confirming actual NetEase audio.
await online.playSong(context, original); await flush();
assert.equal(player.currentTrack.id, 70); assert.equal(player.currentTrack.title, original.name);
assert.equal(favorites.has(70), true); assert.equal(sessions.at(-1).file, '/sandbox/music/123.flac');

// Repeated point plays of the same NetEase resource share one actual file/SQLite job.
stored = null; downloadGate = deferred();
const beforeRepeated = [downloads.length, inserts.length];
await online.playSong(context, original); await flush();
const superseded = player.currentTrack;
await online.playSong(context, original); await flush();
assert.notEqual(player.currentTrack.id, superseded.id);
assert.equal(downloads.length, beforeRepeated[0] + 1);
downloadGate.resolve(); downloadGate = null; await flush();
assert.equal(inserts.length, beforeRepeated[1] + 1);
assert.equal(player.currentTrack.id, 70); assert.equal(queue.currentId, 70);
assert.equal(player.currentTrack.title, original.name);

// A failed shared job releases ownership so an explicit later selection can retry.
stored = null; downloadGate = deferred(); downloadFailure = true;
await online.playSong(context, original); await flush();
await online.playSong(context, original); await flush();
downloadGate.resolve(); downloadGate = null; await flush();
assert.ok(player.currentTrack.id < 0); assert.equal(player.state, PlayerState.PLAYING);
downloadFailure = false;
await online.playSong(context, original); await flush();
assert.equal(player.currentTrack.id, 70);

// A different recording/selection and a same-catalog source switch both revoke an old completion.
for (const switchSource of [false, true]) {
  stored = null; downloadGate = deferred();
  await online.playSong(context, original); await flush();
  const old = player.currentTrack, oldRequest = player.requestId, oldRef = old.playbackRef, oldUrl = old.streamUrl;
  response = ref => ({ audioIntegrity: { status: 'full', reason: 'controlled_full', catalogDurationMs: 90000, resourceDurationMs: 90000, evidence: ['controlled'] }, url: 'https://audio/new-qq.mp3', catalogRef: switchSource ? refs.netease : ref,
    playbackRef: refs.qq, lyricsRef: ref, playbackSource: 'meting-tencent' });
  if (switchSource) {
    await queue.playFromList([{ ...old, playbackRef: refs.qq }], 0, context);
  } else {
    await online.playSong(context, song('meting-tencent', 0, refs.qq));
  }
  const selected = player.currentTrack;
  downloadGate.resolve(); downloadGate = null; await flush();
  assert.equal(player.currentTrack, selected); assert.ok(selected.id < -1);
  assert.equal(player.currentTrack.playbackSource, 'meting-tencent');
  queue.swapCurrentWithLocal(local(), old, oldRequest, oldRef, oldUrl);
  assert.equal(player.currentTrack, selected);
  response = ref => ({ audioIntegrity: { status: 'full', reason: 'controlled_full', catalogDurationMs: 90000, resourceDurationMs: 90000, evidence: ['controlled'] }, url: 'https://audio/netease.mp3', catalogRef: ref,
    playbackRef: ref, lyricsRef: ref, playbackSource: 'api-enhanced' });
}

// Same request ID alone is insufficient if audio was updated in-place; cover-only updates remain valid.
stored = null; downloadGate = deferred();
await online.playSong(context, original); await flush();
const previous = player.currentTrack;
previous.playbackRef = refs.qq; previous.playbackSource = 'meting-tencent'; previous.streamUrl = 'https://audio/new';
downloadGate.resolve(); downloadGate = null; await flush();
assert.equal(player.currentTrack, previous); assert.ok(previous.id < -1);
stored = null; downloadGate = deferred();
await online.playSong(context, original); await flush();
player.currentTrack.recoveryToken = 'selected-recovery'; player.currentTrack.lyricsRevision = 2;
queue.updateCurrentCover(player.currentTrack, 'https://cover/late-success');
assert.equal(player.currentTrack.recoveryToken, 'selected-recovery');
assert.equal(player.currentTrack.lyricsRevision, 2);
downloadGate.resolve(); downloadGate = null; await flush();
assert.equal(player.currentTrack.id, 70); assert.equal(player.currentTrack.streamCoverUrl, 'https://cover/late-success');
assert.equal(player.currentTrack.recoveryToken, 'selected-recovery');
assert.equal(player.currentTrack.lyricsRevision, 2);
assert.equal(player.currentTrack.streamUrl, undefined, 'subsequent queue playback uses the downloaded local file');

// Legacy real NetEase response preserves old ID-based download; local offline playback needs no network.
stored = null;
await online.playSong(context, { ...original, mediaRef: undefined, catalogRef: undefined,
  playbackRef: undefined, lyricsRef: undefined }); await flush();
assert.equal(player.currentTrack.id, 70); assert.equal(inserts.at(-1).neteaseId, 123);
assert.equal(downloads.findLast(d => d.path.endsWith('.mp3')).url, 'https://audio/legacy.mp3');
const offline = { ...local(8), path: 'music/offline.mp3', neteaseId: 0 };
const resolutionCount = resolutions.length;
const onlineResolve = api.resolvePlayback;
api.resolvePlayback = async () => { throw new Error('offline'); };
await queue.playFromList([offline], 0, context); await flush();
assert.equal(player.currentTrack.id, 8); assert.equal(player.state, PlayerState.PLAYING);
assert.equal(resolutions.length, resolutionCount); assert.equal(history.at(-1), 8);
// A real in-flight download may finish after Ability teardown, but cannot reactivate a selection.
api.resolvePlayback = onlineResolve; stored = null; downloadGate = deferred();
await online.playSong(context, original); await flush();
const closingRequest = player.requestId;
await player.dispose();
downloadGate.resolve(); downloadGate = null; await flush();
assert.equal(player.isCurrentRequest(closingRequest), false);
assert.equal(player.currentTrack, null); assert.equal(player.state, PlayerState.IDLE);
console.log('PASS: isolated online selections, stable catalog/favorites, actual-source cache/download guards, real NetEase write path, stale/duplicate/source-change completion rejection and local offline playback. Kit/SQLite/HTTP are controlled boundaries.');
