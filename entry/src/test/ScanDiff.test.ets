import { describe, it, expect } from '@ohos/hypium';
import { computeScanDiff, ScanDiffResult } from '../main/ets/service/library/ScanDiff';

export default function scanDiffTest() {
  describe('ScanDiff', () => {
    it('diff_newFileOnDisk_added', 0, () => {
      const r: ScanDiffResult = computeScanDiff(['a.mp3'], ['a.mp3', 'b.mp3']);
      expect(r.added.length).assertEqual(1);
      expect(r.added[0]).assertEqual('b.mp3');
      expect(r.missing.length).assertEqual(0);
      expect(r.unchanged.length).assertEqual(1);
    });

    it('diff_dbHasGoneFile_missing', 0, () => {
      const r: ScanDiffResult = computeScanDiff(['a.mp3', 'gone.mp3'], ['a.mp3']);
      expect(r.missing.length).assertEqual(1);
      expect(r.missing[0]).assertEqual('gone.mp3');
      expect(r.added.length).assertEqual(0);
    });

    it('diff_nonAudioFiles_ignored', 0, () => {
      const r: ScanDiffResult = computeScanDiff(['a.mp3'], ['a.mp3', 'cover.jpg', 'note.txt', 'b.FLAC']);
      expect(r.added.length).assertEqual(1);
      expect(r.added[0]).assertEqual('b.FLAC');
      expect(r.missing.length).assertEqual(0);
    });

    it('diff_bothEmpty_emptyResult', 0, () => {
      const r: ScanDiffResult = computeScanDiff([], []);
      expect(r.added.length).assertEqual(0);
      expect(r.missing.length).assertEqual(0);
      expect(r.unchanged.length).assertEqual(0);
    });

    it('diff_pathsComparedExactly', 0, () => {
      // 相对路径按字面精确比较(大小写敏感,与文件系统一致)
      const r: ScanDiffResult = computeScanDiff(['A.mp3'], ['a.mp3']);
      expect(r.added.length).assertEqual(1);
      expect(r.added[0]).assertEqual('a.mp3');
      expect(r.missing.length).assertEqual(1);
      expect(r.missing[0]).assertEqual('A.mp3');
    });
  });
}
