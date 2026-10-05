// Actual ArkTS API/search click/queue/player → actual authenticated gateway/SQLite/adapters.
// Only third-party HTTP, HarmonyOS Kit and client persistence/download are controlled.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { sourceSelectionHarness } from './compiled-source-selection.mjs';
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
  configure({ netease: 'full', tencent: 'full', kugou: 'full' });
  vm.keyword = '目录'; await vm.search(context);
  const group = vm.groups[0], song = vm.groupSong(group);
  const qq = group.entries.find(song => song.source === 'meting-tencent');
  const kugou = group.entries.find(song => song.source === 'meting-kugou');
  const { searchSourceName } = load('viewmodel/OnlineSearchViewModel.ets', ['searchSourceName'], { NetEaseApi, ApiError, networkViewModel: network });
  const ui = sourceSelectionHarness(player, PlayerState, searchSourceName);
  const records = [];
  const record = label => records.push({ step: label, state: player.state, queueId: queue.currentId,
    catalogRef: player.currentTrack?.catalogRef, manualPlaybackRef: player.currentTrack?.manualPlaybackRef,
    actualSource: player.playbackSourceText, integrity: player.currentTrack?.audioIntegrity?.status,
    controls: ui.snapshot() });
  async function clickSearch() {
    panel.playEntry(group, song, true);
    await until(() => panel.busyId === -1 && panel.busyRef === '');
  }
  configure({ netease: 'unavailable', tencent: 'unknown', kugou: 'preview' });
  await clickSearch();
  assert.equal(player.state, PlayerState.ERROR);
  const track = player.currentTrack, queueId = track.id;
  const stable = { title: track.title, artist: track.artist, album: track.album, cover: track.streamCoverUrl,
    catalogRef: track.catalogRef, lyricsRef: track.lyricsRef, mediaRef: track.mediaRef, neteaseId: track.neteaseId };
  ui.click('选择同录音来源'); record('failure source expansion');
  configure({ netease: 'unavailable', tencent: 'full', kugou: 'full' });
  ui.click(searchSourceName(qq.source));
  assert.equal(player.state, PlayerState.PREPARING);
  assert.ok(ui.render().filter(c => c.kind === 'Button' && c.text.includes(searchSourceName(qq.source))).every(c => !c.enabled));
  await until(() => player.state !== PlayerState.PREPARING);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack, track);
  assert.equal(queue.currentId, queueId);
  assert.equal(queue.queueTracks[0].id, queueId);
  assert.equal(player.currentTrack.manualPlaybackRef, qq.mediaRef);
  assert.equal(player.playbackSourceText, '腾讯 / QQ');
  assert.deepEqual({ title: track.title, artist: track.artist, album: track.album, cover: track.streamCoverUrl,
    catalogRef: track.catalogRef, lyricsRef: track.lyricsRef, mediaRef: track.mediaRef, neteaseId: track.neteaseId }, stable);
  assert.equal(downloads.length, 0);
  assert.equal(requests.at(-1).searchParams.get('manual'), 'true');
  assert.equal(requests.at(-1).searchParams.get('automatic'), null);
  assert.equal(requests.at(-1).searchParams.get('catalogRef'), song.catalogRef);
  assert.ok(gateway.controls.calls.every(url => url.searchParams.get('server') === 'tencent'));
  record('manual QQ success, original catalog retained');
  for (const status of ['preview', 'unknown', 'unavailable']) {
    configure({ netease: 'full', tencent: status, kugou: 'full' });
    player.failRequest(player.requestId, 'MEDIA_READ_FAILED'); await player.retry();
    assert.equal(player.state, PlayerState.ERROR);
    assert.equal(player.currentTrack.manualPlaybackRef, qq.mediaRef);
    assert.equal(player.currentTrack.audioIntegrity.status, status);
    assert.equal(player.playbackSourceText, '');
    assert.ok(ui.render().some(c => c.text === '重试所选来源'));
    assert.ok(!ui.render().some(c => c.text.includes('正在使用')));
    assert.ok(gateway.controls.calls.every(url => url.searchParams.get('server') === 'tencent'));
    record('manual QQ ' + status + ' rejected; retry available');
  }
  configure({ netease: 'full', tencent: 'full', kugou: 'full' });
  ui.click('重试所选来源'); await until(() => player.state !== PlayerState.PREPARING);
  assert.equal(player.playbackSourceText, '腾讯 / QQ');
  configure({ kugou: 'full' });
  ui.click(searchSourceName(kugou.source)); await until(() => player.state !== PlayerState.PREPARING);
  assert.equal(player.currentTrack.manualPlaybackRef, kugou.mediaRef);
  assert.equal(player.playbackSourceText, searchSourceName(kugou.source));
  assert.equal(player.currentTrack.id, queueId);
  record('reselect Kugou without new queue identity');
  // A cached/library entry retains the SQLite/favorite ID even when it now streams QQ.
  const cached = { ...track, id: 42, streamUrl: '', manualPlaybackRef: undefined, path: 'music/cached.mp3',
    playbackRef: track.catalogRef, playbackSource: 'api-enhanced' };
  await queue.playFromList([cached], 0, context);
  configure({ tencent: 'full' }); await player.selectSource(qq.mediaRef);
  assert.equal(player.currentTrack.id, 42);
  assert.equal(queue.currentId, 42);
  assert.equal(player.currentTrack.path, 'music/cached.mp3');
  assert.equal(player.currentTrack.catalogRef, stable.catalogRef);
  assert.equal(player.currentTrack.title, stable.title);
  assert.equal(downloads.length, 0);
  record('cached entry retains SQLite and favorite identity while streaming QQ');
  // Same queued recording appears twice: changing one selection cannot affect its neighbor.
  const other = identity.createOnlineTrack(song);
  other.sourceSearchSession = song.automaticSearchSession; other.sourceOptions = group.entries.slice();
  await queue.playFromList([track, other], 0, context);
  configure({ tencent: 'full', kugou: 'full' });
  await player.selectSource(qq.mediaRef);
  assert.equal(other.manualPlaybackRef, undefined);
  await queue.playNext();
  assert.equal(player.currentTrack.id, other.id);
  assert.equal(other.manualPlaybackRef, undefined);
  assert.ok(ui.render().some(c => c.text === '选择同录音来源'), 'expansion does not leak to a different queue entry');
  await queue.playPrev();
  assert.equal(player.currentTrack.manualPlaybackRef, qq.mediaRef);
  // New search playback creates a fresh selection and returns to automatic dispatch.
  configure({ netease: 'unavailable', tencent: 'full', kugou: 'full' });
  await clickSearch();
  assert.notEqual(player.currentTrack.id, queueId);
  assert.equal(player.currentTrack.manualPlaybackRef, undefined);
  assert.equal(requests.at(-1).searchParams.get('automatic'), 'true');
  record('fresh search does not inherit manual source');
  // Slow manual resolution is cancelled on switch, and cannot revise a later local track.
  configure({ tencent: 'full' }, { tencent: 600 });
  gateway.controls.calls.length = 0;
  const stale = player.selectSource(qq.mediaRef);
  await until(() => gateway.controls.calls.some(url => url.searchParams.get('type') === 'url'));
  const local = { id: 77, path: 'music/local.mp3', title: '本地曲', artist: '', album: '', durationMs: 90000,
    coverPath: '', importedAt: 1, missing: false, neteaseId: 0 };
  await queue.playFromList([local], 0, context); await stale; await delay(650);
  assert.equal(player.currentTrack.id, 77); assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(ui.render().length, 0);
  assert.equal(downloads.length, 0);
  record('local switch cancels stale manual resolution');
  if (process.argv.includes('--record')) writeFileSync(new URL('../docs/research/assets/issue28-client-interactions.json', import.meta.url),
    JSON.stringify({ boundary: 'Hvigor compiled SourceSelection controls → actual ArkTS VM/API/queue → actual authenticated HTTP gateway; ArkUI renderer, Kit media and provider responses controlled; not native layout/touch or real audio', records }, null, 2) + '\n');
  console.log('PASS compiled source-choice controls → actual ArkTS → real HTTP; full-only selected-source playback, stable identity, failures/retry/reselect, duplicate queue isolation, fresh search, cancellation and local playback. Native rendering/decoding remain unverified.');
} finally { await gateway.close(); }
