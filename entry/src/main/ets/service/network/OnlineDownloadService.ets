import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiClient } from './ApiClient';
import { NetEaseApi } from './NetEaseApi';
import { LibraryStore } from '../library/LibraryStore';
import { Track, OnlineSong } from '../../model/Entities';
import { canDownloadNetEase } from '../../model/OnlineTrackIdentity';
import { parseYrc, formatLrc } from '../lyrics/LrcParser';

const DOMAIN = 0x0000;
const TAG = 'OnlineDownloadService';
const MUSIC_DIR = 'music';
const COVER_DIR = 'covers';

export type DownloadProgressFn = (pct: number) => void;

/**
 * 在线音轨下载入库：
 * 普通播放 URL 下载到沙箱 → 补齐封面与歌词 → 同一事务语义下写入音乐库。
 * 下载前确保父目录存在；否则新安装且音乐库为空时，文件无法创建，后续也无记录可恢复。
 */
export class OnlineDownloadService {
  private static pending: Map<string, Promise<Track>> = new Map<string, Promise<Track>>();
  /** 查询已入库且文件可用的本地音轨；命中后后台补齐缺失的封面/歌词。 */
  static async findLocal(context: common.Context, neteaseId: number): Promise<Track | null> {
    const track = await LibraryStore.getInstance().getTrackByNeteaseId(neteaseId);
    if (track !== null && OnlineDownloadService.fileUsable(context, track)) {
      OnlineDownloadService.repairMeta(context, track).catch(() => {
      });
      return track;
    }
    return null;
  }

  /** 已入库则直接复用；否则下载音频、封面、歌词，最后写入本地音乐库。 */
  static async ensureLocal(context: common.Context, song: OnlineSong,
    onProgress: DownloadProgressFn, audio: Track): Promise<Track> {
    if (!canDownloadNetEase(audio) || audio.neteaseId !== song.id ||
      audio.streamUrl === undefined || audio.streamUrl === '') {
      throw new Error('当前音频不能进入网易下载入库');
    }
    // Repeated selections share the file/SQLite job, but keep separate queue owners.
    const key = context.filesDir + '/' + song.id;
    let task = OnlineDownloadService.pending.get(key);
    if (task === undefined) {
      task = OnlineDownloadService.downloadLocal(context, song, onProgress, audio);
      OnlineDownloadService.pending.set(key, task);
    }
    try {
      const track = await task;
      onProgress(100);
      return track;
    } finally {
      if (OnlineDownloadService.pending.get(key) === task) { OnlineDownloadService.pending.delete(key); }
    }
  }

  private static async downloadLocal(context: common.Context, song: OnlineSong,
    onProgress: DownloadProgressFn, audio: Track): Promise<Track> {
    // Use the exact playback result, never re-resolve the catalog's numeric ID.
    const url = audio.streamUrl ?? '';
    const store = LibraryStore.getInstance();
    const existing = await store.getTrackByNeteaseId(song.id);
    if (existing !== null && OnlineDownloadService.fileUsable(context, existing)) {
      await OnlineDownloadService.repairMeta(context, existing);
      onProgress(100);
      return existing;
    }
    if (existing !== null) {
      await store.deleteTrack(existing.id);
    }

    const relPath = MUSIC_DIR + '/' + song.id + OnlineDownloadService.extOf(url);
    OnlineDownloadService.ensureDir(context.filesDir + '/' + MUSIC_DIR);
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
    const id = await store.insertTrack(track);
    if (id <= 0) {
      throw new Error('下载完成但写入音乐库失败');
    }
    track.id = id;
    await store.indexTrackMeta(track);
    onProgress(100);
    return track;
  }

  /** 已入库文件存在且非空，避免空文件进入播放器。 */
  private static fileUsable(context: common.Context, track: Track): boolean {
    try {
      const abs = context.filesDir + '/' + track.path;
      return fileIo.accessSync(abs) && fileIo.statSync(abs).size > 0;
    } catch (err) {
      return false;
    }
  }

  /** 从播放 URL 得到安全扩展名；未知时按 MP3 保存。 */
  private static extOf(url: string): string {
    const queryIndex = url.indexOf('?');
    const path = queryIndex >= 0 ? url.substring(0, queryIndex) : url;
    const dot = path.lastIndexOf('.');
    if (dot >= 0) {
      const ext = path.substring(dot).toLowerCase();
      if (ext.length <= 6) {
        return ext;
      }
    }
    return '.mp3';
  }

  private static ensureDir(absDir: string): void {
    if (!fileIo.accessSync(absDir)) {
      fileIo.mkdirSync(absDir, true);
    }
  }

  /** 封面落盘 covers/<songId>.jpg；封面失败不阻断音轨入库。 */
  private static async downloadCover(context: common.Context, song: OnlineSong): Promise<string> {
    let coverUrl = song.coverUrl;
    if (coverUrl === '') {
      coverUrl = await NetEaseApi.songDetailCover(context, song.id,
        song.catalogRef !== undefined ? song.catalogRef : '').catch(() => '');
    }
    if (coverUrl === '') {
      return '';
    }
    try {
      OnlineDownloadService.ensureDir(context.filesDir + '/' + COVER_DIR);
      const rel = COVER_DIR + '/' + song.id + '.jpg';
      await ApiClient.download(coverUrl, context.filesDir + '/' + rel, () => {
      });
      return rel;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cover download failed: %{public}s', (err as Error).message);
      return '';
    }
  }

  /** 歌词落盘 music/<songId>.lrc；lrc 缺失时把 yrc 转换为 LRC。 */
  private static async downloadLyric(context: common.Context, song: OnlineSong): Promise<void> {
    try {
      const payload = await NetEaseApi.lyricRaw(context, song.id,
        song.lyricsRef !== undefined ? song.lyricsRef : '');
      let text = payload.lrc;
      if (text === '' && payload.yrc !== '') {
        const lines = parseYrc(payload.yrc);
        if (lines.length > 0) {
          text = formatLrc(lines);
        }
      }
      if (text === '') {
        return;
      }
      OnlineDownloadService.ensureDir(context.filesDir + '/' + MUSIC_DIR);
      const abs = context.filesDir + '/' + MUSIC_DIR + '/' + song.id + '.lrc';
      const file = fileIo.openSync(abs,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'lyric download failed: %{public}s', (err as Error).message);
    }
  }

  /** 已存在下载曲的资源自愈。 */
  private static async repairMeta(context: common.Context, track: Track): Promise<void> {
    const store = LibraryStore.getInstance();
    if (track.coverPath === '') {
      try {
        const coverUrl = await NetEaseApi.songDetailCover(context, track.neteaseId);
        if (coverUrl !== '') {
          OnlineDownloadService.ensureDir(context.filesDir + '/' + COVER_DIR);
          const rel = COVER_DIR + '/' + track.neteaseId + '.jpg';
          await ApiClient.download(coverUrl, context.filesDir + '/' + rel, () => {
          });
          await store.updateTrackCover(track.id, rel);
          track.coverPath = rel;
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'cover repair failed: %{public}s', (err as Error).message);
      }
    }

    const lrcAbs = context.filesDir + '/' + MUSIC_DIR + '/' + track.neteaseId + '.lrc';
    try {
      if (!fileIo.accessSync(lrcAbs)) {
        const song: OnlineSong = {
          id: track.neteaseId,
          name: track.title,
          artist: track.artist,
          album: track.album,
          coverUrl: '',
          durationMs: track.durationMs
        };
        await OnlineDownloadService.downloadLyric(context, song);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'lyric repair failed: %{public}s', (err as Error).message);
    }
  }
}
