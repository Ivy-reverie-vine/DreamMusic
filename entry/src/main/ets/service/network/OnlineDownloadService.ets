import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiClient } from './ApiClient';
import { NetEaseApi } from './NetEaseApi';
import { LibraryStore } from '../library/LibraryStore';
import { Track, OnlineSong } from '../../model/Entities';
import { parseYrc, formatLrc } from '../lyrics/LrcParser';

const DOMAIN = 0x0000;
const TAG = 'OnlineDownloadService';
const MUSIC_DIR = 'music';
const COVER_DIR = 'covers';

export type DownloadProgressFn = (pct: number) => void;

/**
 * 在线音轨下载入库(阶段 v2,8/16 用户拍板:自建播放器歌曲必须存本地):
 * 网易云 id 去重 → /song/url/v1(standard)下载音频 → 封面 → 歌词 → 入库(与本地导入同域)。
 */
export class OnlineDownloadService {
  /** 查询已入库且文件可用的本地音轨(流式即播前先查,避免重复下载;文件损坏视为未下载) */
  static async findLocal(context: common.Context, neteaseId: number): Promise<Track | null> {
    const t = await LibraryStore.getInstance().getTrackByNeteaseId(neteaseId);
    if (t !== null && OnlineDownloadService.fileUsable(context, t)) {
      // 文件在但封面/歌词缺失 → 后台补齐(8/16 自愈,不用重下)
      OnlineDownloadService.repairMeta(context, t).catch(() => {
      });
      return t;
    }
    return null;
  }

  /** 补齐缺失的封面/歌词(失败静默,不影响播放) */
  private static async repairMeta(context: common.Context, t: Track): Promise<void> {
    const store = LibraryStore.getInstance();
    if (t.coverPath === '') {
      try {
        const cover = await NetEaseApi.songDetailCover(context, t.neteaseId);
        if (cover !== '') {
          const rel = COVER_DIR + '/' + t.neteaseId + '.jpg';
          await ApiClient.download(cover, context.filesDir + '/' + rel, () => {
          });
          await store.updateTrackCover(t.id, rel);
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'cover repair failed: %{public}s', (err as Error).message);
      }
    }
    const lrcAbs = context.filesDir + '/' + MUSIC_DIR + '/' + t.neteaseId + '.lrc';
    try {
      if (!fileIo.accessSync(lrcAbs)) {
        const text = await NetEaseApi.lyric(context, t.neteaseId);
        if (text !== '') {
          const f = fileIo.openSync(lrcAbs,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
          try {
            fileIo.writeSync(f.fd, text);
          } finally {
            fileIo.closeSync(f.fd);
          }
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'lyric repair failed: %{public}s', (err as Error).message);
    }
  }

  /** 已入库(去重)直接返回;否则下载音频+封面+歌词并入库 */
  static async ensureLocal(context: common.Context, song: OnlineSong,
    onProgress: DownloadProgressFn): Promise<Track> {
    const store = LibraryStore.getInstance();
    const existing = await store.getTrackByNeteaseId(song.id);
    // 去重命中:文件存在且非空才直接复用;损坏/空文件删除记录重下(8/16 修复)
    if (existing !== null && OnlineDownloadService.fileUsable(context, existing)) {
      onProgress(100);
      return existing;
    }
    if (existing !== null) {
      await store.deleteTrack(existing.id);
    }
    const url = await NetEaseApi.resolveUrl(context, song.id);
    if (url === '') {
      throw new Error('无版权或需要会员,无法下载');
    }
    const relPath = MUSIC_DIR + '/' + song.id + OnlineDownloadService.extOf(url);
    onProgress(0);
    await ApiClient.download(url, context.filesDir + '/' + relPath, onProgress);
    const coverRel = await OnlineDownloadService.downloadCover(context, song);
    await OnlineDownloadService.downloadLyric(context, song);
    const track: Track = {
      id: 0,
      path: relPath,
      title: song.name,
      artist: song.artist,
      album: song.album,
      durationMs: song.durationMs,
      coverPath: coverRel,
      importedAt: Date.now(),
      missing: false,
      neteaseId: song.id
    };
    await store.insertTrack(track);
    await store.indexTrackMeta(track);
    onProgress(100);
    return track;
  }

  /** 音轨文件存在且非空(去重复用前校验,避免空文件进 AVPlayer) */
  private static fileUsable(context: common.Context, t: Track): boolean {
    try {
      const abs = context.filesDir + '/' + t.path;
      if (!fileIo.accessSync(abs)) {
        return false;
      }
      const st = fileIo.statSync(abs);
      return st.size > 0;
    } catch (err) {
      return false;
    }
  }

  /** 从直链取扩展名(去 query;未知/无扩展名兜底 .mp3) */
  private static extOf(url: string): string {
    let path = url;
    const q = path.indexOf('?');
    if (q >= 0) {
      path = path.substring(0, q);
    }
    const dot = path.lastIndexOf('.');
    if (dot >= 0) {
      const ext = path.substring(dot).toLowerCase();
      if (ext.length <= 6) {
        return ext;
      }
    }
    return '.mp3';
  }

  /** 封面落盘 covers/<id>.jpg(非必需,失败静默) */
  private static async downloadCover(context: common.Context, song: OnlineSong): Promise<string> {
    let coverUrl = song.coverUrl;
    if (coverUrl === '') {
      // 搜索结果未带封面 → /song/detail 兜底(8/16 修复:搜索 picUrl 可能缺失)
      coverUrl = await NetEaseApi.songDetailCover(context, song.id).catch(() => '');
    }
    if (coverUrl === '') {
      return '';
    }
    try {
      const dir = context.filesDir + '/' + COVER_DIR;
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
      }
      const rel = COVER_DIR + '/' + song.id + '.jpg';
      await ApiClient.download(coverUrl, context.filesDir + '/' + rel, () => {
      });
      return rel;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cover download failed: %{public}s', (err as Error).message);
      return '';
    }
  }

  /** 歌词落盘 music/<id>.lrc(与音频同目录同名,现有 LrcLoader 直接读取;非必需,失败静默) */
  private static async downloadLyric(context: common.Context, song: OnlineSong): Promise<void> {
    try {
      const raw = await NetEaseApi.lyricRaw(context, song.id);
      let text = raw.lrc;
      if (text === '') {
        // 新版接口可能只返回 yrc(逐字)→ 转成标准 LRC 落盘(阶段 v2.3)
        const yrcLines = parseYrc(raw.yrc);
        if (yrcLines.length > 0) {
          text = formatLrc(yrcLines);
        }
      }
      if (text === '') {
        return;
      }
      const dir = context.filesDir + '/' + MUSIC_DIR;
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const rel = context.filesDir + '/' + MUSIC_DIR + '/' + song.id + '.lrc';
      const f = fileIo.openSync(rel,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(f.fd, text);
      } finally {
        fileIo.closeSync(f.fd);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'lyric download failed: %{public}s', (err as Error).message);
    }
  }
}
