import { describe, it, expect } from '@ohos/hypium';
import { SleepTimer } from '../main/ets/service/playback/SleepTimer';

export default function sleepTimerTest() {
  describe('SleepTimer', () => {
    it('startAfter_usesAbsoluteDeadline', 0, () => {
      const timer = new SleepTimer();
      timer.startAfter(30 * 60 * 1000, 1000);
      expect(timer.snapshot.active).assertTrue();
      expect(timer.snapshot.deadlineMs).assertEqual(1801000);
      expect(timer.remainingMs(1000)).assertEqual(1800000);
    });

    it('restart_resetsDeadlineFromNow', 0, () => {
      const timer = new SleepTimer();
      timer.startAfter(60 * 60 * 1000, 1000);
      timer.startAfter(120 * 60 * 1000, 2000);
      expect(timer.snapshot.deadlineMs).assertEqual(7202000);
    });

    it('cancel_clearsState', 0, () => {
      const timer = new SleepTimer();
      timer.startAfter(30 * 60 * 1000, 1000);
      timer.cancel();
      expect(timer.snapshot.active).assertFalse();
      expect(timer.snapshot.deadlineMs).assertEqual(0);
      expect(timer.remainingMs(1000)).assertEqual(0);
    });

    it('remaining_neverBecomesNegative', 0, () => {
      const timer = new SleepTimer();
      timer.startAfter(1000, 1000);
      expect(timer.remainingMs(2500)).assertEqual(0);
    });

    it('restore_futureSnapshot_keepsTimer', 0, () => {
      const timer = new SleepTimer();
      timer.restore({ active: true, deadlineMs: 5000 }, 4000);
      expect(timer.snapshot.active).assertTrue();
      expect(timer.remainingMs(4000)).assertEqual(1000);
    });

    it('restore_expiredSnapshot_clearsTimer', 0, () => {
      const timer = new SleepTimer();
      timer.restore({ active: true, deadlineMs: 5000 }, 5000);
      expect(timer.snapshot.active).assertFalse();
      expect(timer.snapshot.deadlineMs).assertEqual(0);
    });

    it('consumeIfDue_onlyConsumesOnce', 0, () => {
      const timer = new SleepTimer();
      timer.startAfter(1000, 1000);
      expect(timer.consumeIfDue(2000)).assertTrue();
      expect(timer.consumeIfDue(3000)).assertFalse();
      expect(timer.snapshot.active).assertFalse();
    });
  });
}
