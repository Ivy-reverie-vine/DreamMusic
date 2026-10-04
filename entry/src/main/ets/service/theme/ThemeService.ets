import { oklchToRgb, ExtractedColors } from '../color/ColorExtract';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { readableText, LIST_SCRIM, NOW_PLAYING_SCRIM, COVER_GLOW_ALPHA } from '../color/TextContrast';

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

@Observed
export class ThemeService {
  // DESIGN.md Roles(深浅两套,跟随系统)
  isDark: boolean = true;
  /** 当前主题模式(issue-12:默认深色) */
  mode: ThemeMode = ThemeMode.DARK;
  bg: string = '#0D0F10';        // 近黑底(oklch L≈0.06, C=0)
  ink: string = '#F2F5F6';       // 正文白
  muted: string = readableText('#A8B0B3', true); // 辅助文字也有 4.5:1 保底
  trackColor: string = '#33FFFFFF'; // Slider 轨道(深色=白 20%)
  overlayDim: string = '#B0000000'; // 弹层/遮罩半透明黑(code-review 后 token 化)
  transparent: string = '#00000000';
  primary: string = SEED_PRIMARY_HEX;
  secondary: string = SEED_SECONDARY_HEX;
  /** 文字角色通过最终叠加背景范围校验；primary/secondary 保留装饰取色。 */
  primaryText: string = readableText(SEED_PRIMARY_HEX, true);
  secondaryText: string = readableText(SEED_SECONDARY_HEX, true);
  scrimList: number = LIST_SCRIM;
  scrimNowPlaying: number = NOW_PLAYING_SCRIM;
  coverGlowAlpha: number = COVER_GLOW_ALPHA;
  card: string = '#12FFFFFF';    // 卡片底色(半透明白,叠于蒙层之上,PRD-v1.1)
  barBg: string = '#59000000';   // 玻璃底栏底色(半透明黑)
  shadowColor: string = '#33000000'; // 浅色阴影强度纳入最终背景范围
  /** 播放页按钮固定灰(issue-14 用户定稿:不随取色) */
  controlGray: string = '#8A9096';
  /** 错误/警告文案色(深浅主题均保证可读;timeout 等提示用) */
  errorColor: string = readableText('#FF8A80', true);
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
  private backgroundPrimary: string = SEED_PRIMARY_HEX;
  private backgroundSecondary: string = SEED_SECONDARY_HEX;
  private coverRequest: number = 0;
  coverIdentity: string = '';

  beginCoverRequest(): number {
    return ++this.coverRequest;
  }

  isCurrentCoverRequest(request: number, backgroundStamp: number): boolean {
    return request === this.coverRequest && backgroundStamp === this.bgStamp;
  }

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
      this.trackColor = '#33FFFFFF';
      this.card = '#12FFFFFF';
      this.barBg = '#59000000';
      this.shadowColor = '#33000000';
      this.overlayDim = '#B0000000';
      this.controlGray = '#8A9096';
    } else {
      this.bg = '#F5F7F8';
      this.ink = '#1B2226';
      this.trackColor = '#33000000';
      this.card = '#0A000000';
      this.barBg = '#59FFFFFF';
      this.shadowColor = '#14000000';
      this.overlayDim = '#B0FFFFFF';
      this.controlGray = '#6B757A';
    }
    this.refreshTextRoles();
  }

  private refreshTextRoles(): void {
    this.ink = readableText(this.isDark ? '#F2F5F6' : '#1B2226', this.isDark);
    this.muted = readableText(this.isDark ? '#A8B0B3' : '#5F6A6E', this.isDark);
    this.primaryText = readableText(this.primary, this.isDark);
    this.secondaryText = readableText(this.secondary, this.isDark);
    this.errorColor = readableText(this.isDark ? '#FF8A80' : '#C62828', this.isDark);
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
    this.primary = /^#[0-9a-fA-F]{6}$/.test(primary) ? primary : SEED_PRIMARY_HEX;
    this.secondary = /^#[0-9a-fA-F]{6}$/.test(secondary) ? secondary : SEED_SECONDARY_HEX;
    this.refreshTextRoles();
  }

  /** 回退品牌种子主题(无背景图/无封面) */
  applyDefault(): void {
    this.applyExtracted(SEED_PRIMARY_HEX, SEED_SECONDARY_HEX);
  }

  /** 封面缺失/取色失败时恢复背景图配色，保留背景图与当前深浅主题。 */
  restoreBackgroundColors(): void {
    this.applyExtracted(this.backgroundPrimary, this.backgroundSecondary);
  }

  /** 异步背景取色仅可提交到仍然选中的图片。 */
  applyBackgroundColors(colors: ExtractedColors): void {
    this.backgroundPrimary = colors.primary;
    this.backgroundSecondary = colors.secondary;
    this.restoreBackgroundColors();
  }

  /** 标记存在用户背景图(实际选图与持久化由适配层负责) */
  setHasBackground(has: boolean): void {
    this.hasBackground = has;
  }

  /** 应用内置背景图预设；取色前先回退种子色。 */
  applyPresetBg(index: number, colors?: ExtractedColors): void {
    this.bgPresetIndex = index;
    if (index < 0 || index >= BG_PRESETS.length) {
      this.bgSrc = null;
      this.bgCustomPath = '';
      this.bgStamp++;
      this.hasBackground = false;
      this.backgroundPrimary = SEED_PRIMARY_HEX;
      this.backgroundSecondary = SEED_SECONDARY_HEX;
      this.applyDefault();
      return;
    }
    this.bgSrc = BG_PRESETS[index].res;
    this.bgCustomPath = '';
    this.applyBackgroundColors(colors !== undefined ? colors :
      { primary: SEED_PRIMARY_HEX, secondary: SEED_SECONDARY_HEX });
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
    this.applyBackgroundColors(colors !== undefined ? colors :
      { primary: SEED_PRIMARY_HEX, secondary: SEED_SECONDARY_HEX });
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
    this.backgroundPrimary = SEED_PRIMARY_HEX;
    this.backgroundSecondary = SEED_SECONDARY_HEX;
    this.applyDefault();
  }

  /** '#RRGGBB' → '#AARRGGBB'(opacity ∈ [0,1]) */
  static alpha(hex: string, opacity: number): string {
    const a = Math.max(0.0, Math.min(1.0, opacity));
    const aa = Math.round(a * 255).toString(16).toUpperCase().padStart(2, '0');
    return '#' + aa + hex.substring(1);
  }
}
