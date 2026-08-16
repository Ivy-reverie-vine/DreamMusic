import { oklchToRgb, ExtractedColors } from '../color/ColorExtract';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 动态主题服务 —— DESIGN.md「取色于景」的唯一 token 落地(issue-00)。
 * 页面一律从这里取色,禁止硬编码颜色。
 * issue-12 修复:默认深色(用户真机反馈浅色白底观感差);三态切换(深/浅/跟随系统)持久化。
 */

const SEED_L = 0.550;
const SEED_C = 0.095;
const SEED_H = 180.0;

const PREF_NAME = 'ivy_prefs';
const KEY_THEME_MODE = 'theme_mode';
const KEY_BG_INDEX = 'bg_index';
const KEY_BG_CUSTOM = 'bg_custom';

/** 主题模式:深色 / 浅色 / 跟随系统 */
export enum ThemeMode {
  DARK = 'DARK',
  LIGHT = 'LIGHT',
  SYSTEM = 'SYSTEM'
}

/** 内置背景图预设(issue-14 定稿:使用用户提供的图片,主题色运行时取色) */
export interface BgPreset {
  res: Resource;
}

export const BG_PRESETS: BgPreset[] = [
  { res: $r('app.media.bg_01') },
  { res: $r('app.media.bg_02') },
  { res: $r('app.media.bg_03') },
  { res: $r('app.media.bg_04') },
  { res: $r('app.media.bg_05') }
];

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

/** '#RRGGBB' 与另一色线性混合,t∈[0,1] */
function mixHex(hex: string, other: string, t: number): string {
  const p = (h: string): number[] => [
    parseInt(h.substring(1, 3), 16),
    parseInt(h.substring(3, 5), 16),
    parseInt(h.substring(5, 7), 16)
  ];
  const a = p(hex);
  const b = p(other);
  const c: number[] = [];
  for (let i = 0; i < 3; i++) {
    c.push(Math.round(a[i] + (b[i] - a[i]) * t));
  }
  return '#' + c.map((v: number) => v.toString(16).toUpperCase().padStart(2, '0')).join('');
}

