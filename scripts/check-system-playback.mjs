// Node 24+：运行真实 ArkTS 逻辑，Kit / 音频 / 存储边界替身；不代表设备系统 UI 验收。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8')
    .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^@Observed\r?\n/gm, '').replace(/^export (default )?/gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { Error, Date, setTimeout, clearTimeout, ...dependencies }, { filename: path });
}
function methods(path, names, dependencies) {
  const source = readFileSync(new URL(path, root), 'utf8');
  const bodies = names.map(name => {
    const match = new RegExp(`\\n  (?:private )?(?:async )?${name}\\(`).exec(source);
    assert.ok(match, name);
    const start = match.index + 3;
    let end = source.indexOf('{', start) + 1, depth = 1;
    while (depth > 0) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; end++; }
    return source.slice(start, end).replace(/^private /, '');
  });
  return runInNewContext(stripTypeScriptTypes(`class Component { ${bodies.join('\n')} }\nnew Component()`,
    { mode: 'transform' }), dependencies);
}
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject }; };
const flush = () => new Promise(resolve => setImmediate(resolve));
const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
const { SleepTimer } = load('service/playback/SleepTimer.ets', ['SleepTimer']);
const launch = load('model/PlaybackLaunch.ets', ['PlaybackLaunch', 'playbackLaunch', 'PLAYBACK_DESTINATION_KEY', 'PLAYBACK_DESTINATION', 'PLAYLIST_ID_KEY']);
const nav = load('model/Navigation.ets', ['RootTab', 'MySubpage', 'selectRoot']);
const gate = deferred();
const shell = methods('pages/IndexV2.ets', ['navigation', 'selectTab', 'openPlaybackEntry', 'checkGate'], {
  ...nav, DreamMusicAuth: { initialize: () => gate.promise, isLoggedIn: () => false }
});
shell.ctx = () => ({});
const ability = load('entryability/EntryAbility.ets', ['EntryAbility'], { UIAbility: class {}, ...launch });
const entry = new ability.EntryAbility();
entry.handlePlaybackWant({ parameters: { [launch.PLAYBACK_DESTINATION_KEY]: 'unknown' } });
assert.equal(launch.playbackLaunch.pending, false);
entry.handlePlaybackWant({ parameters: { [launch.PLAYBACK_DESTINATION_KEY]: launch.PLAYBACK_DESTINATION } });
const gateWork = shell.checkGate();
launch.playbackLaunch.attach(() => shell.openPlaybackEntry());
assert.equal(shell.current, nav.RootTab.NOW_PLAYING, 'cold launch delivered after shell attaches');
gate.resolve(); await gateWork;
assert.equal(shell.loginPromptVisible, false, 'late login gate cannot cover system entry');
for (const current of [nav.RootTab.LIBRARY, nav.RootTab.MY, nav.RootTab.QUEUE]) {
  shell.current = current; shell.showLoginOverlay = true;
  entry.onNewWant({ parameters: { [launch.PLAYBACK_DESTINATION_KEY]: launch.PLAYBACK_DESTINATION } }, {});
  assert.equal(shell.current, nav.RootTab.NOW_PLAYING);
  assert.equal(shell.myPage, nav.MySubpage.HOME);
  assert.equal(shell.showLoginOverlay, false);
}
launch.playbackLaunch.detach(); shell.current = nav.RootTab.MY;
entry.onNewWant({ parameters: { [launch.PLAYBACK_DESTINATION_KEY]: launch.PLAYBACK_DESTINATION } }, {});
assert.equal(shell.current, nav.RootTab.MY);
launch.playbackLaunch.attach(() => shell.openPlaybackEntry());
assert.equal(shell.current, nav.RootTab.NOW_PLAYING);
launch.playbackLaunch.detach(); shell.current = nav.RootTab.MY;
launch.playbackLaunch.attach(() => shell.openPlaybackEntry());
assert.equal(shell.current, nav.RootTab.MY, 'consumed intent never replays on remount');

