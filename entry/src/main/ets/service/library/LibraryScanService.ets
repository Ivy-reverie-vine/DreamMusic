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
        // d.ts:recursion=true 时返回以 '/' 开头的相对路径,归一化
        disk.push(n.startsWith('/') ? n.substring(1) : n);
      });
    }
    const tracks = await store.listTracks();
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
