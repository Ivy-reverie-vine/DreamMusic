import { describe, it, expect } from '@ohos/hypium';
import { planImport } from '../main/ets/service/library/ImportPlanner';

export default function importPlannerTest() {
  describe('ImportPlanner', () => {
    it('plan_basicFiles_normalizesExt', 0, () => {
      const plan = planImport(['/a/b/song.MP3', '/a/b/song2.Flac'], []);
      expect(plan.items.length).assertEqual(2);
      expect(plan.items[0].ext).assertEqual('.mp3');
      expect(plan.items[1].ext).assertEqual('.flac');
      expect(plan.items[0].destRelative).assertEqual('song.MP3');
      expect(plan.skipped.length).assertEqual(0);
    });

    it('plan_unsupportedFormats_skipped', 0, () => {
      const plan = planImport(['a.txt', 'b.mp3', 'c.ogg', 'noext', 'd.wav'], []);
      expect(plan.items.length).assertEqual(2);
      expect(plan.skipped.length).assertEqual(3);
      expect(plan.skipped[0]).assertEqual('a.txt');
      expect(plan.skipped[1]).assertEqual('c.ogg');
      expect(plan.skipped[2]).assertEqual('noext');
    });

    it('plan_existingPath_duplicate', 0, () => {
      const plan = planImport(['/x/song.mp3'], ['song.mp3']);
      expect(plan.items.length).assertEqual(0);
      expect(plan.duplicates.length).assertEqual(1);
      expect(plan.duplicates[0]).assertEqual('/x/song.mp3');
    });

    it('plan_sameBasenameInBatch_renamed', 0, () => {
      const plan = planImport(['dir1/x.mp3', 'dir2/x.mp3'], []);
      expect(plan.items.length).assertEqual(2);
      expect(plan.items[0].destRelative).assertEqual('x.mp3');
      expect(plan.items[1].destRelative).assertEqual('x (1).mp3');
    });

    it('plan_illegalFilenameChars_sanitized', 0, () => {
      const plan = planImport(['/a/b/c:d?e.mp3'], []);
      expect(plan.items.length).assertEqual(1);
      const dest = plan.items[0].destRelative;
      expect(dest.includes(':')).assertFalse();
      expect(dest.includes('?')).assertFalse();
      expect(dest.endsWith('.mp3')).assertTrue();
    });

    it('plan_mixedBatch_counts', 0, () => {
      const plan = planImport(['a.mp3', 'b.txt', 'a.mp3', 'c.flac'], ['old.mp3']);
      // a.mp3 出现两次 → 一次入库一次重命名;b.txt 跳过;old.mp3 不影响
      expect(plan.items.length).assertEqual(3);
      expect(plan.skipped.length).assertEqual(1);
      expect(plan.duplicates.length).assertEqual(0);
      const dests: string[] = [];
      plan.items.forEach((it) => {
        dests.push(it.destRelative);
      });
      expect(dests.includes('a.mp3')).assertTrue();
      expect(dests.includes('a (1).mp3')).assertTrue();
      expect(dests.includes('c.flac')).assertTrue();
    });
  });
}