const states = [], metadata = [], nativeTasks = [], sessions = [];
let createGate = null, startGate = null, stopGate = null, stateGate = null, failLaunch = false;
let taskRunning = false, activeStateWrites = 0, maxStateWrites = 0, wantInfo;
const avSession = {
  PlaybackState: Object.fromEntries(['PLAY', 'PAUSE', 'PREPARE', 'COMPLETED', 'INITIAL', 'ERROR'].map(v => [`PLAYBACK_STATE_${v}`, v])),
  LoopMode: {},
  async createAVSession() {
    if (createGate) await createGate.promise;
    const session = { handlers: {}, destroyed: false,
      on(event, handler) { this.handlers[event] = handler; }, async activate() {},
      async setLaunchAbility(agent) { if (failLaunch) throw new Error('launch failure'); this.agent = agent; },
      async destroy() { this.destroyed = true; },
      async setAVMetadata(meta) { assert.equal(this.destroyed, false); metadata.push(meta); },
      async setAVPlaybackState(state) {
        assert.equal(this.destroyed, false);
        maxStateWrites = Math.max(maxStateWrites, ++activeStateWrites);
        if (stateGate) { const g = stateGate; stateGate = null; await g.promise; }
        states.push(state); activeStateWrites--;
      }
    };
    sessions.push(session); return session;
  }
};
const covers = { async acquire() { return { pixelMap: null, release() {} }; } };
const { BackgroundPlayback } = load('service/playback/BackgroundPlayback.ets', ['BackgroundPlayback'], {
  DesktopLyrics: { getInstance: () => ({ attach() {}, async detach() {}, setContentAvailable() {} }) },
  PlayerState, PlayMode, ...launch, avSession, hilog: { warn() {}, error() {} },
  CoverArtService: { getInstance: () => covers, resolve: () => '', identity: t => String(t?.id ?? '') },
  wantAgent: { async getWantAgent(info) { wantInfo = info; return { id: 15 }; },
    OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 } },
  backgroundTaskManager: { BackgroundMode: { AUDIO_PLAYBACK: 1 },
    async startBackgroundRunning() { nativeTasks.push('start'); if (startGate) await startGate.promise; taskRunning = true; },
    async stopBackgroundRunning() { nativeTasks.push('stop'); if (stopGate) await stopGate.promise; taskRunning = false; }
  }
});
const bp = BackgroundPlayback.getInstance(), ctx = { filesDir: '/files' };
await bp.startLongTask();
createGate = deferred();
const init1 = bp.init(ctx), init2 = bp.init(ctx);
createGate.resolve(); await Promise.all([init1, init2]); createGate = null;
assert.equal(sessions.length, 1);
assert.equal(taskRunning, true, 'play requested before session initialization is retained');
assert.equal(wantInfo.wants[0].parameters[launch.PLAYBACK_DESTINATION_KEY], launch.PLAYBACK_DESTINATION);
assert.equal(sessions[0].agent.id, 15);
await bp.stopLongTask(); nativeTasks.length = 0;
startGate = deferred();
const start = bp.startLongTask(); await flush();
const duplicate = bp.startLongTask(), stop = bp.stopLongTask();
startGate.resolve(); await Promise.all([start, duplicate, stop]); startGate = null;
assert.deepEqual(nativeTasks, ['start', 'stop']); assert.equal(taskRunning, false);
await bp.startLongTask(); stopGate = deferred();
const stopping = bp.stopLongTask(); await flush();
const restarting = bp.startLongTask(); stopGate.resolve();
await Promise.all([stopping, restarting]); stopGate = null;
assert.equal(taskRunning, true, 'a play arriving during stop restarts after stop completes');

const track = id => ({ id, path: `music/${id}.mp3`, title: `song ${id}`, artist: 'artist', album: 'album',
  durationMs: 90000, coverPath: '', neteaseId: 0, importedAt: 0, missing: false });
