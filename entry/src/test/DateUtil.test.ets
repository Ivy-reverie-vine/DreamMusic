import { describe, it, expect } from '@ohos/hypium';
import { shanghaiDateString } from '../main/ets/common/DateUtil';

export default function dateUtilTest() {
  describe('DateUtil', () => {
    it('shanghaiDate_midnightOffset', 0, () => {
      // 2026-08-16 15:59 UTC → 东八区 2026-08-16 23:59,仍同一天
      const now = Date.UTC(2026, 7, 16, 15, 59, 0);
      expect(shanghaiDateString(now)).assertEqual('2026-08-16');
    });

    it('shanghaiDate_crossesDay', 0, () => {
      // 2026-08-16 16:01 UTC → 东八区 2026-08-17 00:01,跨天
      const now = Date.UTC(2026, 7, 16, 16, 1, 0);
      expect(shanghaiDateString(now)).assertEqual('2026-08-17');
    });
  });
}
