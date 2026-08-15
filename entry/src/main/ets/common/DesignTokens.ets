/**
 * 设计 token —— DESIGN.md 视觉系统与 PRD-v1.1 的唯一数值来源。
 * 页面禁止手写数字(颜色除外,颜色只准从 ThemeService 取)。
 * 初值来自 PRD-v1.1-visual-polish.md,真机评审微调后回填 DESIGN.md。
 */

// ---- 字阶(HarmonyOS Sans,dp) ----
export const FONT_DISPLAY = 32;   // 仅正在播放页曲名
export const FONT_TITLE = 20;     // 页面标题
export const FONT_BODY = 15;      // 列表主文本
export const FONT_LABEL = 12;     // 辅助文本
export const FONT_CAPTION = 11;   // 时间码/角标

// ---- 间距(4dp 栅格) ----
export const SPACE_XS = 4;
export const SPACE_SM = 8;
export const SPACE_MD = 12;
export const SPACE_LG = 16;
export const SPACE_XL = 20;       // 页面 padding
export const SPACE_XXL = 24;

// ---- 圆角 ----
export const RADIUS_CARD = 16;
export const RADIUS_CONTROL = 12;
export const RADIUS_CAPSULE = 999;

// ---- 阴影(弥散优先,克制) ----
export const SHADOW_CARD_RADIUS = 20;
export const SHADOW_CARD_COLOR = '#33000000';
export const SHADOW_CARD_OFFSET_Y = 6;
export const SHADOW_GLOW_RADIUS = 48;

// ---- 动效 ----
export const MOTION_VINYL_MS = 550;     // 黑胶翻开
export const MOTION_THEME_FADE_MS = 500; // 切歌取色渐变
export const MOTION_RIPPLE_MS = 300;    // 触点光晕
export const MOTION_PRESS_MS = 150;     // 列表点击反馈

// ---- 封面缩略图 ----
export const COVER_THUMB_SIZE = 44;
export const COVER_THUMB_RADIUS = 11;