const a = track(1);
stateGate = deferred(); const blocked = stateGate;
const playing = bp.sync(a, PlayerState.PLAYING, 1000, 90000, PlayMode.SEQUENTIAL, true);
await flush();
const paused = bp.sync(a, PlayerState.PAUSED, 1200, 90000, PlayMode.SEQUENTIAL);
blocked.resolve(); await Promise.all([playing, paused]);
assert.equal(maxStateWrites, 1); assert.equal(states.at(-1).state, 'PAUSE');
await bp.sync(a, PlayerState.ERROR, 1200, 90000, PlayMode.SEQUENTIAL);
assert.equal(states.at(-1).state, 'ERROR', 'state transitions bypass position throttle');
await flush(); assert.equal(metadata.at(-1).artist, 'artist'); assert.equal(metadata.at(-1).duration, 90000);

// 系统命令贯通真实 QueueViewModel / PlayerViewModel，仅音频和存储替身。
const audio = [];
let audioGate = null;
class PlayerSession {
  constructor() { audio.push(this); this.isLoaded = false; this.isPlaying = false; }
  async release() { this.isLoaded = false; this.isPlaying = false; }
  async playFile(path, cb) { this.cb = cb; this.isLoaded = true; this.isPlaying = true; cb.onStateChange(PlayerState.PLAYING); }
  setVolume() {} seekTo(ms) { this.position = ms; } getDuration() { return 90000; }
  async pause() { this.isPlaying = false; this.cb.onStateChange(PlayerState.PAUSED); }
  async togglePause() { if (audioGate) await audioGate.promise;
    this.isPlaying = !this.isPlaying; this.cb.onStateChange(this.isPlaying ? PlayerState.PLAYING : PlayerState.PAUSED); }
}
const saved = [];
const store = { async insertHistory() {}, async savePlayerState(snapshot, pos) { saved.push(pos); } };
const { playerViewModel: player } = load('viewmodel/PlayerViewModel.ets', ['playerViewModel'], {
  PlayerSession, SleepTimer, PlayerState, PlayMode, BackgroundPlayback,
  fileIo: { accessSync: () => true }, LibraryStore: { getInstance: () => store }, hilog: { error() {} }
});
const { QueueViewModel } = load('viewmodel/QueueViewModel.ets', ['QueueViewModel'], {
  QueueEngine, PlayMode, PlayerState, playerViewModel: player, BackgroundPlayback,
  LibraryStore: { getInstance: () => store }, setInterval() {}
});
const queue = new QueueViewModel();
await queue.playFromList([a, track(2)], 0, ctx); await flush();
const session = sessions[0];
session.handlers.pause(); session.handlers.pause(); await bp.commandChain; await flush();
assert.equal(player.state, PlayerState.PAUSED); assert.equal(taskRunning, false);
audioGate = deferred();
session.handlers.play(); session.handlers.play(); await flush();
audioGate.resolve(); await bp.commandChain; audioGate = null; await flush();
assert.equal(player.state, PlayerState.PLAYING, 'duplicate play never toggles back to pause');
session.handlers.playNext(); await bp.commandChain;
assert.equal(player.currentTrack.id, 2);
session.handlers.playPrevious(); await bp.commandChain;
assert.equal(player.currentTrack.id, 1);
session.handlers.seek(95000); await flush(); assert.equal(player.positionMs, 90000);
assert.equal(states.at(-1).position.elapsedTime, 90000);
session.handlers.seek(NaN); await bp.commandChain; assert.equal(player.positionMs, 90000);
session.handlers.pause(); await bp.commandChain;
session.handlers.seek(-10); await flush(); assert.equal(player.positionMs, 0); assert.equal(saved.at(-1), 0);
player.restorePaused(a, 2000, ctx);
session.handlers.seek(3200); session.handlers.play(); await bp.commandChain;
assert.equal(audio.at(-1).position, 3200, 'restored playback starts from system seek position');
const { EntryAbility: LifecycleAbility } = load('entryability/EntryAbility.ets', ['EntryAbility'], {
  UIAbility: class {}, ...launch, BackgroundPlayback, playerViewModel: player, queueViewModel: queue,
  hilog: { info() {} }
});
const lifecycle = new LifecycleAbility(); lifecycle.context = ctx;
lifecycle.onBackground(); await flush(); assert.equal(saved.at(-1), player.positionMs);
const stateCount = states.length;
lifecycle.onForeground(); await flush();
assert.ok(states.length > stateCount); assert.equal(states.at(-1).state, 'PLAY');
assert.equal(sessions.length, 1, 'foreground reuses the session');
player.setSleepTimer(30000); player.checkSleepTimer(Date.now() + 31000); await flush();
assert.equal(player.state, PlayerState.PAUSED); assert.equal(taskRunning, false); assert.equal(states.at(-1).state, 'PAUSE');
await queue.playFromList([a], 0, ctx);
audio.at(-1).cb.onTrackEnded(); await flush();
assert.equal(player.state, PlayerState.COMPLETED); assert.equal(states.at(-1).state, 'COMPLETED');
assert.equal(taskRunning, false);
// 命令失败被隔离，后续命令仍可执行。
bp.onPlayCommand = async () => { throw new Error('native failure'); };
session.handlers.play(); await bp.commandChain;
session.handlers.seek(1000); await bp.commandChain; assert.equal(player.positionMs, 1000);
await bp.release(); assert.equal(session.destroyed, true);
session.handlers.seek(5000); await bp.commandChain; assert.equal(player.positionMs, 1000);

