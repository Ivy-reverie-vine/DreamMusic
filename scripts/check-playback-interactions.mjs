// Node.js 24+: 执行真实 ArkTS 状态逻辑；Kit/存储边界使用替身。
// 不代替原生手势、点击派发、AVPlayer 或真实 SQLite 验收。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const sourceRoot = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, exports, dependencies = {}) {
  const source = readFileSync(new URL(path, sourceRoot), 'utf8')
    .replace(/^import .+;\r?\n/gm, '')
    .replace(/^@Observed\r?\n/gm, '')
    .replace(/^export /gm, '');
  return runInNewContext(
    `${stripTypeScriptTypes(source, { mode: 'transform' })}\n({ ${exports.join(', ')} })`, dependencies
  );
}
const flush = () => new Promise((resolve) => setImmediate(resolve));
const plain = (value) => JSON.parse(JSON.stringify(value));
const { QueueDragState, nearestQueueRow } = load(
  'service/playback/QueueDragState.ets', ['QueueDragState', 'nearestQueueRow']
);
const original = [10, 20, 30, 40];
for (let from = 0; from < original.length; from += 1) {
  for (let to = 0; to < original.length; to += 1) {
    const drag = new QueueDragState();
    assert.equal(drag.begin(original, original[from]), true);
    drag.setTarget(to);
    const result = drag.finish(original);
    const expected = original.slice();
    expected.splice(to, 0, expected.splice(from, 1)[0]);
    assert.deepEqual(result === null ? original : Array.from(result), expected);
    assert.deepEqual(original, [10, 20, 30, 40]);
  }
}
const drag = new QueueDragState();
assert.equal(drag.begin(original, 999), false);
drag.begin(original, 20);
drag.setTarget(3);
drag.cancel();
assert.equal(drag.finish(original), null);
for (const target of [-1, original.length]) {
  drag.begin(original, 20);
  drag.setTarget(target);
  assert.equal(drag.finish(original), null);
}
for (const changed of [[10, 30, 40], [10, 30, 20, 40], [10, 20, 30, 40, 50], [10, 20, 99, 40]]) {
  drag.begin(original, 20);
  drag.setTarget(3);
  assert.equal(drag.finish(changed), null);
}
const rows = [{ id: -9, top: 100, height: 48 }, { id: 1, top: 160, height: 100 },
  { id: 7, top: 270, height: 64 }];
assert.equal(nearestQueueRow(150, rows), -9);
assert.equal(nearestQueueRow(173, rows), 1);
assert.equal(nearestQueueRow(290, rows), 7);
assert.equal(nearestQueueRow(150, []), null);

const { QueueEngine, PlayMode } = load('service/playback/QueueEngine.ets', ['QueueEngine', 'PlayMode']);
for (const mode of Object.values(PlayMode)) {
  const engine = new QueueEngine();
  engine.setQueue(original, 1, mode);
  const before = engine.toSnapshot();
  const shuffleIds = Array.from(before.shuffleOrder, (index) => before.tracks[index]);
  assert.equal(engine.reorder([40, 10, 30, 20]), true);
  const after = engine.toSnapshot();
  assert.equal(engine.current(), 20);
  assert.equal(engine.currentMode, mode);
  assert.deepEqual(Array.from(after.shuffleOrder, (index) => after.tracks[index]), shuffleIds);
  assert.equal(after.shufflePos, before.shufflePos);
  assert.equal(after.shuffleSteps, before.shuffleSteps);
  const snapshot = JSON.stringify(after);
  for (const invalid of [[10, 20], [10, 10, 30, 40], [10, 20, 30, 99]]) {
    assert.equal(engine.reorder(invalid), false);
    assert.equal(JSON.stringify(engine.toSnapshot()), snapshot);
  }
  const restored = new QueueEngine();
  restored.fromSnapshot(plain(after));
  assert.equal(restored.current(), 20);
  assert.equal(restored.currentMode, mode);
  assert.equal(restored.next(), engine.next());
}

