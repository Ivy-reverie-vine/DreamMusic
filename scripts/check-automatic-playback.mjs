// Actual ArkTS API/search click/queue/player → actual authenticated gateway/SQLite/adapters.
// Only third-party HTTP, HarmonyOS Kit and client persistence/download are controlled.
import assert from 'node:assert/strict';
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
function componentMethods(names, deps) {
  const source = readFileSync(new URL('components/OnlineSearchView.ets', root), 'utf8');
  const bodies = names.map(name => {
    const match = new RegExp(`\\n  (?:private )?(?:static )?(?:async )?${name}\\(`).exec(source);
    const start = match.index + 3, brace = source.indexOf('{', start);
    let depth = 1, end = brace + 1;
    while (depth) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; end++; }
    return source.slice(start, end).replace(/^private /, '');
  });
  return runInNewContext(stripTypeScriptTypes(`class OnlineSearchView { ${bodies.join('\n')} }\nnew OnlineSearchView()`,
    { mode: 'transform' }), deps);
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate) {
  const deadline = Date.now() + 5000;
  while (!predicate()) { assert.ok(Date.now() < deadline, 'client did not settle'); await delay(10); }
}
const gateway = await startIdentityGateway({ mediaProxy: true });
try {
  const requests = [], sessions = [], downloads = [];
  const hilog = { error() {}, debug() {} };
  const { normalizeBaseUrl } = load('service/network/HealthStateMachine.ets', ['normalizeBaseUrl']);
  const { ApiClient, ApiError } = load('service/network/ApiClient.ets', ['ApiClient', 'ApiError'], {
    normalizeBaseUrl, hilog, http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 }, createHttp: () => {
      const controller = new AbortController();
      return { async request(url, options) {
        requests.push(new URL(url));
        const response = await fetch(url, { headers: options.header, signal: controller.signal });
        return { responseCode: response.status, result: await response.text(), header: Object.fromEntries(response.headers) };
      }, destroy() { controller.abort(); } };
    } },
  });
  const { NetEaseApi } = load('service/network/NetEaseApi.ets', ['NetEaseApi'], {
    ApiClient, ApiError, DreamMusicAuth: {
      base: async () => gateway.base + '/dreammusic/api/v1', baseV2: async () => gateway.base + '/dreammusic/api/v2',
      username: () => 'identity-user', withApiKey: (_ctx, call) => call({ 'X-API-Key': gateway.apiKey }),
    }, playbackDiagnostics: { record() {} }, classifyPlaybackError: () => 'failure',
    DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL: 'empty', DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT: 'timeout',
  });
  const identity = load('model/OnlineTrackIdentity.ets', ['createOnlineTrack', 'canDownloadNetEase']);
  const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
  const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
  const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
  class Session {
    constructor() { sessions.push(this); }
    async release() { this.isLoaded = false; }
    async playUrl(url, cb) { this.url = url; this.isLoaded = true; this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING); }
    async playFile(path, cb) { return this.playUrl(path, cb); }
    setVolume() {} getDuration() { return 90000; } seekTo() {}
  }
  const deps = { ...identity, PlayerSession: Session, PlayerState, PlayMode, SleepTimer, ApiError, NetEaseApi, hilog,
    fileIo: { accessSync: () => true }, LibraryStore: { getInstance: () => ({ async savePlayerState() {}, async insertHistory() {} }) },
    BackgroundPlayback: { getInstance: () => ({ sync() {}, startLongTask() {}, stopLongTask() {} }) } };
  const { playerViewModel: player } = load('viewmodel/PlayerViewModel.ets', ['playerViewModel'], deps);
  const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
    ...deps, QueueEngine, playerViewModel: player, setInterval() {},
  });
  const queue = new QueueViewModel();
  const { onlineMusicViewModel: online } = load('viewmodel/OnlineMusicViewModel.ets', ['onlineMusicViewModel'], {
    ...deps, playerViewModel: player, queueViewModel: queue,
    OnlineDownloadService: { async findLocal() { return null; }, async ensureLocal(_ctx, song) { downloads.push(song); throw new Error('test boundary'); } },
  });
  const network = { markOnline() {}, markOffline() {} };
  const { OnlineSearchViewModel } = load('viewmodel/OnlineSearchViewModel.ets', ['OnlineSearchViewModel'], {
    NetEaseApi, ApiError, networkViewModel: network,
  });
  const vm = new OnlineSearchViewModel(), context = { filesDir: '/sandbox' };
  const panel = componentMethods(['streamAndPlay', 'reportConnectivity', 'playEntry'], {
    ApiError, playerViewModel: player, onlineMusicViewModel: online, networkViewModel: network,
  });
  Object.assign(panel, { search: vm, ctx: () => context, busyId: -1, busyRef: '', progressText: '', errorText: '', errorCode: '' });
  const json = body => new Response(JSON.stringify(body), { status: 200 });
  let states = {}, timings = {};
  function configure(next, waits = {}) {
    states = next; timings = waits;
    gateway.controls.calls.length = 0;
    gateway.orchestrator.playbackBudget = { totalMs: 500, reserveMs: 150 };
    for (const source of gateway.orchestrator.registry.sources.values()) {
      source.adapter.clearCache?.(); gateway.orchestrator.resetSourceCircuit(source.id);
    }
    gateway.controls.beforeResponse = (url, signal) => {
      const source = url.host === 'upstream.test' ? 'netease' : url.searchParams.get('server');
      const wait = timings[source] || 0;
      return wait ? new Promise((resolve, reject) => {
        const timer = setTimeout(resolve, wait);
        signal.addEventListener('abort', () => { clearTimeout(timer); reject(new Error('cancelled')); }, { once: true });
      }) : Promise.resolve();
    };
    gateway.controls.thirdPartyResponse = url => {
      const api = url.host === 'upstream.test', state = states[api ? 'netease' : url.searchParams.get('server')] ?? 'unavailable';
      if (!api && url.searchParams.get('type') === 'search') return json([{ id: url.searchParams.get('server') + '-001',
        name: gateway.song.name, artist: ['原歌手'], album: '目录专辑', duration: 90 }]);
      if (!api && url.searchParams.get('type') === 'song') return json([{ id: url.searchParams.get('id'), duration: 90 }]);
      if (api && url.pathname === '/song/url/v1') return json({ code: 200, data: [{ id: 123, time: 90000,
        url: state === 'unavailable' ? '' : 'https://audio.test/netease.mp3',
        ...(state === 'unknown' ? {} : { freeTrialInfo: state === 'preview' ? { start: 0, end: 30 } : null }) }] });
      if (!api && url.searchParams.get('type') === 'url') return json({ url: state === 'unavailable' ? '' : 'https://audio.test/' + url.searchParams.get('server') + '.mp3',
        durationMs: 90000, ...(state === 'unknown' ? {} : { isPreview: state === 'preview' }) });
      return null;
    };
  }
  configure({ netease: 'unavailable', tencent: 'full', kugou: 'unknown' });
  vm.keyword = '目录'; await vm.search(context);
  const group = vm.groups[0], song = vm.groupSong(group);
  assert.equal(group.entries.length, 3);
  async function click() {
    panel.playEntry(group, song, true);
    await until(() => panel.busyId === -1 && panel.busyRef === '');
  }
  configure({ netease: 'unavailable', tencent: 'full', kugou: 'unknown' }, { tencent: 35 });
  await click();
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack.playbackSource, 'meting-tencent');
  assert.equal(player.currentTrack.catalogRef, song.catalogRef);
  assert.equal(player.currentTrack.lyricsRef, song.lyricsRef);
  assert.equal(player.currentTrack.title, song.name);
  assert.equal(player.currentTrack.streamCoverUrl, song.coverUrl);
  assert.equal(downloads.length, 0);
  assert.equal(identity.canDownloadNetEase(player.currentTrack), false);
  assert.ok(requests.at(-1).searchParams.get('automatic'));
  const queueId = queue.currentId;
  player.failRequest(player.requestId, 'MEDIA_READ_FAILED');
  configure({ netease: 'preview', tencent: 'full' });
  await player.retry();
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(queue.currentId, queueId);
  assert.equal(player.currentTrack.catalogRef, song.catalogRef);
  assert.equal(requests.at(-1).searchParams.get('mediaRef'), player.currentTrack.playbackRef, 'URL recovery reparses the resource that actually played');
  assert.equal(requests.at(-1).searchParams.get('recover'), 'true');
  assert.equal(player.playbackSourceText, '腾讯 / QQ');
  assert.equal(downloads.length, 0);
  configure({ netease: 'full', tencent: 'full', kugou: 'full' }, { netease: 300, tencent: 20, kugou: 320 });
  await click(); const picked = player.currentTrack.playbackRef;
  await delay(380);
  assert.equal(player.currentTrack.playbackRef, picked);
  assert.equal(player.currentTrack.playbackSource, 'meting-tencent');
  assert.equal(downloads.length, 0);
  for (const statuses of [{ netease: 'preview', tencent: 'unknown', kugou: 'unavailable' }, {}]) {
    configure(statuses); await click();
    assert.equal(player.state, PlayerState.ERROR);
    assert.equal(player.errorCode, 'PLAYBACK_EXHAUSTED');
    assert.equal(player.currentTrack.playbackOutcome.status, 'exhausted');
    assert.ok(player.errorText.includes('完整版'));
  }
  configure({ netease: 'full', tencent: 'full', kugou: 'full' }, { netease: 700, tencent: 700, kugou: 700 });
  await click();
  assert.equal(player.errorCode, 'PLAYBACK_TIMEOUT');
  assert.ok(player.currentTrack.playbackOutcome.remainingBudgetMs > 80);
  gateway.controls.calls.length = 0;
  const stale = online.playSong(context, song, true);
  await until(() => gateway.controls.calls.some(url => url.pathname === '/song/url/v1'));
  const local = { id: 77, path: 'music/local.mp3', title: '新本地曲', artist: '', album: '', durationMs: 90000,
    coverPath: '', importedAt: 1, missing: false, neteaseId: 0 };
  await queue.playFromList([local], 0, context);
  await stale; await delay(400);
  assert.equal(player.currentTrack.id, 77);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(queue.currentId, 77);
  assert.ok(queueId < 0);
  // T08: the same actual ArkTS row click consumes Bilibili outcomes and retains
  // candidates on failure; only provider replies and Kit playback are controlled.
  gateway.orchestrator.setSourceEnabled('bilibili', true);
  configure({});
  const ordinaryResponse = gateway.controls.thirdPartyResponse;
  let biliFull = false;
  gateway.controls.thirdPartyResponse = url => {
    if (url.pathname === '/x/web-interface/nav') return json({ code: -101, data: { wbi_img: {
      img_url: 'https://i.test/' + 'a'.repeat(32) + '.png', sub_url: 'https://i.test/' + 'b'.repeat(32) + '.png' } } });
    if (url.pathname.endsWith('/search/type')) return json({ code: 0, data: { result: [{ bvid: 'BV1GJ411x7h7', title: '目录歌曲', author: '上传者' }] } });
    if (url.pathname === '/x/web-interface/view') return json({ code: 0, data: { bvid: 'BV1GJ411x7h7', title: '目录歌曲',
      desc: '歌名：目录歌曲\n歌手：原歌手\n专辑：目录专辑\n音频：原专辑音轨\nhttps://music.163.com/song?id=123',
      owner: { mid: 9, name: '上传者' }, pages: [{ cid: 222, page: 2, part: '目录歌曲', duration: 90 }] } });
    if (url.pathname === '/x/player/playurl') return json({ code: 0, data: { cid: 222, timelength: 90000,
      ...(biliFull ? { isPreview: false } : {}), dash: { duration: 90,
        audio: [{ baseUrl: 'https://audio.test/bili.m4a', mimeType: 'audio/mp4', codecs: 'mp4a.40.2' }] } } });
    return ordinaryResponse(url);
  };
  await click();
  assert.equal(player.errorCode, 'PLAYBACK_EXHAUSTED');
  const candidate = player.currentTrack.playbackOutcome.bilibili.candidates.find(candidate => candidate.resource?.cid === '222');
  assert.equal(candidate.reason, 'audio_unknown');
  assert.equal(candidate.status, 'manual');
  assert.equal(candidate.resource.uploader.name, '上传者');
  biliFull = true; await click();
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack.playbackSource, 'bilibili');
  assert.equal(player.playbackSourceText, 'Bilibili');
  assert.equal(player.currentTrack.title, song.name);
  assert.equal(player.currentTrack.artist, song.artist);
  assert.equal(player.currentTrack.catalogRef, song.catalogRef);
  assert.equal(player.currentTrack.lyricsRef, song.lyricsRef);
  assert.equal(identity.canDownloadNetEase(player.currentTrack), false);
  assert.equal(downloads.length, 0);
  gateway.controls.beforeResponse = (url, signal) => url.pathname === '/x/player/playurl'
    ? new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(new Error('cancelled')), { once: true })) : Promise.resolve();
  gateway.controls.calls.length = 0;
  const oldBili = online.playSong(context, song, true);
  await until(() => gateway.controls.calls.some(url => url.pathname === '/x/player/playurl'));
  await queue.playFromList([local], 0, context); await oldBili; await delay(80);
  assert.equal(player.currentTrack.id, 77);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(downloads.length, 0);
  gateway.orchestrator.setSourceEnabled('bilibili', false);
  configure({ netease: 'full' });
  await click(); await until(() => downloads.length === 1);
  assert.equal(player.currentTrack.playbackSource, 'api-enhanced');
  assert.equal(identity.canDownloadNetEase(player.currentTrack), true);
  gateway.orchestrator.searchSessions.clear(); await click();
  assert.equal(player.errorCode, 'INVALID_SEARCH_SESSION');
  console.log('PASS actual HTTP → actual ArkTS merged-row click, music/Bilibili full-only automatic fallback, retained manual candidates, source label, total/stage budget, switch cancellation including Bilibili, stale rejection, catalog/cover/lyrics/download isolation and original NetEase regression. Kit playback is controlled, not device decoding.');
} finally { await gateway.close(); }