// 初始化失败可以重试，销毁时等待正在初始化的会话并清理。
failLaunch = true; await bp.init(ctx); assert.equal(sessions.at(-1).destroyed, true);
failLaunch = false; await bp.init(ctx); assert.equal(sessions.at(-1).destroyed, false);
await bp.release();
createGate = deferred(); const lateInit = bp.init(ctx); const releasing = bp.release();
createGate.resolve(); await Promise.all([lateInit, releasing]); createGate = null;
assert.equal(sessions.at(-1).destroyed, true); assert.equal(taskRunning, false);
console.log('PASS: system entry cold/warm delivery, login race, session init/release, launch Want, ordered state/task updates, commands, seek/resume, timer and completion.');

// 卡片 call 冷启动也走真实队列/播放器；页面再挂载不应二次恢复。
const cardModel = load('model/MusicCard.ets', ['isMusicCardCommand', 'MUSIC_FORM_METHOD']);
const projections = [];
let restoreReads = 0, restoreGate = deferred();
store.init = async () => {};
store.loadPlayerState = async () => {
  restoreReads++; if (restoreGate) await restoreGate.promise;
  return { queue: [1, 2], currentIndex: 0, positionMs: 4200, mode: PlayMode.REPEAT_ALL,
    shuffleOrder: [], shufflePos: 0, shuffleSteps: 0, sleepTimerActive: false, sleepTimerDeadlineMs: 0 };
};
store.listTracks = async () => [a, track(2)];
const { PlaybackRuntime } = load('viewmodel/PlaybackRuntime.ets', ['PlaybackRuntime'], {
  lyricsViewModel: { lines: [], setContext() {} }, desktopLrc: () => '',
  playerViewModel: player, queueViewModel: queue, PlayerState, BackgroundPlayback, ...cardModel,
  MusicFormPublisher: class { sync(track, state, status, canPlay) { projections.push({ track, state, status, canPlay }); }
    async dispose() {} }
});
const runtime = new PlaybackRuntime();
const coldPlay = runtime.dispatch(ctx, 'play'); await flush();
const warmPage = runtime.ensureReady(ctx);
assert.equal(restoreReads, 1); restoreGate.resolve(); restoreGate = null;
await Promise.all([coldPlay, warmPage]);
assert.equal(player.state, PlayerState.PLAYING); assert.equal(audio.at(-1).position, 4200);
await runtime.dispatch(ctx, 'play'); assert.equal(player.state, PlayerState.PLAYING);
await runtime.dispatch(ctx, 'pause'); await runtime.dispatch(ctx, 'pause');
assert.equal(player.state, PlayerState.PAUSED);
await runtime.dispatch(ctx, 'next'); assert.equal(player.currentTrack.id, 2);
await runtime.dispatch(ctx, 'previous'); assert.equal(player.currentTrack.id, 1);
await runtime.ensureReady(ctx); assert.equal(restoreReads, 1, 'foreground never resets live queue');
assert.ok(projections.some(p => p.state === 'playing')); assert.ok(projections.some(p => p.state === 'paused'));
const originalPause = player.pause.bind(player);
player.pause = async () => { throw Error('native command failure'); };
await runtime.dispatch(ctx, 'pause'); player.pause = originalPause;
await runtime.dispatch(ctx, 'pause'); assert.equal(player.state, PlayerState.PAUSED);
player.failRequest(player.requestId, 'FILE_MISSING');
await runtime.dispatch(ctx, 'play'); assert.equal(player.state, PlayerState.ERROR);
assert.equal(projections.at(-1).canPlay, false);
player.failRequest(player.requestId, 'NETWORK');
await runtime.dispatch(ctx, 'play'); assert.equal(player.state, PlayerState.PLAYING);
player.setSleepTimer(30000); player.checkSleepTimer(Date.now() + 31000); await flush();
assert.equal(projections.at(-1).state, 'paused');
await runtime.dispatch(ctx, 'invalid'); assert.equal(restoreReads, 1);
// 队列直达封面补齐也发布，不依赖播放中的 tick。
let metadataNotifications = 0; const observer = player.playbackChangedHandler;
player.playbackChangedHandler = () => { metadataNotifications++; observer(); };
queue.updateCurrentCover(player.currentTrack, 'https://example.test/cover.jpg');
assert.equal(metadataNotifications, 1);
player.currentTrack = null;
await runtime.dispatch(ctx, 'next'); assert.equal(projections.at(-1).canPlay, false);
await runtime.dispose(); await bp.release();
// EntryAbility IPC adapter: registered method -> parsed command -> same runtime, malformed input ignored.
let calleeHandler, received = [];
const { EntryAbility: CardAbility } = load('entryability/EntryAbility.ets', ['EntryAbility'], {
  UIAbility: class {}, ...launch, ...cardModel,
  playbackRuntime: { ensureReady: async () => {}, dispatch: async (context, command) => received.push(command) },
  ThemeService: { getInstance: () => ({ applyMode() {} }) }, ThemeMode: { DARK: 'dark' },
  BackgroundAdapter: { restoreIfPresent: async () => true },
  BackgroundPlayback, playerViewModel: player,
  ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: 0 } },
  LibraryStore: { getInstance: () => ({ init: async () => {} }) },
  PlaylistFormStore: { refreshAll: async () => {} },
  LibraryScanService: { scan: async () => {} }, networkViewModel: { load: async () => {} },
  hilog: { info() {}, error() {} }
});
const cardAbility = new CardAbility();
cardAbility.context = { ...ctx, getApplicationContext: () => ({ setColorMode() {} }) };
cardAbility.callee = { on(method, handler) { assert.equal(method, cardModel.MUSIC_FORM_METHOD); calleeHandler = handler; } };
cardAbility.onCreate({}, {});
calleeHandler({ readString: () => '{"command":"play"}' });
calleeHandler({ readString: () => 'broken JSON' });
assert.deepEqual(received, ['play']); await flush(); await bp.release();
console.log('PASS: form call cold restore/seek, single initialization, idempotent commands, failure recovery, queue controls, metadata push, empty state and EntryAbility IPC.');
