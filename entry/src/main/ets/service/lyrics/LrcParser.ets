/**
 * LRC 歌词解析(纯逻辑,零 Kit 依赖)——issue-08 单测接缝。
 * 支持:[mm:ss.xx] / [mm:ss] 时间标签、一行多时间标签、元数据标签忽略、乱行跳过、BOM 剥离。
 */

export interface LyricLine {
  timeMs: number;
  text: string;
}

const TIME_TAG = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;

function parseTagTime(tag: string): number {
  // tag 形如 "[mm:ss.xx]"
  const m = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/.exec(tag);
  if (m === null) {
    return -1;
  }
  const minutes = parseInt(m[1], 10);
  const seconds = parseInt(m[2], 10);
  let frac = 0;
  if (m[3] !== undefined) {
    const raw = m[3];
    const digits = raw.length === 1 ? parseInt(raw, 10) * 100
      : raw.length === 2 ? parseInt(raw, 10) * 10 : parseInt(raw, 10);
    frac = digits;
  }
  return minutes * 60000 + seconds * 1000 + frac;
}

export function parseLrc(content: string): LyricLine[] {
  const out: LyricLine[] = [];
  if (content.length === 0) {
    return out;
  }
  let text = content;
  // BOM 剥离
  if (text.charCodeAt(0) === 0xFEFF) {
    text = text.substring(1);
  }
  const lines = text.split(/\r\n|\n|\r/);
  for (const line of lines) {
    if (line.length === 0) {
      continue;
    }
    const tags: string[] = [];
    let rest = line;
    let m = TIME_TAG.exec(rest);
    while (m !== null) {
      tags.push(m[0]);
      rest = rest.substring(m.index + m[0].length);
      TIME_TAG.lastIndex = 0;
      m = TIME_TAG.exec(rest);
    }
    // 元数据标签或完全无时间标签的行跳过
    if (tags.length === 0) {
      continue;
    }
    const body = rest.trim();
    for (const tag of tags) {
      const t = parseTagTime(tag);
      if (t >= 0) {
        out.push({ timeMs: t, text: body });
      }
    }
  }
  out.sort((a: LyricLine, b: LyricLine) => a.timeMs - b.timeMs);
  return out;
}

/** 当前应高亮的行索引:最后一个 timeMs <= positionMs 的行;-1 表示尚未到第一句 */
export function findActiveLine(lines: LyricLine[], positionMs: number): number {
  if (lines.length === 0) {
    return -1;
  }
  let result = -1;
  let lo = 0;
  let hi = lines.length - 1;
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (lines[mid].timeMs <= positionMs) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return result;
}
