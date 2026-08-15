import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { planImport, ImportPlan, AUDIO_EXT_WHITELIST } from '../library/ImportPlanner';
import { LibraryStore } from '../library/LibraryStore';
import { Track } from '../../model/Entities';

const DOMAIN = 0x0000;
const TAG = 'ImportService';
const MUSIC_DIR = 'music';
const COVER_DIR = 'covers';

export type ImportProgressFn = (done: number, total: number) => void;

export interface ImportResult {
  imported: number;
  duplicates: number;
  skipped: number;
}

/**
 * 导入服务适配层(issue-03,真机验证项):
 * 选择器(多文件/文件夹)→ 规划(纯逻辑)→ 复制进沙箱 → AVMetadataExtractor 元数据+封面 → 入库。
 * API 对照 SDK d.ts 核实:DocumentViewPicker/DocumentSelectMode.FOLDER、
 * fs.listFile(recursion)、createAVMetadataExtractor/fdSrc/fetchMetadata/fetchAlbumCover、ImagePacker。
 */
export class ImportService {
  /** 多选音频文件(白名单在系统选择器与规划器双重过滤) */
  static async pickAudioFiles(context: common.Context): Promise<string[]> {
    const docPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 100;
    options.fileSuffixFilters = AUDIO_EXT_WHITELIST;
    return await docPicker.select(options);
  }

  /** 选择文件夹并递归收集白名单音频(真机验证:目录 URI 的 listFile 行为) */
  static async pickAudioFolder(context: common.Context): Promise<string[]> {
    const docPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    const uris = await docPicker.select(options);
    const out: string[] = [];
    for (const dirUri of uris) {
      const names = await fileIo.listFile(dirUri, { recursion: true });
      names.forEach((name: string) => {
        const dot = name.lastIndexOf('.');
        if (dot <= 0) {
          return;
        }
        const ext = name.substring(dot).toLowerCase();
        if (AUDIO_EXT_WHITELIST.includes(ext)) {
          out.push(dirUri + '/' + name);
        }
      });
    }
    return out;
  }

  /** 执行导入;onProgress 回调 (done, total),total 为规划后待导入数 */
  static async importSources(context: common.Context, sources: string[],
    onProgress: ImportProgressFn): Promise<ImportResult> {
    const store = LibraryStore.getInstance();
    const tracks = await store.listTracks();
    const existing: string[] = [];
    tracks.forEach((t: Track) => {
      existing.push(t.path);
    });
    const plan: ImportPlan = planImport(sources, existing);
    const result: ImportResult = { imported: 0, duplicates: plan.duplicates.length, skipped: plan.skipped.length };
    const total = plan.items.length;
    let done = 0;
    for (const item of plan.items) {
      try {
        const absPath = ImportService.copyToSandbox(context, item.source, item.destRelative);
        const meta = await ImportService.readMetadata(absPath);
        const coverRelative = await ImportService.extractCover(context, absPath);
        const track: Track = {
          id: 0,
          path: item.destRelative,
          title: meta.title,
          artist: meta.artist,
          album: meta.album,
          durationMs: meta.durationMs,
          coverPath: coverRelative,
          importedAt: Date.now(),
          missing: false
        };
        await store.insertTrack(track);
        if (meta.title !== '' && meta.artist !== '') {
          await store.upsertAlbum(meta.album, meta.artist);
          await store.upsertArtist(meta.artist);
        }
        result.imported++;
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'import %{public}s failed: %{public}s', item.source, e.message);
      }
      done++;
      onProgress(done, total);
    }
    return result;
  }

  private static copyToSandbox(context: common.Context, source: string, destRelative: string): string {
    const abs = context.filesDir + '/' + destRelative;
    const dir = abs.substring(0, abs.lastIndexOf('/'));
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    fileIo.copyFileSync(source, abs);
    return abs;
  }

  /** 读取音轨元数据(扫描与导入共用) */
  static async readMetadata(absPath: string): Promise<Track> {
    const stat = fileIo.statSync(absPath);
    const file = fileIo.openSync(absPath, fileIo.OpenMode.READ_ONLY);
    try {
      const extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
      const md = await extractor.fetchMetadata();
      const track: Track = {
        id: 0,
        path: '',
        title: md.title !== undefined && md.title !== '' ? md.title : '',
        artist: md.artist !== undefined && md.artist !== '' ? md.artist : '',
        album: md.album !== undefined && md.album !== '' ? md.album : '',
        durationMs: typeof md.duration === 'number' ? md.duration : 0,
        coverPath: '',
        importedAt: 0,
        missing: false
      };
      extractor.release().catch(() => {
      });
      return track;
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  /** 提取封面并打包为 JPEG 存沙箱,返回相对路径;失败返回空串(封面非必需) */
  private static async extractCover(context: common.Context, absPath: string): Promise<string> {
    try {
      const stat = fileIo.statSync(absPath);
      const file = fileIo.openSync(absPath, fileIo.OpenMode.READ_ONLY);
      let cover = '';
      try {
        const extractor = await media.createAVMetadataExtractor();
        extractor.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
        const pm = await extractor.fetchAlbumCover();
        const packer = image.createImagePacker();
        const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 90 };
        const data = await packer.packing(pm, packOpts);
        const coverDir = context.filesDir + '/' + COVER_DIR;
        if (!fileIo.accessSync(coverDir)) {
          fileIo.mkdirSync(coverDir);
        }
        const base = absPath.substring(absPath.lastIndexOf('/') + 1);
        const coverName = base.substring(0, base.lastIndexOf('.')) + '.jpg';
        const coverFile = fileIo.openSync(coverDir + '/' + coverName, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        fileIo.writeSync(coverFile.fd, data);
        fileIo.closeSync(coverFile.fd);
        cover = COVER_DIR + '/' + coverName;
        extractor.release().catch(() => {
        });
      } finally {
        fileIo.closeSync(file.fd);
      }
      return cover;
    } catch (err) {
      // 无封面/打包失败:静默降级,不影响导入
      return '';
    }
  }
}
