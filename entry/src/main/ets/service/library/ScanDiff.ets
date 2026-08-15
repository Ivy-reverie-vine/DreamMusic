import { AUDIO_EXT_WHITELIST } from './ImportPlanner';

/**
 * 扫描比对(纯逻辑,零 Kit 依赖)——issue-04 单测接缝。
 * 语义:数据库快照(相对路径) vs 沙箱音乐目录清单(相对路径)。
 * 磁盘侧只统计白名单音频;路径按字面精确比较。
 */

export interface ScanDiffResult {
  /** 目录有、库没有 → 待入库(提元数据) */
  added: string[];
  /** 库有、目录没有 → 文件缺失(标记,不自动删) */
  missing: string[];
  unchanged: string[];
}

function isAudio(rel: string): boolean {
  const dot = rel.lastIndexOf('.');
  if (dot <= 0) {
    return false;
  }
  return AUDIO_EXT_WHITELIST.includes(rel.substring(dot).toLowerCase());
}

export function computeScanDiff(dbPaths: string[], diskPaths: string[]): ScanDiffResult {
  const result: ScanDiffResult = { added: [], missing: [], unchanged: [] };
  const db = new Set<string>();
  dbPaths.forEach((p: string) => {
    db.add(p);
  });
  const disk = new Set<string>();
  diskPaths.forEach((p: string) => {
    if (isAudio(p)) {
      disk.add(p);
    }
  });
  db.forEach((p: string) => {
    if (disk.has(p)) {
      result.unchanged.push(p);
    } else {
      result.missing.push(p);
    }
  });
  disk.forEach((p: string) => {
    if (!db.has(p)) {
      result.added.push(p);
    }
  });
  return result;
}
