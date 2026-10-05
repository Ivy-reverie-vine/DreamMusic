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
const gateway = await startIdentityGateway({ bilibili: true, mediaProxy: true });
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
  const parser = load('service/lyrics/LrcParser.ets', ['findActiveLine', 'parseLrc', 'parseYrc']);
  const { LyricsViewModel, LyricsLoadState } = load('viewmodel/LyricsViewModel.ets', ['LyricsViewModel', 'LyricsLoadState'], {
    ...parser, NetEaseApi, playerViewModel: player, LrcLoader: { loadForTrack: () => null },
  });
  const lyrics = new LyricsViewModel(); lyrics.setContext(context);
  if (process.argv.includes('--live')) {
    const upstream = process.env.LIVE_NETEASE_UPSTREAM || 'http://127.0.0.1:30325';
    const events = [];
    for (const source of ['meting-tencent', 'meting-kugou']) gateway.orchestrator.setSourceEnabled(source, false);
    gateway.controls.thirdPartyResponse = async (url, init) => {
      const target = url.host === 'upstream.test' ? new URL(url.pathname + url.search, upstream) : url;
      const response = await fetch(target, { ...init, signal: init?.signal ? AbortSignal.any([init.signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000) });
      events.push({ host: url.host === 'upstream.test' ? 'netease-local' : url.host, path: url.pathname, httpStatus: response.status });
      return response;
    };
    vm.keyword = process.env.LIVE_MUSIC_KEYWORD || 'Never Gonna Give You Up Rick Astley'; await vm.search(context);
    const group = vm.groups.find(group => group.entries.some(song => song.id === Number(process.env.LIVE_MUSIC_ID || 18520488)));
    assert.ok(group, 'requested original catalog must be found in real search');
    const song = group.entries.find(song => song.id === Number(process.env.LIVE_MUSIC_ID || 18520488));
    const { searchSourceName } = load('viewmodel/OnlineSearchViewModel.ets', ['searchSourceName'], { NetEaseApi, ApiError, networkViewModel: network });
    const ui = sourceSelectionHarness(player, PlayerState, searchSourceName), records = [];
    const record = step => records.push({ step, state: player.state, queueId: queue.currentId,
      title: player.currentTrack?.title, artist: player.currentTrack?.artist,
      catalogRef: player.currentTrack?.catalogRef, originalCatalogRef: player.currentTrack?.otherRecordingOrigin,
      integrity: player.currentTrack?.audioIntegrity, errorCode: player.errorCode,
      lyricsState: lyrics.loadState, activeLyric: lyrics.activeIndex, controls: ui.snapshot() });
    panel.playEntry(group, song, true);
    const deadline = Date.now() + 30000;
    while (panel.busyId !== -1 || panel.busyRef !== '') { assert.ok(Date.now() < deadline, 'live automatic resolution did not settle'); await delay(20); }
    assert.equal(player.state, PlayerState.ERROR, 'sample must be automatically rejected');
    const original = player.currentTrack;
    const candidates = player.otherRecordingOptions;
    assert.ok(candidates.length > 0, 'real fallback must discover concrete manual candidates');
    const candidate = candidates[0];
    ui.click('查看其他录音候选'); record('real automatic rejection; discovered manual candidates');
    const audioRequests = events.filter(event => event.path === '/x/player/playurl').length;
    ui.click('选择候选：' + candidate.title);
    assert.equal(events.filter(event => event.path === '/x/player/playurl').length, audioRequests);
    record('real candidate selected; explicit confirmation pending');
    ui.click('确认播放此独立曲目');
    const manualDeadline = Date.now() + 20000;
    while (player.state === PlayerState.PREPARING) { assert.ok(Date.now() < manualDeadline, 'manual live resolution did not settle'); await delay(20); }
    assert.notEqual(player.currentTrack.id, original.id);
    assert.equal(player.currentTrack.neteaseId, 0);
    assert.equal(player.currentTrack.catalogRef, candidate.mediaRef);
    assert.equal(lyrics.lines.length, 0); assert.equal(lyrics.activeIndex, -1);
    assert.ok(events.filter(event => event.path === '/x/player/playurl').length > audioRequests);
    if (player.currentTrack.audioIntegrity.status !== 'full') assert.equal(player.state, PlayerState.ERROR);
    ui.click('查看其他录音候选'); record('confirmed real candidate resolved; production integrity gate preserved');
    const evidence = { date: '2026-10-05 Asia/Shanghai',
      boundary: 'Real NetEase/Bilibili HTTP → actual gateway → actual ArkTS API/player/queue/lyrics + compiled controls. Local disposable auth/SQLite, Kit media and ArkUI rendering controlled. No real decoding/device evidence.',
      catalog: { id: song.id, title: song.name, artist: song.artist },
      chosen: { title: candidate.title, resource: candidate.resource, reason: candidate.reason, match: candidate.match },
      records, events, audioDecoded: false };
    if (process.argv.includes('--record')) writeFileSync(new URL('../docs/research/assets/issue29-real-selection.json', import.meta.url), JSON.stringify(evidence, null, 2) + '\n');
    console.log(JSON.stringify({ original: song.name, candidate: candidate.title, reason: candidate.reason,
      actualIntegrity: player.currentTrack.audioIntegrity, state: player.state, errorCode: player.errorCode,
      identityChanged: player.currentTrack.catalogRef !== original.catalogRef, oldLyricsCleared: lyrics.lines.length === 0,
      realHttpRequests: events.length, audioDecoded: false }));
  } else {
  const bvid = 'BV1GJ411x7h7';
  let mode = 'full', waitMs = 0;
  const json = body => new Response(JSON.stringify(body), { headers: { 'Content-Type': 'application/json' } });
  for (const source of ['meting-tencent', 'meting-kugou']) gateway.orchestrator.setSourceEnabled(source, false);
  gateway.orchestrator.playbackBudget = { totalMs: 1500, reserveMs: 1000 };
  gateway.controls.beforeResponse = (url, signal) => waitMs && url.pathname === '/x/player/playurl'
    ? new Promise((resolve, reject) => { const timer = setTimeout(resolve, waitMs);
      signal.addEventListener('abort', () => { clearTimeout(timer); reject(new Error('cancelled')); }, { once: true }); })
    : Promise.resolve();
  gateway.controls.thirdPartyResponse = url => {
    if (url.pathname === '/song/url/v1') return json({ code: 200, data: [{ id: 123, url: '', time: 90000 }] });
    if (url.pathname === '/x/web-interface/nav') return json({ code: -101, data: { wbi_img: {
      img_url: 'https://i.test/' + 'a'.repeat(32) + '.png', sub_url: 'https://i.test/' + 'b'.repeat(32) + '.png' } } });
    if (url.pathname.endsWith('/search/type')) return json({ code: 0, data: { result: [{ bvid, title: '目录歌曲 MV 含对白' }] } });
    if (url.pathname === '/x/web-interface/view') return json({ code: 0, data: { bvid,
      title: '目录歌曲 MV 含对白', desc: '歌手：独立录音歌手\n含对白', pic: 'https://cover.test/mv.jpg',
      owner: { mid: 7, name: 'UP不是歌手' }, pages: [{ cid: 222, page: 2, part: '独立版本 MV', duration: 100 }] } });
    if (url.pathname === '/x/player/playurl') return mode === 'failure' ? json({ code: -404 }) : json({ code: 0, data: {
      cid: 222, timelength: mode === 'short' ? 30000 : 100000,
      ...(mode === 'unknown' ? {} : { isPreview: mode === 'preview' }),
      dash: { audio: [{ baseUrl: 'https://audio.test/mv.m4a', mimeType: 'audio/mp4', codecs: 'mp4a.40.2' }] } } });
    return null;
  };
  vm.keyword = '目录'; await vm.search(context);
  const group = vm.groups[0], song = vm.groupSong(group);
  const { searchSourceName } = load('viewmodel/OnlineSearchViewModel.ets', ['searchSourceName'], { NetEaseApi, ApiError, networkViewModel: network });
  const ui = sourceSelectionHarness(player, PlayerState, searchSourceName), records = [];
  const record = step => records.push({ step, state: player.state, queueId: queue.currentId,
    title: player.currentTrack?.title, artist: player.currentTrack?.artist, catalogRef: player.currentTrack?.catalogRef,
    originalCatalogRef: player.currentTrack?.otherRecordingOrigin, actualSource: player.playbackSourceText,
    integrity: player.currentTrack?.audioIntegrity?.status, lyricsState: lyrics.loadState,
    lyricsRef: lyrics.lyricsRef, activeLyric: lyrics.activeIndex, controls: ui.snapshot() });
  async function searchPlay() {
    panel.playEntry(group, song, true);
    await until(() => panel.busyId === -1 && panel.busyRef === '');
  }
  await searchPlay();
  await until(() => lyrics.loadState === LyricsLoadState.READY);
  assert.equal(player.state, PlayerState.ERROR);
  const original = player.currentTrack;
  const originalSnapshot = JSON.stringify({ id: original.id, title: original.title, neteaseId: original.neteaseId });
  assert.equal(player.otherRecordingOptions.length, 1);
  assert.ok(!gateway.controls.calls.some(url => url.pathname === '/x/player/playurl'));
  ui.click('查看其他录音候选');
  assert.ok(ui.render().some(control => control.text.includes('MV') && control.text.includes('对白')));
  record('automatic rejection, candidate and extra-segment reason visible');
  ui.click('选择候选：独立版本 MV');
  assert.ok(!gateway.controls.calls.some(url => url.pathname === '/x/player/playurl'));
  record('candidate chosen; awaiting explicit confirmation without audio requests');
  ui.click('取消选择');
  assert.ok(!ui.render().some(control => control.text === '确认播放此独立曲目'));
  ui.click('选择候选：独立版本 MV'); ui.click('确认播放此独立曲目');
  assert.equal(player.state, PlayerState.PREPARING);
  assert.equal(lyrics.lines.length, 0); assert.equal(lyrics.activeIndex, -1);
  assert.equal(lyrics.lyricsRef, ''); assert.equal(lyrics.loadState, LyricsLoadState.EMPTY);
  await until(() => player.state !== PlayerState.PREPARING);
  assert.equal(player.state, PlayerState.PLAYING);
  const independent = player.currentTrack;
  assert.notEqual(independent.id, original.id); assert.equal(queue.currentId, independent.id);
  assert.equal(queue.queueTracks[0], independent);
  assert.equal(independent.title, '独立版本 MV'); assert.equal(independent.artist, '独立录音歌手');
  assert.equal(independent.album, '目录歌曲 MV 含对白'); assert.equal(independent.durationMs, 100000);
  assert.equal(independent.streamCoverUrl, 'https://cover.test/mv.jpg');
  assert.equal(independent.neteaseId, 0); assert.equal(independent.lyricsRef, '');
  assert.equal(independent.catalogRef, independent.manualPlaybackRef);
  assert.equal(independent.manualCandidate.match.status, 'manual');
  assert.equal(independent.otherRecordingOrigin, original.catalogRef);
  assert.equal(identity.canDownloadNetEase(independent), false); assert.equal(downloads.length, 0);
  assert.equal(JSON.stringify({ id: original.id, title: original.title, neteaseId: original.neteaseId }), originalSnapshot);
  assert.equal(lyrics.lines.length, 0); assert.equal(lyrics.activeIndex, -1);
  assert.equal(requests.filter(url => url.searchParams.get('manual') === 'other').length, 1);
  ui.click('查看其他录音候选'); record('confirmed independent MV playing; own identity, no inherited synced lyrics');
  for (const value of ['preview', 'unknown', 'short', 'failure']) {
    mode = value; const count = sessions.length;
    player.failRequest(player.requestId, 'MEDIA_READ_FAILED'); await player.retry();
    assert.equal(player.state, PlayerState.ERROR);
    assert.equal(player.currentTrack, independent); assert.equal(queue.currentId, independent.id);
    assert.equal(player.currentTrack.audioIntegrity.status, value === 'unknown' ? 'unknown' : value === 'failure' ? 'unavailable' : 'preview');
    assert.equal(player.playbackSourceText, '');
    assert.ok(!sessions.slice(count).some(session => session.isPlaying));
    assert.equal(lyrics.lines.length, 0); assert.equal(lyrics.activeIndex, -1);
    record('manual ' + value + ' rejected without fallback or stale lyrics');
  }
  mode = 'full'; ui.click('重试所选候选'); await until(() => player.state !== PlayerState.PREPARING);
  assert.equal(player.state, PlayerState.PLAYING); record('retry same independent candidate');
  // Neighbouring entries remain unchanged; revisiting the selection stays manual.
  const neighbour = identity.createOnlineTrack(song);
  const local = { id: 77, path: 'music/local.mp3', title: '本地曲', artist: '', album: '', durationMs: 90000,
    coverPath: '', importedAt: 1, missing: false, neteaseId: 0 };
  // The same cached library track can occur twice; only the current occurrence changes.
  const cached = { ...original, id: 42, path: 'music/cached-original.mp3', streamUrl: '' };
  await queue.playFromList([cached, cached, local], 1, context);
  await player.selectOtherRecording(independent.mediaRef);
  assert.equal(queue.queueTracks[0], cached);
  assert.equal(queue.queueTracks[0].id, 42);
  assert.notEqual(queue.queueTracks[1].id, 42);
  assert.equal(queue.queueTracks[2], local);
  assert.equal(queue.currentIndexId(), 1);
  assert.equal(cached.title, original.title);
  assert.equal(player.currentTrack.neteaseId, 0);
  record('duplicate cached/favorite track: only current occurrence replaced; original library identity retained');
  await queue.playFromList([independent, neighbour, local], 0, context);
  await queue.playNext();
  assert.equal(neighbour.otherRecordingOrigin, undefined); assert.equal(neighbour.manualPlaybackRef, undefined);
  await queue.playPrev(); assert.equal(player.currentTrack, independent); assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(lyrics.loadState, LyricsLoadState.EMPTY);
  record('queue neighbour isolated; revisiting independent selection retains explicit choice');
  // Replaying original search uses automatic mode and creates an original-catalog entry.
  await searchPlay();
  assert.equal(player.currentTrack.catalogRef, original.catalogRef);
  assert.equal(player.currentTrack.otherRecordingOrigin, undefined);
  assert.equal(player.currentTrack.manualPlaybackRef, undefined);
  assert.ok(requests.some(url => url.searchParams.get('automatic') === 'true'));
  record('original search replay re-runs automatic resolution');
  // Delayed lyric response cannot resurrect the old recording after an independent choice.
  const staleLyric = {};
  const liveLyricRaw = NetEaseApi.lyricRaw;
  NetEaseApi.lyricRaw = () => new Promise(resolve => { staleLyric.resolve = resolve; });
  player.trackChangeHandler(player.currentTrack);
  ui.click('查看其他录音候选'); ui.click('选择候选：独立版本 MV');
  waitMs = 400; gateway.controls.calls.length = 0;
  ui.click('确认播放此独立曲目');
  staleLyric.resolve({ lrc: '[00:01]旧曲迟到歌词', yrc: '' }); await delay(10);
  assert.equal(lyrics.lines.length, 0); assert.equal(lyrics.activeIndex, -1);
  await until(() => gateway.controls.calls.some(url => url.pathname === '/x/player/playurl'));
  NetEaseApi.lyricRaw = liveLyricRaw;
  await queue.playFromList([local], 0, context); await delay(500);
  assert.equal(player.currentTrack, local); assert.equal(player.state, PlayerState.PLAYING);
  assert.equal(lyrics.lines.length, 0); assert.equal(ui.render().length, 0);
  assert.equal(downloads.length, 0); record('switch cancels pending manual audio and ignores stale original lyrics');
  if (process.argv.includes('--record')) writeFileSync(new URL('../docs/research/assets/issue29-client-interactions.json', import.meta.url),
    JSON.stringify({ boundary: 'Actual Hvigor compiled controls → ArkTS player/queue/lyrics/API → authenticated HTTP gateway; ArkUI renderer, Kit media, client storage and third-party responses controlled. Not native layout/touch or real audio.', records }, null, 2) + '\n');
  console.log('PASS explicit other-recording confirmation, independent identity/metadata/queue scope, full-only playback, failures/retry, fresh search, lyric reset and stale audio/lyric cancellation.');
  }
} finally { await gateway.close(); }
