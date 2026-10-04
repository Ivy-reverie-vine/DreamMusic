// 主机端读取实际 ArkTS 逻辑；独立计算最终 sRGB 合成及 WCAG 对比度。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8')
    .replace(/^import .+;\r?\n/gm, '').replace(/^@Observed\r?\n/gm, '').replace(/^export /gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { $r: name => name, ...dependencies });
}
const contrast = load('service/color/TextContrast.ets',
  ['readableText', 'contrastRatio', 'LIST_SCRIM', 'NOW_PLAYING_SCRIM', 'COVER_GLOW_ALPHA']);
const extract = load('service/color/ColorExtract.ets', ['oklchToRgb', 'extractColors']);
const { ThemeService, ThemeMode } = load('service/theme/ThemeService.ets',
  ['ThemeService', 'ThemeMode'], { ...contrast, ...extract });
const pending = [];
const CoverArtService = {
  identity(track) { return track.coverPath || track.streamCoverUrl || ''; },
  resolve(_ctx, track) { return track.coverPath || track.streamCoverUrl || ''; },
  getInstance() { return { colors(_ctx, uri) {
    return uri === '' ? Promise.resolve(null) : new Promise((resolve, reject) => pending.push({ resolve, reject }));
  } }; }
};
const { BackgroundAdapter } = load('service/theme/BackgroundAdapter.ets', ['BackgroundAdapter'],
  { ThemeService, CoverArtService, ...extract });

// 独立真源：标准黑白 21:1 和 WCAG 典型失败色。
const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
const luminance = color => color.map(v => v / 255).map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
  .reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
const ratio = (a, b) => (Math.max(luminance(a), luminance(b)) + 0.05) / (Math.min(luminance(a), luminance(b)) + 0.05);
const blend = (front, back, alpha) => back.map((v, i) => v * (1 - alpha) + front[i] * alpha);
const alpha = v => Math.round(v * 255) / 255;
assert.equal(contrast.contrastRatio('#FFFFFF', '#000000'), 21);
assert.ok(ratio(rgb('#777777'), rgb('#FFFFFF')) < 4.5);

const colors = ['#000000', '#FFFFFF', '#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF', '#00FFFF', '#808080'];
const roles = ['ink', 'muted', 'primaryText', 'secondaryText', 'errorColor'];
let checks = 0;
const minima = {};
function check(theme, background, label) {
  for (const role of roles) {
    const value = ratio(rgb(theme[role]), background);
    assert.ok(value >= 4.5, `${label}/${role}: ${value}`);
    minima[role] = Math.min(minima[role] ?? Infinity, value);
    checks++;
  }
}
function surfaces(theme, pixel, tint) {
  const neutral = theme.isDark ? [0, 0, 0] : [255, 255, 255];
  const card = theme.isDark ? [255, 255, 255] : [0, 0, 0];
  const cardAlpha = theme.isDark ? 18 / 255 : 10 / 255;
  const rawPage = blend(neutral, pixel, theme.scrimList);
  const page = theme.isDark ? rawPage : blend([0, 0, 0], blend([0, 0, 0], rawPage, 20 / 255), 20 / 255);
  const oneCard = blend(card, page, cardAlpha);
  const twoCards = blend(card, oneCard, cardAlpha);
  const playing = blend(tint, blend(neutral, pixel, theme.scrimNowPlaying), alpha(theme.coverGlowAlpha));
  const bar = blend(neutral, page, 89 / 255);
  return [page, oneCard, twoCards, blend(tint, twoCards, 0.2), playing,
    blend(tint, bar, alpha(0.14)), rgb(theme.bg), blend(card, rgb(theme.bg), cardAlpha),
    blend(neutral, page, 176 / 255), blend(rgb(theme.bg), pixel, alpha(0.95))];
}

