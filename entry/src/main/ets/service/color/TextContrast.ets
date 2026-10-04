/** sRGB 合成后的最坏背景范围；不以缩略图平均色替代文字背后的像素。 */
export const TEXT_CONTRAST_MIN = 4.5;
export const LIST_SCRIM = 0.86;
export const NOW_PLAYING_SCRIM = 0.80;
export const COVER_GLOW_ALPHA = 41 / 255;
export const LIGHT_SHADOW_ALPHA = 20 / 255;

export interface BackgroundRange {
  min: number;
  max: number;
}

function channels(hex: string): number[] {
  return [parseInt(hex.substring(1, 3), 16), parseInt(hex.substring(3, 5), 16),
    parseInt(hex.substring(5, 7), 16)];
}

function linear(channel: number): number {
  const value = channel / 255;
  return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}

export function relativeLuminance(hex: string): number {
  const rgb = channels(hex);
  return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2]);
}

export function contrastRatio(foreground: string, background: string): number {
  const a = relativeLuminance(foreground);
  const b = relativeLuminance(background);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

/** 各通道的上下界。任意图片/透明像素/裁剪/模糊都位于黑白界内。
 * 列表：最多两层卡片/阴影 + 20% tint；播放页：16% 光晕；底栏朝同主题色合成。
 * tint/光晕以任意颜色计算，覆盖取色渐变的全部中间帧。
 */
export function textBackgroundRange(dark: boolean): BackgroundRange {
  const cardAlpha = dark ? 18 / 255 : 10 / 255;
  const imageExtreme = dark ? 1 - LIST_SCRIM : LIST_SCRIM * Math.pow(1 - LIGHT_SHADOW_ALPHA, 2);
  const cards = dark ? 1 - (1 - imageExtreme) * Math.pow(1 - cardAlpha, 2)
    : imageExtreme * Math.pow(1 - cardAlpha, 2);
  const listExtreme = dark ? cards * 0.8 + 0.2 : cards * 0.8;
  const playingExtreme = dark ? 1 - NOW_PLAYING_SCRIM * (1 - COVER_GLOW_ALPHA)
    : NOW_PLAYING_SCRIM * (1 - COVER_GLOW_ALPHA);
  return dark ? { min: 0, max: Math.max(listExtreme, playingExtreme) }
    : { min: Math.min(listExtreme, playingExtreme), max: 1 };
}

function gray(channel: number): string {
  const value = channel.toString(16).toUpperCase().padStart(2, '0');
  return '#' + value + value + value;
}

/** 对各通道设置保底值，保留色相倾向；通道界保证不同强调色插值仍可读。 */
export function readableText(color: string, dark: boolean): string {
  const range = textBackgroundRange(dark);
  const background = gray(dark ? Math.ceil(range.max * 255) : Math.floor(range.min * 255));
  let limit = dark ? 255 : 0;
  for (let step = 0; step <= 255; step++) {
    const candidate = dark ? step : 255 - step;
    if (contrastRatio(gray(candidate), background) >= TEXT_CONTRAST_MIN + 0.1) {
      limit = candidate;
      break;
    }
  }
  const rgb = channels(/^#[0-9a-fA-F]{6}$/.test(color) ? color : (dark ? '#FFFFFF' : '#000000'));
  return '#' + rgb.map((value: number): string => {
    const adjusted = dark ? Math.max(value, limit) : Math.min(value, limit);
    return adjusted.toString(16).toUpperCase().padStart(2, '0');
  }).join('');
}