const { PlayerState } = load('model/Playback.ets', ['PlayerState']);
let stored = null;
let writes = 0;
const tracks = original.map((id) => ({ id, path: `music/${id}.mp3` }));
const player = {
  state: PlayerState.PAUSED, currentTrack: null, positionMs: 0, durationMs: 10000,
  sleepTimerSnapshot: { active: false, deadlineMs: 0 }, errorText: '', requestId: 0,
  isCurrentRequest(request) { return request === this.requestId; },
  failRequest(request) { if (this.isCurrentRequest(request)) this.errorText = '这首音乐暂时无法播放，请重试'; },
  checkSleepTimer() { return false; },
  restoreSleepTimer() { return false; },
  async playTrack(track) { this.currentTrack = track; this.state = PlayerState.PLAYING; },
  restorePaused(track, positionMs) { this.currentTrack = track; this.positionMs = positionMs; this.state = PlayerState.PAUSED; },
  seekTo(positionMs) { this.positionMs = positionMs; }
};
const store = {
  async init() {}, async listTracks() { return tracks; }, async loadPlayerState() { return stored; },
  async savePlayerState(snapshot, positionMs, timer) {
    writes += 1;
    stored = plain({ queue: snapshot.tracks, currentIndex: snapshot.currentIndex, mode: snapshot.mode,
      shuffleOrder: snapshot.shuffleOrder, shufflePos: snapshot.shufflePos, shuffleSteps: snapshot.shuffleSteps,
      positionMs, sleepTimerActive: timer.active, sleepTimerDeadlineMs: timer.deadlineMs });
  }
};
const { queueViewModel: queue, QueueViewModel } = load(
  'viewmodel/QueueViewModel.ets', ['queueViewModel', 'QueueViewModel'], {
    QueueEngine, PlayMode, PlayerState, playerViewModel: player,
    setInterval() { return 0; },
    BackgroundPlayback: { getInstance() { return { sync() {} }; } },
    LibraryStore: { getInstance() { return store; } }
  }
);
await queue.playFromList(tracks, 1, { filesDir: '/sandbox' });
player.positionMs = 4321;
queue.cycleMode();
await flush();
const previousMode = queue.mode;
assert.equal(queue.reorder([40, 10, 30, 20]), true);
assert.equal(queue.currentId, 20);
assert.equal(player.currentTrack.id, 20);
assert.equal(player.positionMs, 4321);
assert.equal(queue.mode, previousMode);
await flush();
assert.deepEqual(stored.queue, [40, 10, 30, 20]);
assert.equal(stored.positionMs, 4321);
const previousWrites = writes;
assert.equal(queue.reorder([40, 10, 10, 20]), false);
await flush();
assert.equal(writes, previousWrites);
const restarted = new QueueViewModel();
await restarted.restore({ filesDir: '/sandbox' });
assert.deepEqual(Array.from(restarted.queueTracks, (track) => track.id), [40, 10, 30, 20]);
assert.equal(restarted.currentId, 20);
assert.equal(restarted.mode, previousMode);
assert.equal(player.positionMs, 4321);

const { PlaybackControlGate } = load('viewmodel/PlaybackControlGate.ets', ['PlaybackControlGate'],
  { playerViewModel: player });
const gate = new PlaybackControlGate();
let release;
let executed = 0;
const first = gate.run(() => { executed += 1; return new Promise((resolve) => { release = resolve; }); });
assert.equal(gate.busy, true);
await gate.run(async () => { executed += 1; });
assert.equal(executed, 1);
release();
await first;
assert.equal(gate.busy, false);
await gate.run(async () => { throw new Error('pause failed'); });
assert.equal(gate.busy, false);
assert.equal(player.errorText, '这首音乐暂时无法播放，请重试');
await gate.run(async () => { executed += 1; });
assert.equal(executed, 2);
console.log('PASS: drag commit/cancel/bounds/concurrent changes, measured drop targets, reorder invariants, snapshot persistence/restore and repeated command gating.');