for (const dark of [true, false]) {
  const theme = new ThemeService();
  theme.applyMode(ThemeMode.SYSTEM, dark);
  for (const color of colors) {
    theme.applyExtracted(color, color);
    // 16^3 个像素，包含极亮/极暗、高饱和及复杂图片中的不同区域。
    for (let r = 0; r <= 255; r += 17) {
      for (let g = 0; g <= 255; g += 17) {
        for (let b = 0; b <= 255; b += 17) {
          for (const tint of [[0, 0, 0], [255, 255, 255]]) {
            for (const background of surfaces(theme, [r, g, b], tint)) {
              check(theme, background, `${dark}/${color}/${r},${g},${b}`);
            }
          }
        }
      }
    }
  }
  // 所有角色色的插值帧也须通过；装饰主色按任意黑白极端取上界。
  for (const from of colors) {
    theme.applyExtracted(from, from);
    const start = roles.map(role => rgb(theme[role]));
    for (const to of colors) {
      theme.applyExtracted(to, to);
      const finish = roles.map(role => rgb(theme[role]));
      for (let frame = 0; frame <= 10; frame++) {
        for (const pixel of [[0, 0, 0], [255, 255, 255]]) {
          for (const tint of [[0, 0, 0], [255, 255, 255]]) {
            for (const background of surfaces(theme, pixel, tint)) {
              for (let i = 0; i < roles.length; i++) {
                assert.ok(ratio(blend(finish[i], start[i], frame / 10), background) >= 4.5);
              }
            }
          }
        }
      }
    }
  }
  theme.applyCustomBg('bg.jpg', 'file:///bg.jpg', { primary: '#00FF00', secondary: '#FF0000' });
  theme.applyExtracted('#0000FF', '#FFFF00');
  theme.restoreBackgroundColors();
  assert.equal(theme.primary, '#00FF00');
  assert.equal(theme.hasBackground, true);
  theme.applyPresetBg(0); // 新背景的取色尚未完成/失败。
  assert.notEqual(theme.primary, '#00FF00');
  theme.applyExtracted('#FF00FF', '#00FFFF');
  theme.clearBackground();
  assert.equal(theme.bgSrc, null);
  assert.equal(theme.hasBackground, false);
  check(theme, rgb(theme.bg), 'clear/no image');
  theme.applyMode(ThemeMode.SYSTEM, !dark);
  check(theme, rgb(theme.bg), 'system switch');
  theme.applyExtracted('invalid', '');
  check(theme, rgb(theme.bg), 'invalid extraction');
}

// 主机 Kit 替身：快速切歌、无封面、失败、背景移除后的迟到结果。
const theme = new ThemeService();
const ctx = { filesDir: '/sandbox' };
theme.applyCustomBg('background.jpg', 'file:///background.jpg', { primary: '#00FF00', secondary: '#FF0000' });
const old = BackgroundAdapter.applyCoverColors(ctx, theme, { coverPath: 'old.jpg' });
await BackgroundAdapter.applyCoverColors(ctx, theme, { coverPath: '' });
pending.shift().resolve({ primary: '#0000FF', secondary: '#FFFF00' });
await old;
assert.equal(theme.primary, '#00FF00');
const failed = BackgroundAdapter.applyCoverColors(ctx, theme, { coverPath: 'failed.jpg' });
pending.shift().reject(new Error('decode failed'));
await failed;
assert.equal(theme.primary, '#00FF00');
const stale = BackgroundAdapter.applyCoverColors(ctx, theme, { coverPath: 'stale.jpg' });
theme.clearBackground();
const seed = theme.primary;
pending.shift().resolve({ primary: '#0000FF', secondary: '#FFFF00' });
await stale;
assert.equal(theme.primary, seed);
console.log(`PASS: ${checks} final-surface contrast checks; interpolation, system mode, fallbacks and stale cover results.`);
console.log('Minimum calculated ratios:', Object.fromEntries(Object.entries(minima).map(([key, value]) => [key, value.toFixed(3)])));
