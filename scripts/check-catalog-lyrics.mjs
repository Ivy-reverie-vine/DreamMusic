// Node 24+: actual ArkTS API/queue/player/lyrics → authenticated HTTP gateway.
// Third-party HTTP, Kit audio/network primitives and client persistence are controlled.
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
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate) {
  const deadline = Date.now() + 5000;
  while (!predicate()) { assert.ok(Date.now() < deadline, 'client state did not settle'); await delay(10); }
}
const json = body => new Response(JSON.stringify(body));
const gateway = await startIdentityGateway({ lrclib: true });
const lrclib = gateway.orchestrator.lrclib;
gateway.orchestrator.lrclib = null; // Original T11 provider isolation, then enable T12 below.
try {
  const requests = [], sessions = [];
  const hilog = { error() {}, debug() {} };
  const { normalizeBaseUrl } = load('service/network/HealthStateMachine.ets', ['normalizeBaseUrl']);
  const { ApiClient, ApiError } = load('service/network/ApiClient.ets', ['ApiClient', 'ApiError'], {
    normalizeBaseUrl, hilog,
    http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 }, createHttp: () => {
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
  const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
  const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
  const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
  const identity = load('model/OnlineTrackIdentity.ets', ['createOnlineTrack', 'canDownloadNetEase']);
  class Session {
    constructor() { sessions.push(this); }
    async release() { this.isLoaded = false; }
    async playUrl(url, cb) { this.url = url; this.isLoaded = true; this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING); }
    async playFile(url, cb) { await this.playUrl(url, cb); }
    setVolume() {} getDuration() { return 90000; } seekTo() {}
  }
  const background = { sync() {}, startLongTask() {}, stopLongTask() {} };
  const deps = { ...identity, PlayerSession: Session, SleepTimer, PlayerState, PlayMode, ApiError, NetEaseApi, hilog,
    fileIo: { accessSync: () => true }, LibraryStore: { getInstance: () => ({ async savePlayerState() {}, async insertHistory() {} }) },
    BackgroundPlayback: { getInstance: () => background } };
  const { playerViewModel: player } = load('viewmodel/PlayerViewModel.ets', ['playerViewModel'], deps);
  const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
    ...deps, QueueEngine, playerViewModel: player, setInterval() {},
  });
  const queue = new QueueViewModel();
  const parser = load('service/lyrics/LrcParser.ets', ['parseLrc', 'parseYrc', 'findActiveLine']);
  const { lyricsViewModel: lyrics, LyricsLoadState: state } = load('viewmodel/LyricsViewModel.ets', ['lyricsViewModel', 'LyricsLoadState'], {
    ...parser, playerViewModel: player, NetEaseApi, LrcLoader: { loadForTrack: () => null },
  });
  const context = { filesDir: '/sandbox' };
  lyrics.setContext(context);
  // Execute Hvigor's compiled LyricWindow and follow methods with ArkUI primitives controlled.
  // This checks production display decisions, not native layout/touch/animation.
  const compiledPath = '../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/NowPlayingPage.ts';
  const compiled = readFileSync(new URL(compiledPath, import.meta.url), 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
  let texts = [], currentText, renderingItem = false, scrolls = 0;
  class Property { constructor(value) { this.value = value; } get() { return this.value; } set(value) { this.value = value; } }
  class ViewPU {
    finalizeConstruction() {} declareWatch() {}
    observeComponentCreation2(callback) { callback(0, true); }
    ifElseBranchUpdateFunction(_branch, callback) { callback(); }
    forEachUpdateFunction(_id, items, callback) { items.forEach(callback); }
  }
  const node = kind => new Proxy({}, { get(_target, key) {
    if (key === 'create') return value => {
      if (kind === 'Text') { currentText = { text: value }; texts.push(currentText); }
      if (kind === 'ListItem' && !renderingItem) { renderingItem = true; value(0, true); renderingItem = false; }
    };
    if (key === 'pop') return () => {};
    return value => { if (kind === 'Text') currentText[key] = value; };
  } });
  const { LyricFollowState } = load('service/lyrics/LyricFollowState.ets', ['LyricFollowState']);
  const { NowPlayingPage } = runInNewContext(`${stripTypeScriptTypes(compiled, { mode: 'transform' })}\n({NowPlayingPage})`, {
    ViewPU, Reflect, ObservedPropertyObjectPU: Property, ObservedPropertySimplePU: Property,
    ThemeService: { getInstance: () => ({ muted: 'muted', primaryText: 'active' }) },
    playerViewModel: player, lyricsViewModel: lyrics, playbackControlGate: {}, LyricsLoadState: state,
    LyricFollowState, findActiveLine: parser.findActiveLine,
    Scroller: class { scrollToIndex() { scrolls++; } },
    If: node('If'), Text: node('Text'), List: node('List'), ForEach: node('ForEach'), ListItem: node('ListItem'), Button: node('Button'),
    Color: { Transparent: 'transparent' },
    ViewStackProcessor: { StartGetAccessRecordingFor() {}, StopGetAccessRecording() {} },
    TextAlign: { Center: 0 }, FontWeight: { Medium: 'medium', Normal: 'normal' }, BarState: { Off: 0 },
    NestedScrollMode: { SELF_FIRST: 0 }, FONT_LABEL: 12, clearTimeout,
  });
  const ui = new NowPlayingPage(null, {});
  const render = () => { texts = []; ui.LyricWindow(); return texts; };
  // Real automatic resolution: NetEase catalog, confirmed full QQ audio.
  gateway.controls.thirdPartyResponse = url => {
    if (url.searchParams.get('type') === 'search') return json([{ id: 'qq-001', name: gateway.song.name,
      artist: ['原歌手'], album: '目录专辑', duration: 90 }]);
    if (url.pathname === '/song/url/v1') return json({ code: 200, data: [{ id: 123, url: '' }] });
    return null;
  };
  const search = (await gateway.request('/dreammusic/api/v2/search?aggregate=true&merge=true&keywords=目录',
    { headers: { 'X-API-Key': gateway.apiKey } })).body;
  const catalog = search.groups[0].entries.find(song => song.source === 'api-enhanced');
  const audio = await NetEaseApi.resolvePlayback(context, catalog.legacyId, catalog.mediaRef, search.searchSession);
  assert.equal(audio.playbackSource, 'meting-tencent');
  const original = identity.createOnlineTrack({ id: 123, name: catalog.title, artist: catalog.artists[0], album: '',
    coverUrl: '', durationMs: 90000, source: catalog.source, mediaRef: catalog.mediaRef, ...audio });
  original.streamUrl = audio.url;
  // A queue retry can start catalog lyrics before discovering a different audio source.
  // Run real resolution again and observe the old trusted timeline being withdrawn.
  for (const id of ['meting-tencent', 'meting-kugou']) gateway.orchestrator.registry.get(id).adapter.clearCache();
  gateway.controls.beforeResponse = url => url.searchParams.get('type') === 'url' ? delay(100) : Promise.resolve();
  const unresolved = { ...original, playbackRef: catalog.mediaRef, automaticSearchSession: search.searchSession };
  const resolving = queue.playFromList([unresolved], 0, context);
  await until(() => lyrics.loadState === state.READY);
  assert.equal(lyrics.timelineTrusted, true);
  await resolving;
  await until(() => lyrics.loadState === state.STATIC);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(lyrics.timelineTrusted, false);
  gateway.controls.beforeResponse = async () => {};
  // Use the queue's normal prepared-resolution boundary (also used by online clicks).
  const play = track => queue.playFromList([track], 0, context, -1, { ...audio,
    catalogRef: track.catalogRef, playbackRef: track.playbackRef, lyricsRef: track.catalogRef,
    playback: undefined });
  await play(original);
  await until(() => lyrics.loadState === state.STATIC);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(player.currentTrack.title, catalog.title);
  assert.equal(lyrics.lyricsSource, 'api-enhanced');
  assert.equal(lyrics.lines[0].text, '目录歌词');
  assert.equal(lyrics.timelineTrusted, false);
  assert.ok(render().some(text => text.text === '歌词时间轴未确认，静态显示'));
  assert.equal(render().find(text => text.text === '目录歌词').fontWeight, 'normal');
  ui.followActiveLine(); assert.equal(scrolls, 0);
  player.positionTickHandler(5000);
  assert.equal(lyrics.activeIndex, -1);
  const request = requests.findLast(url => url.pathname.endsWith('/lyric/new'));
  assert.equal(request.searchParams.get('catalogRef'), catalog.mediaRef);
  assert.equal(request.searchParams.get('playbackRef'), audio.playbackRef);
  assert.equal(gateway.controls.calls.findLast(url => url.pathname === '/lyric/new').searchParams.get('id'), '123');

  // Same original resource is timed; return to QQ must not reuse its cached timing.
  gateway.controls.thirdPartyResponse = () => null;
  const same = { ...original, playbackRef: catalog.mediaRef, playbackSource: 'api-enhanced', streamUrl: 'https://audio.test/original' };
  await play(same);
  await until(() => lyrics.loadState === state.READY);
  player.positionTickHandler(5000);
  assert.equal(lyrics.activeIndex, 0);
  player.positionMs = 5000;
  assert.equal(render().find(text => text.text === '目录歌词').fontWeight, 'medium');
  await play(original);
  await until(() => lyrics.loadState === state.STATIC);
  assert.equal(lyrics.activeIndex, -1);
  assert.equal(lyrics.timelineTrusted, false);

  let sequence = 200;
  function entry(source = 'api-enhanced') {
    const catalogRef = createMediaRef({ source, sourceId: String(sequence++) });
    return { ...original, id: -sequence, mediaRef: catalogRef, catalogRef, lyricsRef: catalogRef };
  }
  for (const [payload, expected] of [
    [{ code: 200, lrc: { lyric: '没有时间轴\n仍然可读' } }, state.STATIC],
    [{ code: 200, lrc: { lyric: '' } }, state.EMPTY],
    [{ code: 200, nolyric: true }, state.INSTRUMENTAL],
    [{ code: 503 }, state.ERROR],
  ]) {
    gateway.controls.thirdPartyResponse = url => url.pathname === '/lyric/new' ? json(payload) : null;
    await play(entry());
    await until(() => lyrics.loadState === expected);
    assert.equal(player.state, PlayerState.PLAYING);
    assert.equal(lyrics.activeIndex, -1);
    if (expected === state.STATIC) assert.equal(lyrics.lines[0].text, '没有时间轴');
    const hints = { [state.EMPTY]: '这首歌暂无歌词', [state.INSTRUMENTAL]: '纯音乐，无歌词',
      [state.ERROR]: '歌词暂时无法加载' };
    if (hints[expected]) assert.ok(render().some(text => text.text === hints[expected]));
  }
  await play(entry('meting-kugou'));
  await until(() => lyrics.loadState === state.UNSUPPORTED);
  assert.ok(render().some(text => text.text === '原平台未提供歌词'));
  assert.equal(player.state, PlayerState.PLAYING);
  gateway.orchestrator.registry.get('api-enhanced').timeoutMs = 50;
  gateway.controls.beforeResponse = url => url.pathname === '/lyric/new' ? delay(130) : Promise.resolve();
  await play(entry());
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(lyrics.loadState, state.LOADING);
  await until(() => lyrics.loadState === state.TIMEOUT);
  assert.ok(render().some(text => text.text === '歌词请求超时'));
  assert.equal(player.state, PlayerState.PLAYING);
  await delay(150);

  // Switching during a slow lyric request aborts the HTTP/provider and clears the display.
  gateway.orchestrator.registry.get('api-enhanced').timeoutMs = 1000;
  let started, release, cancelled = 0;
  const began = new Promise(resolve => { started = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  gateway.controls.thirdPartyResponse = url => url.pathname === '/lyric/new' ? json({ code: 200, lrc: { lyric: '[00:00]迟到旧词' } }) : null;
  gateway.controls.beforeResponse = async (url, signal) => {
    if (url.pathname !== '/lyric/new') return;
    started(); signal.addEventListener('abort', () => { cancelled++; }, { once: true });
    await gate; // Deliberately ignores abort to prove late success cannot overwrite a new song.
  };
  await play(entry());
  await began;
  const local = { id: 7, path: 'local.mp3', title: '新本地曲', artist: '', album: '', durationMs: 90000,
    coverPath: '', importedAt: 0, missing: false, neteaseId: 0 };
  await queue.playFromList([local], 0, context);
  await until(() => cancelled === 1);
  release(); await delay(50);
  assert.equal(player.currentTrack, local);
  assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(lyrics.lines.length, 0);
  assert.equal(lyrics.activeIndex, -1);
  assert.equal(lyrics.lyricsRef, '');
  assert.equal(lyrics.timelineTrusted, false);
  assert.equal(render().some(text => text.text === '迟到旧词'), false);
  assert.equal(gateway.orchestrator.registry.get('api-enhanced').inFlight, 0);
  // T12: real gateway fallback into production ArkTS parser/display/cache/retry.
  gateway.orchestrator.lrclib = lrclib;
  gateway.controls.beforeResponse = async () => {};
  const lrclibRow = extra => ({ id: 42, trackName: gateway.song.name, artistName: '原歌手', albumName: '目录专辑',
    duration: 90, plainLyrics: '第一句\n第二句', syncedLyrics: '[00:01]第一句\n[00:02]第二句', ...extra });
  for (const [extra, expected] of [[{}, state.READY], [{ syncedLyrics: null }, state.STATIC],
    [{ instrumental: true, plainLyrics: null, syncedLyrics: null }, state.INSTRUMENTAL]]) {
    lrclib.cache.clear();
    gateway.controls.thirdPartyResponse = url => url.pathname === '/lyric/new' ? json({ code: 200 })
      : url.hostname === 'lrclib.net' ? json(lrclibRow(extra)) : null;
    const track = entry(); track.playbackRef = track.catalogRef;
    await play(track); await until(() => lyrics.loadState === expected);
    assert.equal(lyrics.lyricsSource, 'lrclib');
    assert.ok(render().some(text => text.text === '歌词来源：LRCLIB'));
    assert.equal(player.state, PlayerState.PLAYING);
    player.positionMs = 5000; player.positionTickHandler(5000);
    if (expected === state.READY) {
      assert.equal(lyrics.activeIndex, 1);
      assert.equal(render().find(text => text.text === '第二句').fontWeight, 'medium');
    } else assert.equal(lyrics.activeIndex, -1);
  }
  // Same cached lyric provider text becomes static for an unknown MV relation.
  lrclib.cache.clear();
  gateway.controls.thirdPartyResponse = url => url.pathname === '/lyric/new' ? json({ code: 200 })
    : url.hostname === 'lrclib.net' ? json(lrclibRow({})) : null;
  await play(entry()); await until(() => lyrics.loadState === state.STATIC);
  assert.equal(lyrics.timelineTrusted, false);
  ui.followActiveLine();
  for (const failure of ['missing', 'failed', 'timeout']) {
    lrclib.cache.clear(); lrclib.timeoutMs = 60;
    gateway.controls.beforeResponse = url => failure === 'timeout' && url.hostname === 'lrclib.net' ? delay(140) : Promise.resolve();
    gateway.controls.thirdPartyResponse = url => url.pathname === '/lyric/new' ? json({ code: 200 })
      : url.hostname === 'lrclib.net' ? failure === 'missing'
        ? url.pathname === '/api/get' ? new Response('{}', { status: 404 }) : json([])
        : failure === 'failed' ? new Response('{}', { status: 503 }) : json(lrclibRow({})) : null;
    const track = entry(); track.playbackRef = track.catalogRef;
    await play(track);
    await until(() => lyrics.loadState === (failure === 'missing' ? state.EMPTY : failure === 'failed' ? state.ERROR : state.TIMEOUT));
    assert.equal(player.state, PlayerState.PLAYING);
    assert.equal(lyrics.retryable, failure !== 'missing');
    render();
    if (failure !== 'missing') {
      gateway.controls.beforeResponse = async () => {};
      gateway.controls.thirdPartyResponse = url => url.pathname === '/lyric/new' ? json({ code: 200 })
        : url.hostname === 'lrclib.net' ? json(lrclibRow({})) : null;
      lyrics.retry(); await until(() => lyrics.loadState === state.READY);
      assert.equal(lyrics.retryable, false);
      assert.equal(player.state, PlayerState.PLAYING);
    }
    await delay(150);
  }
  // Switch tracks while LRCLIB ignores cancellation: neither display nor cache accepts late success.
  lrclib.cache.clear(); lrclib.timeoutMs = 1000;
  let lrStarted, lrRelease, lrAborted = false;
  const lrBegan = new Promise(resolve => { lrStarted = resolve; });
  const lrGate = new Promise(resolve => { lrRelease = resolve; });
  gateway.controls.beforeResponse = async (url, signal) => {
    if (url.hostname !== 'lrclib.net') return;
    lrStarted(); signal.addEventListener('abort', () => { lrAborted = true; }, { once: true }); await lrGate;
  };
  await play(entry()); await lrBegan;
  await queue.playFromList([local], 0, context);
  await until(() => lrAborted); lrRelease(); await delay(50);
  assert.equal(player.currentTrack, local); assert.equal(lyrics.lines.length, 0);
  assert.equal(lrclib.cache.size, 0); assert.equal(player.state, PlayerState.PLAYING);
  console.log('PASS T12: actual HTTP LRCLIB fallback → compiled lyric display; synced/static/instrumental/missing/failure/timeout, retry, cache timing and late cancellation.');
  console.log('PASS T11: real HTTP automatic audio fallback + catalog lyrics → real ArkTS queue/player/lyrics; static/trusted/cache relations, plain text, empty, instrumental, unsupported, timeout, failure and cancellation. Audio keeps PLAYING; Kit boundaries controlled, no device claim.');
} finally { await gateway.close(); }
