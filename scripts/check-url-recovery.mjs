// Production ArkTS API/queue/PlayerSession → authenticated HTTP gateway and media.
// Only HarmonyOS Kit/persistence and third-party provider responses are controlled.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { startRecoveryGateway } from '../../NightDream/server/test-support/recoveryGateway.js';

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
  while (!predicate()) { assert.ok(Date.now() < deadline, 'recovery did not settle'); await delay(10); }
}
const gateway = await startRecoveryGateway();
try {
  const requests = [], natives = [], records = [], timers = [];
  const hilog = { error() {}, warn() {} };
  const { normalizeBaseUrl } = load('service/network/HealthStateMachine.ets', ['normalizeBaseUrl']);
  const { ApiClient, ApiError } = load('service/network/ApiClient.ets', ['ApiClient', 'ApiError'], {
    normalizeBaseUrl, hilog, http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 }, createHttp() {
      const controller = new AbortController();
      return { async request(url, options) {
        requests.push(new URL(url));
        const response = await fetch(url, { headers: options.header, signal: controller.signal });
        return { responseCode: response.status, result: await response.text(), header: {} };
      }, destroy() { controller.abort(); } };
    } },
  });
  const { NetEaseApi } = load('service/network/NetEaseApi.ets', ['NetEaseApi'], {
    ApiClient, ApiError, DreamMusicAuth: { baseV2: async () => gateway.base + '/dreammusic/api/v2',
      base: async () => gateway.base + '/dreammusic/api/v1', username: () => 'identity-user',
      withApiKey: (_ctx, callback) => callback({ 'X-API-Key': gateway.apiKey }) },
    playbackDiagnostics: { record() {} }, classifyPlaybackError: () => 'failure',
    DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL: 'empty', DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT: 'timeout',
  });
  const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
  const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
  const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
  const identity = load('model/OnlineTrackIdentity.ets', ['createOnlineTrack', 'canDownloadNetEase']);
  const kitFiles = { accessSync: () => true, openSync: () => ({ fd: 1 }), statSync: () => ({ size: 1 }),
    closeSync() {}, OpenMode: { READ_ONLY: 1 } };
  const { PlayerSession } = load('service/playback/PlayerSession.ets', ['PlayerSession'], {
    PlayerState, hilog, playbackDiagnostics: { record() {} }, fileIo: kitFiles,
    DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE: 'init',
    DIAGNOSTIC_CATEGORY_PLAYBACK_FAILURE: 'playing', DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE: 'url',
    media: { async createAVPlayer() {
      const handlers = {};
      const native = { state: 'idle', duration: 90000, currentTime: 0, plays: 0,
        on(event, callback) { handlers[event] = callback; },
        emit(state) { this.state = state; handlers.stateChange?.(state); },
        set url(value) { this.source = value; this.emit('initialized'); },
        set fdSrc(value) { this.source = value; this.emit('initialized'); },
        async prepare() {
          if (typeof this.source === 'string') {
            const response = await fetch(this.source);
            if (!response.ok) { this.emit('error'); handlers.error?.(); throw new Error('HTTP ' + response.status); }
            const bytes = new Uint8Array(await response.arrayBuffer());
            assert.equal(new TextDecoder().decode(bytes.slice(0, 4)), 'RIFF');
          }
          this.emit('prepared');
        },
        async play() { this.plays++; this.emit('playing'); },
        async pause() { this.emit('paused'); }, async release() { this.emit('released'); },
        seek(ms) { this.currentTime = ms; }, setVolume() {}, handlers,
      };
      natives.push(native); return native;
    } },
  });
  const deps = { ...identity, PlayerSession, PlayerState, PlayMode, SleepTimer, ApiError, NetEaseApi, hilog,
    fileIo: kitFiles, LibraryStore: { getInstance: () => ({ async insertHistory() {} }) },
    BackgroundPlayback: { getInstance: () => ({ sync() {}, startLongTask() {}, stopLongTask() {} }) },
    setTimeout(callback, ms) { if (ms === 15000) timers.push(callback); return setTimeout(callback, ms); },
  };
  const { playerViewModel: player } = load('viewmodel/PlayerViewModel.ets', ['playerViewModel'], deps);
  const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
    ...deps, QueueEngine, playerViewModel: player, setInterval() {},
  });
  const queue = new QueueViewModel(), context = { filesDir: '/sandbox' };
  let ready = 0, lyricRevisions = 0;
  player.trackChangeHandler = () => { lyricRevisions++; };
  async function play() {
    const selected = await gateway.select();
    const track = identity.createOnlineTrack({ id: 123, name: '目录歌曲', artist: '原歌手', album: '目录专辑',
      coverUrl: '', durationMs: 90000, source: 'api-enhanced', mediaRef: selected.catalog.mediaRef });
    track.catalogRef = selected.catalog.mediaRef; track.lyricsRef = selected.catalog.mediaRef;
    track.manualPlaybackRef = selected.selected.mediaRef; track.sourceSearchSession = selected.searchSession;
    const request = player.beginTrack(track, context, () => ready++);
    queue.selectFromList([track], 0, context, request);
    await player.playTrack(track, context, 12000, request, { ...selected.body, url: selected.body.data[0].url });
    return track;
  }
  // Actual HTTP 410, duplicated state/error/catch, cache bypass, native boundary playing.
  const track = await play(); await until(() => player.state === PlayerState.PLAYING);
  assert.equal(player.currentTrack, track); assert.equal(queue.currentId, track.id);
  assert.equal(track.playbackRef, track.manualPlaybackRef); assert.equal(player.positionMs, 12000);
  assert.equal(natives.at(-1).currentTime, 12000); assert.equal(ready, 1);
  assert.equal(requests.filter(url => url.searchParams.get('recover') === 'true').length, 1);
  assert.ok(lyricRevisions >= 2); assert.equal(identity.canDownloadNetEase(track), false);
  records.push({ scenario: 'controlled 410 → exact-resource refresh → playing at 12000ms',
    evidence: gateway.evidence.splice(0), resolutions: requests.length, readyCalls: ready });
  // Mid-play failure retains position and never runs the download callback again.
  queue.updateCurrentCover(track, 'https://cover.test/before-recovery');
  assert.equal(player.currentTrack.recoveryToken, track.recoveryToken);
  assert.equal(player.currentTrack.lyricsRevision, track.lyricsRevision);
  gateway.recoveryControls.resolveDelayMs = 80;
  player.positionMs = 23000;
  const old = natives.at(-1); old.emit('error'); old.handlers.error();
  await until(() => requests.filter(url => url.searchParams.get('recover') === 'true').length === 2);
  queue.updateCurrentCover(player.currentTrack, 'https://cover.test/during-recovery');
  const withCover = player.currentTrack;
  await until(() => player.state === PlayerState.PLAYING);
  gateway.recoveryControls.resolveDelayMs = 0;
  assert.equal(player.currentTrack, withCover);
  assert.equal(queue.queueTracks[0], withCover);
  assert.equal(withCover.streamCoverUrl, 'https://cover.test/during-recovery');
  assert.equal(player.positionMs, 23000); assert.equal(ready, 1); assert.equal(natives.at(-1).currentTime, 23000);
  records.push({ scenario: 'mid-play recovery; duplicate events coalesced; no second ready/download', positionMs: player.positionMs });
  // Persistent media failure reaches an actionable terminal after exactly two refreshes.
  gateway.recoveryControls.failFresh = true; const before = requests.length;
  await play(); await until(() => player.state === PlayerState.ERROR && player.errorCode === 'PLAYBACK_RECOVERY_FAILED');
  assert.equal(requests.slice(before).filter(url => url.searchParams.get('recover') === 'true').length, 2);
  assert.equal(player.recoveryAction, 'retry');
  records.push({ scenario: 'persistent 410 → two retries → actionable error', refreshes: 2 });
  // Switching cancels an in-flight HTTP refresh; late work cannot play the old resource.
  gateway.recoveryControls.failFresh = false; gateway.recoveryControls.resolveDelayMs = 350;
  const switching = play(); await until(() => player.recoveryRunning);
  const local = { id: 77, path: 'music/local.wav', title: '本地曲', artist: '', album: '', durationMs: 90000,
    coverPath: '', importedAt: 0, missing: false, neteaseId: 0 };
  deps.fileIo.openSync = () => ({ fd: 1 }); deps.fileIo.statSync = () => ({ size: 1 });
  deps.fileIo.closeSync = () => {}; deps.fileIo.OpenMode = { READ_ONLY: 1 };
  await queue.playFromList([local], 0, context); await switching; await delay(400);
  assert.equal(player.currentTrack.id, 77); assert.equal(player.state, PlayerState.PLAYING);
  records.push({ scenario: 'switch to local cancels stale HTTP/media ownership', currentId: 77 });
  // Exercise the production total deadline without waiting 15 seconds.
  const pending = play(); await until(() => player.recoveryRunning); timers.at(-1)();
  await pending; await until(() => player.state === PlayerState.ERROR);
  assert.equal(player.errorCode, 'PLAYBACK_RECOVERY_FAILED');
  await delay(400); assert.equal(player.state, PlayerState.ERROR);
  records.push({ scenario: 'total deadline cancels slow resolution and suppresses late playback', deadlineMs: 15000 });
  const closing = play(); await until(() => player.recoveryRunning);
  await player.dispose(); await closing; await delay(400);
  assert.equal(player.currentTrack, null); assert.equal(player.state, PlayerState.IDLE);
  assert.equal(player.recoveryRunning, false);
  assert.ok(natives.every(native => native.state === 'released'));
  records.push({ scenario: 'Ability teardown cancels HTTP recovery; late responses never reactivate playback' });
  if (process.argv.includes('--record')) writeFileSync(new URL('../docs/research/assets/issue32-client-recovery.json', import.meta.url),
    JSON.stringify({ boundary: 'actual ArkTS + authenticated HTTP + real WAV bytes; Kit decoder controlled; native browser decoding recorded separately', records }, null, 2) + '\n');
  console.log('PASS T13 actual ArkTS/HTTP/session: controlled 410 recovery, position/identity/queue, event coalescing, no repeated download, bounded failure, switch and deadline cancellation.');
} finally { await gateway.close(); }
