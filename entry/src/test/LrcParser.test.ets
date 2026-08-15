import { describe, it, expect } from '@ohos/hypium';
import { parseLrc, findActiveLine } from '../main/ets/service/lyrics/LrcParser';

export default function lrcParserTest() {
  describe('LrcParser', () => {
    it('parse_basicLines', 0, () => {
      const lines = parseLrc('[00:01.50]第一句\n[00:03.00]第二句');
      expect(lines.length).assertEqual(2);
      expect(lines[0].timeMs).assertEqual(1500);
      expect(lines[0].text).assertEqual('第一句');
      expect(lines[1].timeMs).assertEqual(3000);
    });

    it('parse_multiTimestampLine', 0, () => {
      const lines = parseLrc('[00:01.00][00:05.00]重复句');
      expect(lines.length).assertEqual(2);
      expect(lines[0].timeMs).assertEqual(1000);
      expect(lines[1].timeMs).assertEqual(5000);
      expect(lines[1].text).assertEqual('重复句');
    });

    it('parse_metadataIgnored', 0, () => {
      const lines = parseLrc('[ti:歌名]\n[ar:歌手]\n[offset:500]\n[00:02.00]正文');
      expect(lines.length).assertEqual(1);
      expect(lines[0].timeMs).assertEqual(2000);
      expect(lines[0].text).assertEqual('正文');
    });

    it('parse_malformedIgnored', 0, () => {
      const lines = parseLrc('没有时间标签\n[xx:yy.zz]坏时间\n[00:03.00]好');
      expect(lines.length).assertEqual(1);
      expect(lines[0].text).assertEqual('好');
    });

    it('parse_integerSeconds', 0, () => {
      const lines = parseLrc('[01:02]整秒');
      expect(lines[0].timeMs).assertEqual(62000);
    });

    it('parse_sortedAscending', 0, () => {
      const lines = parseLrc('[00:05.00]后\n[00:01.00]前');
      expect(lines[0].timeMs).assertEqual(1000);
      expect(lines[1].timeMs).assertEqual(5000);
    });

    it('parse_bomStripped', 0, () => {
      const lines = parseLrc('\uFEFF[00:01.00]首句');
      expect(lines.length).assertEqual(1);
      expect(lines[0].text).assertEqual('首句');
    });

    it('parse_emptyContent', 0, () => {
      const lines = parseLrc('');
      expect(lines.length).assertEqual(0);
    });

    it('findActiveLine_ranges', 0, () => {
      const lines = parseLrc('[00:01.00]A\n[00:02.00]B\n[00:03.00]C');
      expect(findActiveLine(lines, 500)).assertEqual(-1);
      expect(findActiveLine(lines, 1500)).assertEqual(0);
      expect(findActiveLine(lines, 2500)).assertEqual(1);
      expect(findActiveLine(lines, 99999)).assertEqual(2);
      expect(findActiveLine([], 1000)).assertEqual(-1);
    });
  });
}
