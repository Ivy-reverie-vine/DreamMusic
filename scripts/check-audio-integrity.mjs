// Node 24+: real ArkTS client logic → real NightDream HTTP/auth/SQLite/orchestration.
// HarmonyOS Kit, client storage/download and third-party network are controlled boundaries.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { startIdentityGateway } from '../../NightDream/server/test-support/identityGateway.js';

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
// Controlled WAV over real HTTP, fully read and independently measured by the Kit substitute.
const wav = Buffer.alloc(44 + 90000 * 16);
wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(8000, 24); wav.writeUInt32LE(16000, 28); wav.writeUInt16LE(2, 32);
wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(wav.length - 44, 40);
let mediaReads = 0;
const media = createServer((req, res) => {
  mediaReads++;
  if (req.url === '/fail') { res.writeHead(503); return res.end(); }
  if (req.headers.range) { res.writeHead(206, { 'Content-Range': `bytes 0-99/${wav.length}` }); return res.end(wav.subarray(0, 100)); }
  res.writeHead(200, { 'Content-Type': 'audio/wav' }); res.end(wav);
});
await new Promise(r => media.listen(0, '127.0.0.1', r));
const mediaBase = `http://127.0.0.1:${media.address().port}`;
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
      base: async () => gateway.base + '/dreammusic/api/v1',
      baseV2: async () => gateway.base + '/dreammusic/api/v2', username: () => 'identity-user',
      withApiKey: (_ctx, call) => call({ 'X-API-Key': gateway.apiKey }),
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
    async playUrl(url, cb) {
      this.url = url; this.cb = cb;
      if (url.startsWith(mediaBase)) {
        const response = await fetch(url);
        if (!response.ok) throw new Error('HTTP media failed');
        const bytes = Buffer.from(await response.arrayBuffer());
        assert.equal(bytes.length, bytes.readUInt32LE(40) + 44, 'complete WAV body');
        this.duration = bytes.readUInt32LE(40) / bytes.readUInt32LE(28) * 1000;
        assert.equal(this.duration, 90000);
      }
      this.isLoaded = true; this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING);
    }
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
  const selected = (await NetEaseApi.search(context, '目录', 0)).songs[0];
  const json = body => new Response(JSON.stringify(body), { status: 200 });
  let resource = { id: 123, url: mediaBase + '/full', time: 90000, freeTrialInfo: null };
  let detailFailed = false;
  gateway.controls.thirdPartyResponse = url => {
    if (url.pathname === '/song/url/v1') return json({ code: 200, data: [resource] });
    if (url.pathname === '/song/detail' && detailFailed) return json({ code: 503 });
    return null;
  };
  const cases = [
    ['full', 'provider_duration_and_non_trial', resource],
    ['preview', 'explicit_trial', { ...resource, freeTrialInfo: { start: 0, end: 30 } }],
    ['preview', 'resource_shorter', { ...resource, time: 30000 }],
    ['unknown', 'duration_mismatch', { ...resource, time: 120000 }],
    ['unknown', 'missing_evidence', { id: 123, url: resource.url }],
    ['unknown', 'missing_evidence', { ...resource, freeTrialInfo: undefined }],
    ['unknown', 'missing_evidence', { ...resource, time: undefined }],
    ['unavailable', 'empty_url', { ...resource, url: '' }],
    ['unavailable', 'resource_identity_mismatch', { ...resource, id: 124 }],
  ];
  // HTTP 206 prefix and complete lyrics exist even for unknown audio; neither is evidence.
  assert.equal((await fetch(resource.url, { headers: { Range: 'bytes=0-99' } })).status, 206);
  assert.ok((await NetEaseApi.lyricRaw(context, 123, selected.lyricsRef)).lrc);
  for (const [status, reason, raw] of cases) {
    gateway.orchestrator.registry.resetCircuit('api-enhanced');
    resource = raw;
    const resolution = await NetEaseApi.resolvePlayback(context, 123, selected.playbackRef);
    assert.equal(resolution.audioIntegrity.status, status); assert.equal(resolution.audioIntegrity.reason, reason);
    const readsBefore = mediaReads, downloadsBefore = downloads.length;
    if (status === 'full') {
      await online.playSong(context, selected);
      assert.equal(player.state, PlayerState.PLAYING);
      assert.equal(mediaReads, readsBefore + 1); assert.equal(downloads.length, downloadsBefore + 1);
    } else {
      await assert.rejects(online.playSong(context, selected));
      assert.equal(player.state, PlayerState.ERROR);
      assert.equal(player.currentTrack.audioIntegrity.status, status);
      assert.equal(mediaReads, readsBefore); assert.equal(downloads.length, downloadsBefore);
      assert.equal(identity.canDownloadNetEase(player.currentTrack), false);
      assert.ok(player.errorText.includes('重试'));
    }
    assert.equal(player.currentTrack.catalogRef, selected.catalogRef);
    assert.equal(player.currentTrack.title, selected.name);
    // Queue playback and retry independently enforce the gate too.
    await player.retry();
    assert.equal(player.state, status === 'full' ? PlayerState.PLAYING : PlayerState.ERROR);
    console.log(`PASS ${status}: ${reason}`);
  }
  gateway.orchestrator.registry.resetCircuit('api-enhanced');
  resource = cases[0][2]; detailFailed = true;
  await assert.rejects(online.playSong(context, selected));
  assert.equal(player.currentTrack.audioIntegrity.status, 'unknown'); detailFailed = false;
  // Metadata passes but actual media HTTP fails: unavailable, zero downloads, retry same reference.
  resource = { ...cases[0][2], url: mediaBase + '/fail' };
  const downloadCount = downloads.length;
  await assert.rejects(online.playSong(context, selected));
  assert.equal(player.errorCode, 'MEDIA_READ_FAILED');
  assert.equal(player.currentTrack.audioIntegrity.status, 'unavailable');
  assert.equal(player.currentTrack.audioIntegrity.reason, 'media_read_failed');
  assert.equal(downloads.length, downloadCount);
  const failedId = player.currentTrack.id;
  resource = cases[0][2];
  await player.retry();
  assert.equal(player.state, PlayerState.PLAYING); assert.equal(player.currentTrack.id, failedId);
  assert.equal(sessions.at(-1).duration, 90000);
  // v1 online-profile entries still use confirmed real NetEase evidence and downloads.
  await gateway.request('/dreammusic/api/v1/login/qr/check?key=controlled', { headers: { Cookie: gateway.cookie } });
  await online.playSong(context, { ...selected, mediaRef: undefined, catalogRef: undefined, playbackRef: undefined, lyricsRef: undefined });
  assert.equal(player.state, PlayerState.PLAYING); assert.equal(player.currentTrack.audioIntegrity.status, 'full');
  const local = { id: 7, path: 'music/local.wav', title: '本地', artist: '', album: '', durationMs: 90000,
    coverPath: '', importedAt: 0, missing: false, neteaseId: 0 };
  await queue.playFromList([local], 0, context);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.ok(gateway.controls.calls.filter(url => url.pathname === '/song/url/v1').every(url => url.searchParams.get('id') === '123'));
  assert.equal(gateway.controls.calls.some(url => url.host === 'meting.test'), false, 'no cross-source fallback');
  console.log('PASS: real HTTP → adapters/gateway → ArkTS API/player/queue/download gate; real controlled WAV read and measured, preview/unknown/unavailable, media failure and same-resource retry, v1 and offline regression. Third-party samples and HarmonyOS decoding remain unverified.');
} finally { await new Promise(r => media.close(r)); await gateway.close(); }
