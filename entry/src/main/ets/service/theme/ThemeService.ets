import { oklchToRgb } from '../color/ColorExtract';

/**
 * 动态主题服务 —— DESIGN.md「取色于景」的唯一 token 落地(issue-00)。
 * 页面一律从这里取色,禁止硬编码颜色。
 * 真机能力(背景图选择、ImageKit 读像素)由 ThemeAdapter 注入提取结果。
 */

const SEED_L = 0.550;
const SEED_C = 0.095;
const SEED_H = 180.0;

function toHex(rgb: number[]): string {
  const hx = (v: number): string => {
    const s = Math.max(0, Math.min(255, v)).toString(16).toUpperCase();
    return s.length === 1 ? '0' + s : s;
  };
  return '#' + hx(rgb[0]) + hx(rgb[1]) + hx(rgb[2]);
}

/** 品牌种子色(DESIGN.md fallback): oklch(0.550 0.095 180) */
export const SEED_PRIMARY_HEX: string = toHex(oklchToRgb(SEED_L, SEED_C, SEED_H));
export const SEED_SECONDARY_HEX: string = toHex(oklchToRgb(SEED_L, SEED_C, (SEED_H + 120.0) % 360.0));

@Observed
export class ThemeService {
  // DESIGN.md Roles(深浅两套,跟随系统)
  isDark: boolean = true;
  bg: string = '#0D0F10';        // 近黑底(oklch L≈0.06, C=0)
  ink: string = '#F2F5F6';       // 正文白
  muted: string = '#A8B0B3';     // 弱文字
  trackColor: string = '#33FFFFFF'; // Slider 轨道(深色=白 20%)
  overlayDim: string = '#B0000000'; // 弹层/遮罩半透明黑(code-review 后 token 化)
  transparent: string = '#00000000';
  primary: string = SEED_PRIMARY_HEX;
  secondary: string = SEED_SECONDARY_HEX;
  scrimList: number = 0.65;      // 列表页蒙层不透明度(0-1)
  scrimNowPlaying: number = 0.45;
  hasBackground: boolean = false;

  private static instance: ThemeService | null = null;

  static getInstance(): ThemeService {
    if (ThemeService.instance === null) {
      ThemeService.instance = new ThemeService();
    }
    return ThemeService.instance;
  }

  /** 深浅色切换(跟随系统;深色=默认品牌氛围,浅色=同构浅底) */
  setDarkMode(dark: boolean): void {
    this.isDark = dark;
    if (dark) {
      this.bg = '#0D0F10';
      this.ink = '#F2F5F6';
      this.muted = '#A8B0B3';
      this.trackColor = '#33FFFFFF';
    } else {
      this.bg = '#F5F7F8';
      this.ink = '#1B2226';
      this.muted = '#5F6A6E';
      this.trackColor = '#33000000';
    }
  }

  /** 应用取色引擎结果(背景图/封面 → ExtractedColors) */
  applyExtracted(primary: string, secondary: string): void {
    this.primary = primary;
    this.secondary = secondary;
  }

  /** 回退品牌种子主题(无背景图/无封面) */
  applyDefault(): void {
    this.primary = SEED_PRIMARY_HEX;
    this.secondary = SEED_SECONDARY_HEX;
    this.hasBackground = false;
  }

  /** 标记存在用户背景图(实际选图与持久化由适配层负责) */
  setHasBackground(has: boolean): void {
    this.hasBackground = has;
  }
}
