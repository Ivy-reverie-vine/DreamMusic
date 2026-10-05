// Node 24+: real ArkTS client logic → real NightDream HTTP/auth/SQLite/orchestration.
// HarmonyOS Kit, client storage/download and third-party network are controlled boundaries.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { startIdentityGateway } from '../../NightDream/server/test-support/identityGateway.js';
import { createMediaRef } from '../../NightDream/server/mediaContract.js';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, deps = {}) {
  const source = readFileSync(new URL(path, root), 'utf8').replace(/^import[\s\S]*?;\r?\n/gm, '')
    .replace(/^@Observed\r?\n/gm, '').replace(/^export /gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { Error, Date, setTimeout, clearTimeout, ...deps }, { filename: path });
}
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const flush = () => new Promise(r => setImmediate(r));
async function until(predicate) {
  const deadline = Date.now() + 5000;
  while (!predicate()) { assert.ok(Date.now() < deadline, 'public state did not settle'); await new Promise(r => setTimeout(r, 10)); }
}
const gateway = await startIdentityGateway();
let activeGateway = gateway;
try {
  const requests = [];
  const hilog = { error() {}, debug() {} };
  const { normalizeBaseUrl } = load('service/network/HealthStateMachine.ets', ['normalizeBaseUrl']);
  const { ApiClient, ApiError } = load('service/network/ApiClient.ets', ['ApiClient', 'ApiError'], {
    normalizeBaseUrl, hilog,
    http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 }, createHttp: () => ({
      async request(url, options) {
        requests.push(new URL(url));
        const response = await fetch(url, { method: options.method, headers: options.header });
        return { responseCode: response.status, result: await response.text(), header: Object.fromEntries(response.headers) };
      }, destroy() {},
    }) },
  });
  const { NetEaseApi } = load('service/network/NetEaseApi.ets', ['NetEaseApi'], {
    ApiClient, ApiError, DreamMusicAuth: {
      base: async () => activeGateway.base + '/dreammusic/api/v1',
      baseV2: async () => activeGateway.base + '/dreammusic/api/v2', username: () => 'identity-user',
      withApiKey: (_ctx, call) => call({ 'X-API-Key': activeGateway.apiKey }),
    }, playbackDiagnostics: { record() {} }, classifyPlaybackError: () => 'failure',
    DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL: 'empty', DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT: 'timeout',
  });
  const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
  const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
  const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
  const identity = load('model/OnlineTrackIdentity.ets', ['createOnlineTrack', 'canDownloadNetEase']);
  const sessions = [], downloads = [], localLookups = [], downloadResults = [];
  let localResult = null;
  class Session {
    constructor() { sessions.push(this); }
    async release() { this.isLoaded = false; }
    async playUrl(url, cb) { this.url = url; this.cb = cb; this.isLoaded = true; this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING); }
    async playFile(path, cb) { return this.playUrl(path, cb); }
    setVolume() {} getDuration() { return 90000; } seekTo() {}
  }
  const store = { async savePlayerState() {}, async insertHistory() {} };
  const background = { sync() {}, startLongTask() {}, stopLongTask() {} };
  const deps = { ...identity, PlayerSession: Session, SleepTimer, PlayerState, PlayMode, ApiError, NetEaseApi,
    fileIo: { accessSync: () => true }, hilog,
    LibraryStore: { getInstance: () => store }, BackgroundPlayback: { getInstance: () => background } };
  const { playerViewModel: player } = load('viewmodel/PlayerViewModel.ets', ['playerViewModel'], deps);
  const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
    ...deps, QueueEngine, playerViewModel: player, setInterval() {},
  });
  const queue = new QueueViewModel();
  const parser = load('service/lyrics/LrcParser.ets', ['parseLrc', 'parseYrc', 'findActiveLine']);
  const { lyricsViewModel: lyrics, LyricsLoadState } = load('viewmodel/LyricsViewModel.ets', ['lyricsViewModel', 'LyricsLoadState'], {
    ...parser, playerViewModel: player, NetEaseApi, LrcLoader: { loadForTrack: () => null },
  });
  const { onlineMusicViewModel: online } = load('viewmodel/OnlineMusicViewModel.ets', ['onlineMusicViewModel'], {
    ...deps, playerViewModel: player, queueViewModel: queue,
    OnlineDownloadService: {
      async findLocal(_ctx, id) { localLookups.push(id); return localResult; },
      ensureLocal(_ctx, song) { downloads.push(song.id); const pending = deferred(); downloadResults.push(pending); return pending.promise; },
    },
  });
  const context = { filesDir: '/sandbox' };
  lyrics.setContext(context);
  const page = await NetEaseApi.search(context, '目录', 0);
  const selected = page.songs[0];
  assert.equal(selected.catalogRef, selected.mediaRef);
  await online.playSong(context, selected);
  await until(() => lyrics.loadState === LyricsLoadState.READY);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.ok(queue.currentId < -1);
  assert.equal(player.currentTrack.catalogRef, selected.catalogRef);
  assert.equal(player.currentTrack.playbackRef, selected.playbackRef);
  assert.equal(player.playbackSourceText, '网易云');
  assert.equal(lyrics.lyricsRef, selected.lyricsRef);
  assert.equal(lyrics.lyricsSource, 'api-enhanced');
  assert.equal(lyrics.lines[0].text, '目录歌词');
  assert.equal(sessions.at(-1).url, 'https://audio.test/123.mp3');
  assert.equal(player.currentTrack.title, selected.name);
  assert.equal(player.currentTrack.artist, selected.artist);
  assert.equal(player.currentTrack.streamCoverUrl, selected.coverUrl);
  assert.equal(await NetEaseApi.songDetailCover(context, selected.id, selected.catalogRef), selected.coverUrl);
  assert.equal(requests.find(r => r.pathname.endsWith('/song/detail')).searchParams.get('mediaRef'), selected.catalogRef);
  assert.equal(requests.find(r => r.pathname.endsWith('/song/url/v1')).searchParams.get('mediaRef'), selected.playbackRef);
  assert.equal(requests.find(r => r.pathname.endsWith('/lyric/new')).searchParams.get('mediaRef'), selected.lyricsRef);
  assert.deepEqual(downloads, [123]);

  const downloaded = { id: 70, path: 'music/123.mp3', title: '迟到文件旧名', artist: '文件歌手', album: '',
    durationMs: 90000, coverPath: 'covers/old.jpg', importedAt: 0, missing: false, neteaseId: 123 };
  downloadResults[0].resolve(downloaded);
  await until(() => player.currentTrack.id === 70);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack.title, selected.name);
  assert.equal(player.currentTrack.artist, selected.artist);
  assert.equal(player.currentTrack.streamCoverUrl, selected.coverUrl);
  assert.equal(player.currentTrack.catalogRef, selected.catalogRef);
  assert.equal(player.currentTrack.playbackRef, selected.playbackRef);

  // Real Meting result consumed by the same public queue/player boundary; no numeric-ID download.
  const qq = (await gateway.request('/dreammusic/api/v2/search?keywords=QQ&source=meting-tencent', {
    headers: { 'X-API-Key': gateway.apiKey },
  })).body.data[0];
  const qqSong = { id: 0, name: qq.title, artist: qq.artists[0], album: '', coverUrl: qq.album.pictureUrl,
    durationMs: qq.durationMs, mediaRef: qq.mediaRef, source: qq.source,
    catalogRef: qq.catalogRef, playbackRef: qq.playbackRef, lyricsRef: qq.lyricsRef };
  await online.playSong(context, qqSong);
  await until(() => lyrics.loadState === LyricsLoadState.READY);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.playbackSourceText, '腾讯 / QQ');
  assert.equal(lyrics.lyricsSource, 'meting-tencent');
  assert.equal(player.currentTrack.neteaseId, 0);
  assert.deepEqual(downloads, [123]);
  assert.deepEqual(localLookups, [123]);

  // Cached NetEase file remains local-first while preserving this catalog selection.
  localResult = { ...downloaded, title: '已缓存旧名', artist: '旧歌手' };
  const resolutionCount = requests.filter(r => r.pathname.endsWith('/song/url/v1')).length;
  await online.playSong(context, selected);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack.id, 70);
  assert.equal(player.currentTrack.title, selected.name);
  assert.equal(player.currentTrack.artist, selected.artist);
  assert.equal(player.currentTrack.catalogRef, selected.catalogRef);
  assert.equal(requests.filter(r => r.pathname.endsWith('/song/url/v1')).length, resolutionCount + 1,
    'confirm actual audio before reusing the numeric-ID cache');
  assert.equal(localResult.title, '已缓存旧名');
  localResult = null;

  // Native-free local playback remains functional; late resolution/cover/lyrics cannot overwrite it.
  const local = { id: 7, path: 'music/local.mp3', title: '本地歌', artist: '本地歌手', album: '',
    durationMs: 90000, coverPath: '', importedAt: 0, missing: false, neteaseId: 0 };
  const oldCover = player.currentTrack;
  await queue.playFromList([local], 0, context);
  queue.updateCurrentCover(oldCover, 'https://cover.test/late.jpg');
  assert.equal(player.currentTrack, local);
  assert.equal(player.state, PlayerState.PLAYING);
  const wait = deferred(), started = deferred();
  gateway.controls.beforeResponse = async url => {
    if (url.pathname === '/song/url/v1') { started.resolve(); await wait.promise; }
  };
  const slow = online.playSong(context, selected);
  await started.promise;
  await queue.playFromList([local], 0, context);
  wait.resolve(); await slow; await flush();
  assert.equal(player.currentTrack, local);
  assert.equal(queue.currentId, local.id);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(lyrics.lyricsRef, '');
  assert.deepEqual(downloads, [123]);
  // T07: the production API consumes BV/CID through the same resource contract.
  // Explicit unknown samples are only played by the isolated browser harness.
  gateway.controls.beforeResponse = async () => {};
  gateway.orchestrator.setSourceEnabled('bilibili', true);
  const biliRef = createMediaRef({ source: 'bilibili', sourceId: 'BV1GJ411x7h7:222' });
  gateway.controls.thirdPartyResponse = url => {
    if (url.pathname === '/x/web-interface/view') return new Response(JSON.stringify({ code: 0, data: {
      bvid: 'BV1GJ411x7h7', title: '合集', owner: { mid: 9, name: '上传者' }, pages: [
        { cid: 111, page: 1, part: '第一曲', duration: 120 }, { cid: 222, page: 2, part: '目标曲', duration: 90 }
      ]
    } }));
    if (url.pathname === '/x/player/playurl') return new Response(JSON.stringify({ code: 0, data: {
      timelength: 90000, dash: { duration: 90, audio: [{ id: 30280, mimeType: 'audio/mp4',
        codecs: 'mp4a.40.2', baseUrl: 'https://audio.test/part222.m4a' }] }
    } }));
    return null;
  };
  // No proxy means an explicit failure, never exposing required provider headers to ArkTS.
  await assert.rejects(() => NetEaseApi.resolvePlayback(context, 0, biliRef));
  const biliResult = await gateway.request('/dreammusic/api/v2/song/url/v1?' + new URLSearchParams({ mediaRef: biliRef }), {
    headers: { 'X-API-Key': gateway.apiKey }
  });
  assert.equal(biliResult.body.errorCode, 'MEDIA_PROXY_REQUIRED');
  assert.deepEqual(downloads, [123]);
  const biliGateway = await startIdentityGateway({ bilibili: true, mediaProxy: true });
  try {
    activeGateway = biliGateway;
    biliGateway.controls.thirdPartyResponse = gateway.controls.thirdPartyResponse;
    const resolution = await NetEaseApi.resolvePlayback(context, 0, biliRef);
    assert.equal(resolution.catalogRef, biliRef);
    assert.equal(resolution.playbackRef, biliRef);
    assert.equal(resolution.playbackSource, 'bilibili');
    assert.equal(resolution.audioIntegrity.status, 'unknown');
    assert.ok(resolution.url.startsWith(biliGateway.base + '/dreammusic/media/stream/'));
    const playCount = sessions.filter(session => session.url !== undefined).length;
    const lookupCount = localLookups.length;
    const biliSong = { id: 0, name: '目标曲', artist: '', album: '合集', coverUrl: '', durationMs: 90000,
      source: 'bilibili', sourceId: 'BV1GJ411x7h7:222', mediaRef: biliRef,
      catalogRef: biliRef, playbackRef: biliRef, lyricsRef: biliRef };
    await assert.rejects(() => online.playSong(context, biliSong), error => error.code === 'AUDIO_UNKNOWN');
    assert.equal(sessions.filter(session => session.url !== undefined).length, playCount,
      'unknown Bilibili audio must not be handed to Kit for playback');
    assert.deepEqual(downloads, [123]);
    assert.equal(localLookups.length, lookupCount, 'Bilibili must not enter the NetEase local cache');
    await queue.playFromList([local], 0, context);
    assert.equal(player.state, PlayerState.PLAYING);
    assert.equal(player.currentTrack, local);
  } finally { activeGateway = gateway; await biliGateway.close(); }
  console.log('PASS: real HTTP search/detail/audio/lyrics → real ArkTS API/queue/player/lyrics public state; concrete references, stable catalog display, source label, legacy download isolation, local playback and stale response rejection. Bilibili uses the same mediaRef API/proxy; unknown does not enter the production player or download chain. Kit audio/storage are controlled, not device evidence.');
} finally { await gateway.close(); }
