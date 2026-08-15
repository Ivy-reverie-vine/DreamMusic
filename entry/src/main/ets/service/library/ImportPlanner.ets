/**
 * 导入规划器(纯逻辑,零 Kit 依赖)——issue-03 单测接缝。
 * 职责:格式白名单过滤、非法文件名字符清洗、按沙箱相对路径去重与批内重名消解。
 * 契约:输入源 URI 列表 + 已存在相对路径集合 → 导入计划。
 */

export interface ImportItem {
  /** 源 URI/路径(供复制适配层使用) */
  source: string;
  /** 小写扩展名,含点,如 '.mp3' */
  ext: string;
  /** 目标沙箱相对路径(相对 filesDir),如 'music/song.mp3' */
  destRelative: string;
}

export interface ImportPlan {
  items: ImportItem[];
  /** 不支持的格式被拒绝的源 */
  skipped: string[];
  /** 相对路径已存在(与现有库重复)的源 */
  duplicates: string[];
}

/** PRD 决策 #3:MP3 / AAC(M4A) / FLAC / WAV */
export const AUDIO_EXT_WHITELIST: string[] = ['.mp3', '.m4a', '.aac', '.flac', '.wav'];

/** 沙箱音乐根目录(相对 filesDir);导入与扫描必须一致(code-review 修复) */
export const MUSIC_DIR = 'music';

function basename(p: string): string {
  const slash = Math.max(p.lastIndexOf('/'), p.lastIndexOf('\\'));
  return slash >= 0 ? p.substring(slash + 1) : p;
}

function extOf(p: string): string {
  const b = basename(p);
  const dot = b.lastIndexOf('.');
  if (dot <= 0) {
    return '';
  }
  return b.substring(dot).toLowerCase();
}

/** 清洗文件名中的非法字符(沙箱路径安全) */
function sanitize(name: string): string {
  return name.replace(/[\\/:*?"<>|]/g, '_');
}

export function planImport(sources: string[], existingPaths: string[]): ImportPlan {
  const plan: ImportPlan = { items: [], skipped: [], duplicates: [] };
  const existing = new Set<string>();
  const used = new Set<string>();
  existingPaths.forEach((p: string) => {
    existing.add(p);
    used.add(p);
  });

  for (const src of sources) {
    const ext = extOf(src);
    if (!AUDIO_EXT_WHITELIST.includes(ext)) {
      plan.skipped.push(src);
      continue;
    }
    const base = sanitize(basename(src));
    const stem = base.substring(0, base.length - ext.length);
    // 与现有库重复 → 跳过;与批内已分配重名 → 追加序号(比较含 music/ 前缀的完整相对路径)
    const fullBase = MUSIC_DIR + '/' + base;
    if (existing.has(fullBase)) {
      plan.duplicates.push(src);
      continue;
    }
    let dest = MUSIC_DIR + '/' + base;
    let n = 1;
    while (used.has(dest)) {
      dest = MUSIC_DIR + '/' + stem + ' (' + n + ')' + ext;
      n++;
    }
    used.add(dest);
    plan.items.push({ source: src, ext: ext, destRelative: dest });
  }
  return plan;
}