@Observed
export class ThemeService {
  // DESIGN.md Roles(深浅两套,跟随系统)
  isDark: boolean = true;
  /** 当前主题模式(issue-12:默认深色) */
  mode: ThemeMode = ThemeMode.DARK;
  bg: string = '#0D0F10';        // 近黑底(oklch L≈0.06, C=0)
  ink: string = '#F2F5F6';       // 正文白
  muted: string = '#A8B0B3';     // 弱文字
  trackColor: string = '#33FFFFFF'; // Slider 轨道(深色=白 20%)
  overlayDim: string = '#B0000000'; // 弹层/遮罩半透明黑(code-review 后 token 化)
  transparent: string = '#00000000';
  primary: string = SEED_PRIMARY_HEX;
  secondary: string = SEED_SECONDARY_HEX;
  /**
   * 用于文字/图标的强调色(issue-14 修复:取色后部分字体看不清)。
   * 深色主题自动向白提亮,浅色主题自动向 ink 加深,保证文字对比度。
   */
  primaryText: string = mixHex(SEED_PRIMARY_HEX, '#FFFFFF', 0.38);
  scrimList: number = 0.65;      // 列表页蒙层不透明度(0-1)
  scrimNowPlaying: number = 0.45; // 正在播放页蒙层不透明度(issue-12 起真正启用)
  card: string = '#12FFFFFF';    // 卡片底色(半透明白,叠于蒙层之上,PRD-v1.1)
  barBg: string = '#59000000';   // 玻璃底栏底色(半透明黑)
  /** 播放页按钮固定灰(issue-14 用户定稿:不随取色) */
  controlGray: string = '#8A9096';
  /** 错误/警告文案色(深浅主题均保证可读;timeout 等提示用) */
  errorColor: string = '#FF8A80';
  hasBackground: boolean = false;
  /**
   * 当前背景图源:内置预设为 Resource,自定义背景为 'file://' + 沙箱绝对路径。
   * 自定义背景(阶段 v2 恢复,8/16 用户拍板)与内置预设共用此字段。
   */
  bgSrc: Resource | string | null = null;
  /** 自定义背景图沙箱相对路径(相对 filesDir;'' = 未使用自定义背景,持久化用) */
  bgCustomPath: string = '';
  /** 背景图版本号:切换时 +1,Index 用奇偶分支强制重建 Image 组件(绕开缓存) */
  bgStamp: number = 0;
  /** 当前预设索引,-1 = 无背景 */
  bgPresetIndex: number = -1;

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
      this.card = '#12FFFFFF';
      this.barBg = '#59000000';
      this.controlGray = '#8A9096';
      this.errorColor = '#FF8A80';
      this.primaryText = mixHex(this.primary, '#FFFFFF', 0.38);
    } else {
      this.bg = '#F5F7F8';
      this.ink = '#1B2226';
      this.muted = '#5F6A6E';
      this.trackColor = '#33000000';
      this.card = '#0A000000';
      this.barBg = '#59FFFFFF';
      this.controlGray = '#6B757A';
      this.errorColor = '#C62828';
      this.primaryText = mixHex(this.primary, '#1B2226', 0.22);
    }
  }

  /** 应用主题模式(深/浅/跟随系统);SYSTEM 时按系统深浅实时跟随 */
  applyMode(mode: ThemeMode, systemDark: boolean): void {
    this.mode = mode;
    const dark = mode === ThemeMode.DARK ? true : mode === ThemeMode.LIGHT ? false : systemDark;
    this.setDarkMode(dark);
  }

  /** 持久化主题模式(默认深色) */
  static loadMode(context: common.Context): ThemeMode {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const v = prefs.getSync(KEY_THEME_MODE, ThemeMode.DARK) as string;
      if (v === ThemeMode.LIGHT || v === ThemeMode.SYSTEM || v === ThemeMode.DARK) {
        return v as ThemeMode;
      }
      return ThemeMode.DARK;
    } catch (err) {
      return ThemeMode.DARK;
    }
  }

  static saveMode(context: common.Context, mode: ThemeMode): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.putSync(KEY_THEME_MODE, mode);
      prefs.flush();
    } catch (err) {
      // 持久化失败静默,仅本次会话生效
    }
  }

  /** 应用取色引擎结果(背景图/封面 → ExtractedColors) */
  applyExtracted(primary: string, secondary: string): void {
    this.primary = primary;
    this.secondary = secondary;
    this.primaryText = this.isDark ? mixHex(primary, '#FFFFFF', 0.38) : mixHex(primary, '#1B2226', 0.22);
  }

  /** 回退品牌种子主题(无背景图/无封面) */
  applyDefault(): void {
    this.primary = SEED_PRIMARY_HEX;
    this.secondary = SEED_SECONDARY_HEX;
    this.primaryText = mixHex(SEED_PRIMARY_HEX, '#FFFFFF', 0.38);
    this.hasBackground = false;
  }

  /** 标记存在用户背景图(实际选图与持久化由适配层负责) */
  setHasBackground(has: boolean): void {
    this.hasBackground = has;
  }

  /** 应用内置背景图预设(issue-14 定稿);colors 由调用方取色后传入,缺省不改颜色 */
  applyPresetBg(index: number, colors?: ExtractedColors): void {
    this.bgPresetIndex = index;
    if (index < 0 || index >= BG_PRESETS.length) {
      this.bgSrc = null;
      this.bgCustomPath = '';
      this.bgStamp++;
      this.applyDefault();
      return;
    }
    this.bgSrc = BG_PRESETS[index].res;
    this.bgCustomPath = '';
    if (colors !== undefined) {
      this.applyExtracted(colors.primary, colors.secondary);
    }
    this.hasBackground = true;
    this.bgStamp++;
  }

  /**
   * 应用自定义背景图(阶段 v2 恢复,8/16 用户拍板)。
   * relPath 为沙箱相对路径(持久化);uri 为 'file://' 绝对路径(Image 直接用)。
   * colors 由调用方取色后传入;bgPresetIndex 保留为"恢复默认"时的回退预设。
   */
  applyCustomBg(relPath: string, uri: string, colors?: ExtractedColors): void {
    this.bgCustomPath = relPath;
    this.bgSrc = uri;
    this.hasBackground = true;
    if (colors !== undefined) {
      this.applyExtracted(colors.primary, colors.secondary);
    }
    this.bgStamp++;
  }

  /** 持久化当前背景预设索引 */
  static loadBgIndex(context: common.Context): number {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      return prefs.getSync(KEY_BG_INDEX, -1) as number;
    } catch (err) {
      return -1;
    }
  }

  static saveBgIndex(context: common.Context, index: number): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.putSync(KEY_BG_INDEX, index);
      prefs.flush();
    } catch (err) {
      // 持久化失败静默
    }
  }

  static saveCustomBg(context: common.Context, relPath: string): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.putSync(KEY_BG_CUSTOM, relPath);
      prefs.flush();
    } catch (err) {
      // 持久化失败静默,仅本次会话生效
    }
  }

  /** 彻底清除背景图状态(内部保留,当前无 UI 入口) */
  clearBackground(): void {
    this.bgSrc = null;
    this.bgPresetIndex = -1;
    this.bgCustomPath = '';
    this.hasBackground = false;
    this.bgStamp++;
    this.applyDefault();
  }

  /** '#RRGGBB' → '#AARRGGBB'(opacity ∈ [0,1]) */
  static alpha(hex: string, opacity: number): string {
    const a = Math.max(0.0, Math.min(1.0, opacity));
    const aa = Math.round(a * 255).toString(16).toUpperCase().padStart(2, '0');
    return '#' + aa + hex.substring(1);
  }
}
