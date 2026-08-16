import { describe, it, expect } from '@ohos/hypium';
import { layoutHandwritten } from '../main/ets/components/HandwrittenLayout';

export default function handwrittenLayoutTest() {
  describe('HandwrittenLayout', () => {
    it('layout_ivyreverie_producesStrokes', 0, () => {
      const l = layoutHandwritten('IvyReverie', 260, 3000);
      expect(l.strokes.length).assertLarger(20);
      expect(l.width).assertEqual(260);
      expect(l.height).assertLarger(0);
      expect(l.totalMs).assertClose(3000, 150);
    });

    it('layout_strokes_havePathAndLength', 0, () => {
      const l = layoutHandwritten('IvyReverie', 260, 3000);
      for (let i = 0; i < l.strokes.length; i++) {
        const s = l.strokes[i];
        expect(s.commands.length).assertLarger(0);
        expect(s.points.length).assertLarger(0);
        expect(s.len).assertLarger(0);
        expect(s.width).assertLarger(0);
        expect(s.delayMs).assertLargerOrEqual(0);
        expect(s.durMs).assertLargerOrEqual(50);
      }
    });

    it('layout_unknownChar_skipped', 0, () => {
      const l = layoutHandwritten('I?x', 260, 3000);
      // 未知字符按占位宽度跳过,已知字形仍输出笔画
      expect(l.strokes.length).assertLarger(0);
      expect(l.width).assertEqual(260);
    });
  });
}
