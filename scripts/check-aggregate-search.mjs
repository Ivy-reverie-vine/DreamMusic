// Node 24+: real ArkTS search/component methods → real HTTP/auth/SQLite/registry/adapters.
// Only HarmonyOS Kit, client persistence/download, and third-party HTTP are controlled.
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
    assert.ok(match, `Missing component method: ${name}`);
    const start = match.index + 3, brace = source.indexOf('{', start);
    let depth = 1, end = brace + 1;
    while (depth && end < source.length) {
      if (source[end] === '{') depth++;
      if (source[end] === '}') depth--;
      end++;
    }
    return source.slice(start, end).replace(/^private /, '');
  });
  return runInNewContext(stripTypeScriptTypes(`class OnlineSearchView { ${bodies.join('\n')} }\nnew OnlineSearchView()`,
    { mode: 'transform' }), deps);
}
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
async function until(predicate) {
  const end = Date.now() + 5000;
  while (!predicate()) { assert.ok(Date.now() < end, 'public client state did not settle'); await new Promise(r => setTimeout(r, 10)); }
}
const gateway = await startIdentityGateway();
try {
  const requests = [], downloads = [];
  const network = { markOnline() {}, markOffline() {} };
  let disconnect = false, legacyGateway = false;
  const { normalizeBaseUrl } = load('service/network/HealthStateMachine.ets', ['normalizeBaseUrl']);
  const { ApiClient, ApiError } = load('service/network/ApiClient.ets', ['ApiClient', 'ApiError'], {
    normalizeBaseUrl, hilog: { debug() {} },
    http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 }, createHttp: () => ({
      async request(url, options) {
        requests.push(new URL(url));
        if (disconnect) throw new Error('connection lost');
        const target = new URL(url);
        if (legacyGateway) target.searchParams.delete('aggregate');
        const response = await fetch(target, { method: options.method, headers: options.header });
        return { responseCode: response.status, result: await response.text(), header: Object.fromEntries(response.headers) };
      }, destroy() {},
    }) },
  });
  const { NetEaseApi } = load('service/network/NetEaseApi.ets', ['NetEaseApi'], {
    ApiClient, ApiError, DreamMusicAuth: {
      base: async () => gateway.base + '/dreammusic/api/v1', baseV2: async () => gateway.base + '/dreammusic/api/v2',
      username: () => 'identity-user', withApiKey: (_ctx, call) => call({ 'X-API-Key': gateway.apiKey }),
    }, playbackDiagnostics: { record() {} }, classifyPlaybackError: () => 'failure',
    DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL: 'empty', DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT: 'timeout',
  });
  const { OnlineSearchViewModel, searchSourceName } = load('viewmodel/OnlineSearchViewModel.ets',
    ['OnlineSearchViewModel', 'searchSourceName'], { NetEaseApi, ApiError, networkViewModel: network });
  const identity = load('model/OnlineTrackIdentity.ets', ['createOnlineTrack', 'canDownloadNetEase']);
  const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
  const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
  const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
  class Session {
    async release() { this.isLoaded = false; }
    async playUrl(url, cb) { this.url = url; this.isLoaded = true; this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING); }
    setVolume() {} getDuration() { return 90000; } seekTo() {}
  }
  const deps = { ...identity, PlayerState, PlayMode, SleepTimer, ApiError, NetEaseApi, PlayerSession: Session,
    fileIo: { accessSync: () => true }, hilog: { error() {} },
    LibraryStore: { getInstance: () => ({ async savePlayerState() {}, async insertHistory() {} }) },
    BackgroundPlayback: { getInstance: () => ({ sync() {}, startLongTask() {}, stopLongTask() {} }) } };
  const { playerViewModel: player } = load('viewmodel/PlayerViewModel.ets', ['playerViewModel'], deps);
  const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
    ...deps, playerViewModel: player, QueueEngine, setInterval() {},
  });
  const queue = new QueueViewModel();
  const { onlineMusicViewModel: online } = load('viewmodel/OnlineMusicViewModel.ets', ['onlineMusicViewModel'], {
    ...deps, playerViewModel: player, queueViewModel: queue,
    OnlineDownloadService: { async findLocal() { return null; }, async ensureLocal(_ctx, song) { downloads.push(song); } },
  });
  const vm = new OnlineSearchViewModel(), context = { filesDir: '/sandbox' };
  const panel = componentMethods(['onKeyword', 'aboutToDisappear', 'streamAndPlay', 'reportConnectivity'], {
    ApiError, playerViewModel: player, onlineMusicViewModel: online, networkViewModel: network,
  });
  Object.assign(panel, { search: vm, ctx: () => context, errorText: '', errorCode: '', busyId: -1, busyRef: '', progressText: '' });
  const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
  let qqFailed = true, mode = 'paged';
  gateway.controls.thirdPartyResponse = url => {
    const api = url.host === 'upstream.test';
    if (!(api ? url.pathname === '/search' : url.searchParams.get('type') === 'search')) return null;
    if (mode === 'failed') return json({ code: 503 }, 503);
    if (mode === 'empty') return json(api ? { code: 200, result: { songs: [], more: false } } : []);
    const kw = api ? url.searchParams.get('keywords') : url.searchParams.get('id');
    const offset = api ? Number(url.searchParams.get('offset')) : (Number(url.searchParams.get('page')) - 1) * 30;
    if (!api && url.searchParams.get('server') === 'tencent' && qqFailed) return json({ code: 429 }, 429);
    const entries = offset === 0 ? Array.from({ length: 30 }, (_, i) => i) : [0, offset];
    return json(api ? { code: 200, result: { songs: entries.map(i => ({ ...gateway.song, id: 100 + i, name: kw + i })), more: offset === 0 } }
      : entries.map(i => ({ id: 'entry-' + i, name: kw + i, artist: ['歌手'], duration: 90 })));
  };

  panel.onKeyword('第一页');
  await until(() => !vm.loading && vm.results.length > 0);
  assert.equal(vm.status, 'partial_failure');
  assert.equal(vm.results.length, 60);
  assert.equal(vm.sources.find(s => s.source === 'meting-tencent').nextOffset, 0);
  assert.equal(requests.length, 1, 'debounced search uses one aggregate HTTP request');
  assert.equal(gateway.controls.calls.length, 3, 'search must not resolve URLs/covers/lyrics');
  assert.deepEqual(Array.from(vm.sources, s => searchSourceName(s.source)), ['网易云', 'QQ音乐', '酷狗']);
  await vm.loadMore(context);
  assert.equal(vm.results.length, 62, 'overlapping pages are deduplicated per concrete reference');
  assert.deepEqual(JSON.parse(requests.at(-1).searchParams.get('pages')), { 'api-enhanced': 30, 'meting-kugou': 30 });
  assert.equal(vm.hasMore, false);
  qqFailed = false;
  await vm.retrySource(context, 'meting-tencent');
  assert.equal(vm.status, 'success');
  assert.equal(vm.results.length, 92);
  assert.deepEqual(JSON.parse(requests.at(-1).searchParams.get('pages')), { 'meting-tencent': 0 });
  const picked = vm.results.find(s => s.source === 'meting-tencent');
  await panel.streamAndPlay(picked);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack.catalogRef, picked.catalogRef);
  assert.equal(player.currentTrack.title, picked.name);
  assert.equal(downloads.length, 0, 'QQ audio never enters the NetEase download flow');
  const selectedId = queue.currentId;
  await vm.retry(context); // repeat the exact successful page; no repeated append or selection change.
  assert.equal(vm.results.length, 92);
  await vm.loadMore(context);
  assert.equal(vm.results.length, 93);
  assert.equal(queue.currentId, selectedId);
  assert.equal(player.currentTrack.catalogRef, picked.catalogRef);
  assert.equal(player.currentTrack.title, picked.name);

  // Entire HTTP request fails during a later page: preserve list and retry precisely that page.
  panel.onKeyword('传输重试'); await vm.search(context);
  const count = vm.results.length;
  disconnect = true;
  await vm.loadMore(context);
  const failedPages = requests.at(-1).searchParams.get('pages');
  assert.equal(vm.errorCode, 'NETWORK');
  assert.equal(vm.results.length, count);
  disconnect = false;
  await vm.retry(context);
  assert.equal(requests.at(-1).searchParams.get('pages'), failedPages);
  assert.equal(vm.errorText, '');

  for (const [value, expected] of [['empty', 'empty'], ['failed', 'all_failed']]) {
    mode = value;
    panel.onKeyword(value); await vm.search(context);
    assert.equal(vm.status, expected);
    assert.equal(vm.results.length, 0);
  }
  // Retry failed sources without clearing the business circuit.
  mode = 'paged';
  await vm.retrySource(context, 'meting-tencent');
  assert.equal(vm.status, 'partial_failure');
  assert.equal(vm.results.length, 30);

  // Change immediately invalidates old responses, including during the 300 ms debounce window.
  const oldGate = deferred(), allStarted = new Set();
  gateway.controls.beforeResponse = async url => {
    if (url.searchParams.get('keywords') === '旧词' || url.searchParams.get('id') === '旧词') {
      allStarted.add(url.host === 'upstream.test' ? 'api' : url.searchParams.get('server'));
      await oldGate.promise;
    }
  };
  panel.onKeyword('旧词'); const old = vm.search(context);
  await until(() => allStarted.size === 3);
  panel.onKeyword('新词');
  assert.equal(vm.results.length, 0);
  await vm.search(context);
  assert.ok(vm.results.length > 0 && vm.results.every(s => s.name.startsWith('新词')));
  oldGate.resolve(); await old;
  assert.ok(vm.results.every(s => s.name.startsWith('新词')));
  assert.equal(vm.loading, false);
  assert.equal(queue.currentId, selectedId);
  assert.equal(player.currentTrack.title, picked.name);

  // Closing/cancelling while HTTP is in flight cannot repopulate the page.
  const cancelGate = deferred(); let cancelStarted = false;
  gateway.controls.beforeResponse = async url => {
    if (url.searchParams.get('keywords') === '取消' || url.searchParams.get('id') === '取消') {
      cancelStarted = true; await cancelGate.promise;
    }
  };
  panel.onKeyword('取消'); const cancelled = vm.search(context);
  await until(() => cancelStarted);
  panel.aboutToDisappear();
  cancelGate.resolve(); await cancelled;
  assert.equal(vm.results.length, 0);
  assert.equal(vm.sources.length, 0);
  assert.equal(vm.loading, false);
  const beforeClear = requests.length;
  panel.onKeyword('马上清空'); panel.onKeyword('');
  await new Promise(r => setTimeout(r, 320));
  assert.equal(requests.length, beforeClear);
  assert.equal(queue.currentId, selectedId);
  gateway.controls.beforeResponse = async () => {};
  legacyGateway = true;
  panel.onKeyword('旧网关兼容'); await vm.search(context);
  assert.equal(vm.sources.length, 1);
  assert.equal(vm.sources[0].source, 'api-enhanced');
  assert.equal(vm.results.length, 30);
  await vm.loadMore(context);
  assert.equal(vm.results.length, 31);
  assert.equal(vm.hasMore, false);
  panel.aboutToDisappear();
  console.log('PASS: real HTTP aggregate + ArkTS search interaction, independent pages/retries/dedup, empty/all failed, debounce/stale/cancel and selected playback identity.');
} finally { await gateway.close(); }
