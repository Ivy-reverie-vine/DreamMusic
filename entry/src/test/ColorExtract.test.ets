import { describe, it, expect } from '@ohos/hypium';
import { extractColors, rgbToOklch } from '../main/ets/service/color/ColorExtract';

function makeSolidPixels(r: number, g: number, b: number, count: number): Uint8Array {
  const pixels = new Uint8Array(count * 4);
  for (let i = 0; i < count; i++) {
    const o = i * 4;
    pixels[o] = r;
    pixels[o + 1] = g;
    pixels[o + 2] = b;
    pixels[o + 3] = 255;
  }
  return pixels;
}

function halfHalf(r1: number, g1: number, b1: number, r2: number, g2: number, b2: number): Uint8Array {
  // 8x8 = 64 pixels: first 32 = color1, last 32 = color2
  const half = 32;
  const pixels = new Uint8Array(64 * 4);
  for (let i = 0; i < half; i++) {
    const o = i * 4;
    pixels[o] = r1;
    pixels[o + 1] = g1;
    pixels[o + 2] = b1;
    pixels[o + 3] = 255;
  }
  for (let i = half; i < 64; i++) {
    const o = i * 4;
    pixels[o] = r2;
    pixels[o + 1] = g2;
    pixels[o + 2] = b2;
    pixels[o + 3] = 255;
  }
  return pixels;
}

function parseHex(hex: string): number[] {
  const r = parseInt(hex.substring(1, 3), 16);
  const g = parseInt(hex.substring(3, 5), 16);
  const b = parseInt(hex.substring(5, 7), 16);
  return [r, g, b];
}

function channelClose(actual: string, expected: number[], tol: number): boolean {
  const rgb = parseHex(actual);
  return Math.abs(rgb[0] - expected[0]) <= tol && Math.abs(rgb[1] - expected[1]) <= tol && Math.abs(rgb[2] - expected[2]) <= tol;
}

export default function colorExtractTest() {
  describe('ColorExtract', () => {
    // ---- rgbToOklch 与 CSS Color 4 官方示例值对齐(独立真源) ----
    it('rgbToOklch_redAnchor', 0, () => {
      const ok = rgbToOklch(255, 0, 0);
      expect(ok.l).assertClose(0.628, 0.02);
      expect(ok.c).assertClose(0.258, 0.02);
      expect(ok.h).assertClose(29.2, 1.0);
    });
    it('rgbToOklch_greenAnchor', 0, () => {
      const ok = rgbToOklch(0, 255, 0);
      expect(ok.l).assertClose(0.866, 0.02);
      expect(ok.c).assertClose(0.295, 0.02);
      expect(ok.h).assertClose(142.5, 1.0);
    });
    it('rgbToOklch_blueAnchor', 0, () => {
      const ok = rgbToOklch(0, 0, 255);
      expect(ok.l).assertClose(0.452, 0.02);
      expect(ok.c).assertClose(0.313, 0.02);
      expect(ok.h).assertClose(264.1, 1.0);
    });
    it('rgbToOklch_whiteAndBlack', 0, () => {
      const w = rgbToOklch(255, 255, 255);
      expect(w.l).assertClose(1.0, 0.001);
      expect(w.c <= 0.001).assertTrue();
      const k = rgbToOklch(0, 0, 0);
      expect(k.l <= 0.001).assertTrue();
      expect(k.c <= 0.001).assertTrue();
    });

    // ---- 主色提取:主导色被忠实返回 ----
    it('extract_solidRed_keepsRedHue', 0, () => {
      // 注意:纯红 chroma 0.258 > 0.23 会被 DESIGN.md 约束钳制,断言"仍是红":色相≈29.2 且 R 通道显著领先
      const res = extractColors(makeSolidPixels(255, 0, 0, 64), 8, 8);
      const rgb = parseHex(res.primary);
      const ok = rgbToOklch(rgb[0], rgb[1], rgb[2]);
      expect(Math.abs(ok.h - 29.2) <= 10.0).assertTrue();
      expect(rgb[0] > 100).assertTrue();
      expect(rgb[0] > rgb[1]).assertTrue();
      expect(rgb[1] > rgb[2]).assertTrue();
    });
    it('extract_solidTeal_returnsTeal', 0, () => {
      const res = extractColors(makeSolidPixels(0, 128, 128, 64), 8, 8);
      expect(channelClose(res.primary, [0, 128, 128], 14)).assertTrue();
    });

    // ---- 双色图:主=多数色,次=另一色,且二者不同 ----
    it('extract_halfRedHalfBlue_primaryRedSecondaryBlue', 0, () => {
      const res = extractColors(halfHalf(255, 0, 0, 0, 0, 255), 8, 8);
      // 主色为红(钳制后色相保持 29.2±10),次色为蓝
      const prgb = parseHex(res.primary);
      const pok = rgbToOklch(prgb[0], prgb[1], prgb[2]);
      expect(Math.abs(pok.h - 29.2) <= 10.0).assertTrue();
      expect(channelClose(res.secondary, [0, 0, 255], 25)).assertTrue();
      expect(res.primary === res.secondary).assertFalse();
    });

    // ---- 无彩图(灰)回退品牌铜绿种子色:色相≈180、有彩度 ----
    it('extract_grayImage_fallsBackToSeedTeal', 0, () => {
      const res = extractColors(makeSolidPixels(128, 128, 128, 64), 8, 8);
      const rgb = parseHex(res.primary);
      const ok = rgbToOklch(rgb[0], rgb[1], rgb[2]);
      expect(ok.c > 0.02).assertTrue();
      expect(Math.abs(ok.h - 180.0) <= 10.0).assertTrue();
    });

    // ---- 约束钳制:亮色 L∈[0.42,0.78];霓虹 C≤0.23 ----
    it('extract_brightYellow_lightnessClamped', 0, () => {
      const res = extractColors(makeSolidPixels(255, 255, 0, 64), 8, 8);
      const rgb = parseHex(res.primary);
      const ok = rgbToOklch(rgb[0], rgb[1], rgb[2]);
      expect(ok.l <= 0.78 + 0.01).assertTrue();
      expect(ok.l >= 0.42 - 0.01).assertTrue();
    });
    it('extract_neonGreen_chromaClamped', 0, () => {
      const res = extractColors(makeSolidPixels(0, 255, 0, 64), 8, 8);
      const rgb = parseHex(res.primary);
      const ok = rgbToOklch(rgb[0], rgb[1], rgb[2]);
      expect(ok.c <= 0.23 + 0.01).assertTrue();
    });

    // ---- 透明像素被忽略 ----
    it('extract_transparentPixels_ignored', 0, () => {
      const pixels = new Uint8Array(64 * 4); // 全透明
      for (let i = 0; i < 64; i++) {
        pixels[i * 4 + 3] = 0;
      }
      const res = extractColors(pixels, 8, 8);
      const rgb = parseHex(res.primary);
      const ok = rgbToOklch(rgb[0], rgb[1], rgb[2]);
      // 无可取像素 → 回退种子色
      expect(ok.c > 0.02).assertTrue();
      expect(Math.abs(ok.h - 180.0) <= 10.0).assertTrue();
    });
  });
}
