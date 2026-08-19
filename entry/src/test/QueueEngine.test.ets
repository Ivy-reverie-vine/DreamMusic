import { describe, it, expect } from '@ohos/hypium';
import { QueueEngine, PlayMode } from '../main/ets/service/playback/QueueEngine';

function ids(engine: QueueEngine, count: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < count; i++) {
    out.push(engine.next());
  }
  return out;
}

export default function queueEngineTest() {
  describe('QueueEngine', () => {
    it('setQueue_currentIndex', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 1);
      expect(e.current()).assertEqual(2);
    });

    it('next_sequential_stopsAtEnd', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 1);
      expect(e.next()).assertEqual(3);
      expect(e.next()).assertEqual(-1);
    });

    it('next_repeatAll_wraps', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 2, PlayMode.REPEAT_ALL);
      expect(e.next()).assertEqual(1);
    });

    it('next_repeatOne_sameTrack', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 1, PlayMode.REPEAT_ONE);
      expect(e.next()).assertEqual(2);
      expect(e.next()).assertEqual(2);
    });

    it('shuffle_oneCycle_noRepeats_andNewCycleDiffersFromLast', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3, 4], 0, PlayMode.SHUFFLE);
      const first = e.current();
      const cycle: number[] = [first];
      cycle.push(e.next());
      cycle.push(e.next());
      cycle.push(e.next());
      // 一个周期内 4 个 id 互不相同
      const uniq = new Set<number>();
      cycle.forEach((x: number) => {
        uniq.add(x);
      });
      expect(uniq.size).assertEqual(4);
      // 新周期第一首 ≠ 上一周期最后一首
      const newFirst = e.next();
      expect(newFirst !== cycle[3]).assertTrue();
      expect(uniq.has(newFirst)).assertTrue();
    });

    it('move_currentFollowsMovedTrack', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 1);
      e.move(1, 0);
      expect(e.current()).assertEqual(2);
    });

    it('move_otherTrack_currentStaysOnSameId', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 2);
      e.move(0, 2);
      expect(e.current()).assertEqual(3);
      // 移动后队列 [2,3,1],current=3,顺序模式还能播 1 再停
      expect(e.next()).assertEqual(1);
      expect(e.next()).assertEqual(-1);
    });

    it('removeAt_beforeCurrent_shifts', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 2);
      e.removeAt(0);
      expect(e.current()).assertEqual(3);
      expect(e.next()).assertEqual(-1);
    });

    it('replaceTrackId_keepsCurrentSlot_andFollowingOrder', 0, () => {
      const e = new QueueEngine();
      e.setQueue([-101, 2, 3], 0);
      e.replaceTrackId(-101, 101);
      expect(e.current()).assertEqual(101);
      expect(e.queueIds[0]).assertEqual(101);
      expect(e.next()).assertEqual(2);
      expect(e.next()).assertEqual(3);
    });

    it('prev_sequential_clampsAtStart', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 1);
      expect(e.prev()).assertEqual(1);
      expect(e.prev()).assertEqual(1);
    });

    it('prev_repeatAll_wraps', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 0, PlayMode.REPEAT_ALL);
      expect(e.prev()).assertEqual(3);
    });

    it('snapshot_roundtrip', 0, () => {
      const e = new QueueEngine();
      e.setQueue([1, 2, 3], 1, PlayMode.REPEAT_ALL);
      e.next();
      const snap = e.toSnapshot();
      const e2 = new QueueEngine();
      e2.fromSnapshot(snap);
      expect(e2.current()).assertEqual(e.current());
      expect(e2.next()).assertEqual(e.next());
    });
  });
}
