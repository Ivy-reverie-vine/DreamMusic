/**
 * 取色引擎(纯逻辑,零 Kit 依赖)——DESIGN.md「取色于景」世界的核心。
 * 契约见 docs/issues/issue-00-ui-design-foundation.md 与 DESIGN.md Colors 节。
 * 可单测接缝 S:像素数组 → ExtractedColors。
 */

export interface Oklch {
  l: number;
  c: number;
  h: number; // 度 [0,360)
}

export interface ExtractedColors {
  primary: string;   // '#RRGGBB' 主强调(经 DESIGN.md 约束钳制)
  secondary: string; // '#RRGGBB' 次强调(与主色色相分离)
}

// DESIGN.md 约束与品牌种子色(唯一真源值)
const SEED_L = 0.550;
const SEED_C = 0.095;
const SEED_H = 180.0;
const MIN_L = 0.42;
const MAX_L = 0.78;
const MAX_C = 0.23;
const MIN_C = 0.02;
const HUE_SEPARATION = 60.0;
const ALPHA_THRESHOLD = 128;

interface Bucket {
  count: number;
  rSum: number;
  gSum: number;
  bSum: number;
}

function clamp01(v: number): number {
  return Math.max(0.0, Math.min(1.0, v));
}

function srgbToLinear(u: number): number {
  return u <= 0.04045 ? u / 12.92 : Math.pow((u + 0.055) / 1.055, 2.4);
}

function linearToSrgb(u: number): number {
  return u <= 0.0031308 ? 12.92 * u : 1.055 * Math.pow(u, 1.0 / 2.4) - 0.055;
}

/** sRGB(0-255)→ OKLCH。与 CSS Color 4 官方示例值对齐。 */
export function rgbToOklch(r: number, g: number, b: number): Oklch {
  const lr = srgbToLinear(r / 255.0);
  const lg = srgbToLinear(g / 255.0);
  const lb = srgbToLinear(b / 255.0);
  const l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb;
  const m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb;
  const s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb;
  const l_ = Math.cbrt(l);
  const m_ = Math.cbrt(m);
  const s_ = Math.cbrt(s);
  const okl = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
  const a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
  const bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
  const c = Math.sqrt(a * a + bb * bb);
  let h = Math.atan2(bb, a) * 180.0 / Math.PI;
  if (h < 0) {
    h += 360.0;
  }
  return { l: okl, c: c, h: h };
}

/** OKLCH → sRGB(0-255)。 */
export function oklchToRgb(l: number, c: number, h: number): number[] {
  if (c < 1e-8) {
    const lin = Math.pow(l, 3.0);
    const ch = Math.round(255.0 * linearToSrgb(clamp01(lin)));
    return [ch, ch, ch];
  }
  const hr = h * Math.PI / 180.0;
  const a = c * Math.cos(hr);
  const b = c * Math.sin(hr);
  const l_ = l + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = l - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = l - 0.0894841775 * a - 1.2914855480 * b;
  const l3 = l_ * l_ * l_;
  const m3 = m_ * m_ * m_;
  const s3 = s_ * s_ * s_;
  const lr = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
  const lg = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
  const lb = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;
  return [
    Math.round(255.0 * clamp01(linearToSrgb(clamp01(lr)))),
    Math.round(255.0 * clamp01(linearToSrgb(clamp01(lg)))),
    Math.round(255.0 * clamp01(linearToSrgb(clamp01(lb))))
  ];
}

function toHex(rgb: number[]): string {
  const hx = (v: number): string => {
    const s = v.toString(16).toUpperCase();
    return s.length === 1 ? '0' + s : s;
  };
  return '#' + hx(rgb[0]) + hx(rgb[1]) + hx(rgb[2]);
}

function hueDistance(h1: number, h2: number): number {
  const d = Math.abs(h1 - h2) % 360.0;
  return d > 180.0 ? 360.0 - d : d;
}

function seedFallback(): ExtractedColors {
  const primary = oklchToRgb(SEED_L, SEED_C, SEED_H);
  const secondary = oklchToRgb(SEED_L, SEED_C, (SEED_H + 120.0) % 360.0);
  return { primary: toHex(primary), secondary: toHex(secondary) };
}

/** 主色钳制:DESIGN.md 蒙层保底规则。无彩→品牌种子色;L∈[0.42,0.78];C≤0.23。 */
function clampPrimary(rgb: number[]): string {
  const ok = rgbToOklch(rgb[0], rgb[1], rgb[2]);
  if (ok.c < MIN_C) {
    return toHex(oklchToRgb(SEED_L, SEED_C, SEED_H));
  }
  const l = Math.max(MIN_L, Math.min(MAX_L, ok.l));
  const c = Math.min(MAX_C, ok.c);
  return toHex(oklchToRgb(l, c, ok.h));
}

/**
 * 从 RGBA 像素缓冲提取强调色对。
 * pixels: RGBA 逐像素;width/height: 图像尺寸。
 */
export function extractColors(pixels: Uint8Array, width: number, height: number): ExtractedColors {
  const total = width * height;
  const buckets = new Map<number, Bucket>();
  for (let i = 0; i < total; i++) {
    const o = i * 4;
    if (o + 3 >= pixels.length) {
      break;
    }
    if (pixels[o + 3] < ALPHA_THRESHOLD) {
      continue; // 忽略透明像素
    }
    const key = (pixels[o] >> 3) | ((pixels[o + 1] >> 3) << 5) | ((pixels[o + 2] >> 3) << 10);
    let bk = buckets.get(key);
    if (bk === undefined) {
      bk = { count: 0, rSum: 0, gSum: 0, bSum: 0 };
      buckets.set(key, bk);
    }
    bk.count++;
    bk.rSum += pixels[o];
    bk.gSum += pixels[o + 1];
    bk.bSum += pixels[o + 2];
  }
  if (buckets.size === 0) {
    return seedFallback(); // 无可取像素
  }
  const sorted: Bucket[] = [];
  buckets.forEach((v: Bucket) => {
    sorted.push(v);
  });
  sorted.sort((x: Bucket, y: Bucket) => y.count - x.count);

  const avg = (bk: Bucket): number[] => {
    return [Math.round(bk.rSum / bk.count), Math.round(bk.gSum / bk.count), Math.round(bk.bSum / bk.count)];
  };

  const domRgb = avg(sorted[0]);
  const domOk = rgbToOklch(domRgb[0], domRgb[1], domRgb[2]);

  // 次强调:取与主色色相分离 ≥60° 的最大簇;若不存在,旋转主色色相 +120°
  let secRgb: number[] | null = null;
  for (let i = 1; i < sorted.length; i++) {
    const candRgb = avg(sorted[i]);
    const candOk = rgbToOklch(candRgb[0], candRgb[1], candRgb[2]);
    if (candOk.c >= MIN_C && hueDistance(candOk.h, domOk.h) >= HUE_SEPARATION) {
      secRgb = candRgb;
      break;
    }
  }
  if (secRgb === null) {
    secRgb = oklchToRgb(domOk.l, domOk.c, (domOk.h + 120.0) % 360.0);
  }

  return {
    primary: clampPrimary(domRgb),
    secondary: toHex(secRgb)
  };
}
