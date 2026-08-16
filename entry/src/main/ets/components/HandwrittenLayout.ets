import { GLYPH_JSON } from '../common/GlyphData';

/**
 * 手写 Logo 布局引擎(阶段 v2.2,纯逻辑零 Kit):
 * 基于 ivy-move-font 的笔迹数据,把文本排成逐笔折线(commands)+ 每笔时长/延迟,
 * 输出可直接喂给 ArkUI Path 的描边动画参数(移植自 D:\Blog\src\components\handwritten.ts)。
 */

interface StrokeData {
  p: number[][];
  d: number;
  a: number;
}

interface GlyphData {
  w: number;
  t: number;
  s: StrokeData[];
}

const DATA: Record<string, GlyphData> = JSON.parse(GLYPH_JSON) as Record<string, GlyphData>;

export interface HandwrittenStroke {
  /** 'M x y L x y ...'(已缩放,单位 vp) */
  commands: string;
  /** 折线点列(已缩放,vp),供 Canvas 逐帧部分绘制 */
  points: number[][];
  /** 平均笔画宽(vp) */
  width: number;
  /** 折线总长(vp),用于 dash 动画 */
  len: number;
  delayMs: number;
  durMs: number;
}

export interface HandwrittenLayout {
  strokes: HandwrittenStroke[];
  width: number;
  height: number;
  totalMs: number;
}

/**
 * 文本 → 逐笔书写布局。
 * @param text 待渲染文本(仅支持 GLYPH_JSON 内字形)
 * @param targetWidth 目标宽度(vp)
 * @param targetDurationMs 总书写时长(ms)
 */
export function layoutHandwritten(text: string, targetWidth: number,
  targetDurationMs: number): HandwrittenLayout {
  let totalT = 0;
  let totalW = 0;
  let minY = Number.MAX_VALUE;
  let maxY = -Number.MAX_VALUE;
  for (let i = 0; i < text.length; i++) {
    const g = DATA[text.charAt(i)];
    if (g === undefined) {
      totalW += 500;
      continue;
    }
    totalT += g.t;
    totalW += g.w;
    for (let j = 0; j < g.s.length; j++) {
      const st = g.s[j];
      for (let k = 0; k < st.p.length; k++) {
        const y = st.p[k][1];
        if (y < minY) {
          minY = y;
        }
        if (y > maxY) {
          maxY = y;
        }
      }
    }
  }
  if (totalT <= 0) {
    totalT = 1;
  }
  const scaleT = targetDurationMs / (totalT * 1000);
  const scaleX = totalW > 0 ? targetWidth / totalW : 1;
  const height = maxY > minY ? maxY - minY : 1000;

  let xOffset = 0;
  let cumTime = 0;
  const strokes: HandwrittenStroke[] = [];
  for (let i = 0; i < text.length; i++) {
    const g = DATA[text.charAt(i)];
    if (g === undefined) {
      xOffset += 500;
      cumTime += 0.3;
      continue;
    }
    for (let j = 0; j < g.s.length; j++) {
      const st = g.s[j];
      let commands = '';
      let len = 0;
      let sumW = 0;
      let prevX = 0;
      let prevY = 0;
      const pts: number[][] = [];
      for (let k = 0; k < st.p.length; k++) {
        const pt = st.p[k];
        const x = (pt[0] + xOffset) * scaleX;
        const y = (pt[1] - minY) * scaleX;
        pts.push([x, y]);
        if (k === 0) {
          commands += 'M' + x.toFixed(2) + ' ' + y.toFixed(2) + ' ';
        } else {
          commands += 'L' + x.toFixed(2) + ' ' + y.toFixed(2) + ' ';
          const dx = x - prevX;
          const dy = y - prevY;
          len += Math.sqrt(dx * dx + dy * dy);
        }
        prevX = x;
        prevY = y;
        sumW += pt[2];
      }
      const avgW = st.p.length > 0 ? sumW / st.p.length : 30;
      // 单点/近零长笔画(如 i 的点):补一段微线段,圆头线帽渲染为圆点,
      // 同时保证 dashArray 长度>0 对 ArkUI Path 有效(与网页 pathLength 行为对齐)
      if (len < 0.5 && st.p.length > 0) {
        const lastPt = st.p[st.p.length - 1];
        const lx = (lastPt[0] + xOffset) * scaleX;
        const ly = (lastPt[1] - minY) * scaleX;
        commands = commands.trim() + ' L' + (lx + 0.6).toFixed(2) + ' ' + ly.toFixed(2);
        len = 0.6;
        pts.push([lx + 0.6, ly]);
      }
      strokes.push({
        commands: commands.trim(),
        points: pts,
        width: avgW * scaleX,
        len: len,
        delayMs: Math.round((cumTime + st.d) * scaleT * 1000),
        durMs: Math.max(50, Math.round(Math.max(st.a, 0.05) * scaleT * 1000))
      });
    }
    xOffset += g.w;
    cumTime += g.t;
  }
  return {
    strokes: strokes,
    width: targetWidth,
    height: height * scaleX,
    totalMs: Math.round(totalT * scaleT * 1000)
  };
}
