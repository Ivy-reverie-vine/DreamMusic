import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { computeScanDiff, ScanDiffResult } from './ScanDiff';
import { ImportService } from './ImportService';
import { MUSIC_DIR } from './ImportPlanner';
import { LibraryStore } from './LibraryStore';
import { Track } from '../../model/Entities';

const DOMAIN = 0x0000;
const TAG = 'LibraryScanService';

export interface ScanReport {
  added: number;
  missing: number;
}

/**
 * 音乐库扫描服务(issue-04,真机验证项):
 * 遍历沙箱 music 目录(fileIo.listFile recursion,前导 '/' 归一化)→ 纯逻辑 diff →
 * 新增文件提元数据入库;消失文件标记 missing(不自动删)。
 */
export class LibraryScanService {
  static async scan(context: common.Context): Promise<ScanReport> {
    const store = LibraryStore.getInstance();
    const musicDir = context.filesDir + '/' + MUSIC_DIR;
    const disk: string[] = [];
    if (fileIo.accessSync(musicDir)) {
      const names = await fileIo.listFile(musicDir, { recursion: true });
      names.forEach((n: string) => {
        // 归一化到"相对 filesDir"坐标系(issue-14 修复):
        // listFile 返回相对 musicDir 的路径(可能带 '/' 前缀),DB 存的是 'music/xxx';
        // 此前不匹配导致启动扫描把所有歌误标"文件缺失"。
        let rel = n.startsWith('/') ? n.substring(1) : n;
        rel = rel.replace(/\\/g, '/');
        if (!rel.startsWith(MUSIC_DIR + '/')) {
          rel = MUSIC_DIR + '/' + rel;
        }
        disk.push(rel);
      });
    }
    let tracks = await store.listTracks();
    // 兼容旧数据:DB path 无 music/ 前缀 → 磁盘上存在带前缀文件则迁移
    for (const t of tracks) {
      if (!t.path.startsWith(MUSIC_DIR + '/') && disk.indexOf(MUSIC_DIR + '/' + t.path) >= 0) {
        await store.renameTrackPath(t.path, MUSIC_DIR + '/' + t.path);
      }
    }
    tracks = await store.listTracks();
    const dbPaths: string[] = [];
    tracks.forEach((t: Track) => {
      dbPaths.push(t.path);
    });
    const diff: ScanDiffResult = computeScanDiff(dbPaths, disk);

    let addedCount = 0;
    for (const rel of diff.added) {
      const abs = musicDir + '/' + rel;
      try {
        const meta = await ImportService.readMetadata(abs);
        meta.path = rel;
        meta.importedAt = Date.now();
        meta.missing = false;
        await store.insertTrack(meta);
        await store.indexTrackMeta(meta);
        addedCount++;
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'scan add %{public}s failed: %{public}s', rel, e.message);
      }
    }
    for (const rel of diff.missing) {
      await store.markMissing(rel);
    }
    // 消失后重现的文件恢复 present(code-review 修复:markPresent 此前未被调用)
    for (const rel of diff.unchanged) {
      await store.markPresent(rel);
    }
    return { added: addedCount, missing: diff.missing.length };
  }
}
