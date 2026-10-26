import { describe, it, expect } from '@ohos/hypium';
import { HapticService } from '../main/ets/service/haptic/HapticService';

export default function hapticServiceTest() {
  describe('HapticService', () => {
    it('triggerDragSnap_runsSafelyWithoutThrowing', 0, () => {
      let threw = false;
      try {
        HapticService.triggerDragSnap();
      } catch (_e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('triggerFavorite_runsSafelyWithoutThrowing', 0, () => {
      let threw = false;
      try {
        HapticService.triggerFavorite();
      } catch (_e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('triggerSelection_runsSafelyWithoutThrowing', 0, () => {
      let threw = false;
      try {
        HapticService.triggerSelection();
      } catch (_e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });
}
