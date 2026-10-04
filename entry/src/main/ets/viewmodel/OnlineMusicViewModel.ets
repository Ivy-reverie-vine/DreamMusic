import { common } from '@kit.AbilityKit';
import {
  OnlineMusicService,
  OnlinePlaylistSummary
} from '../service/network/OnlineMusicService';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { OnlineSong, Track } from '../model/Entities';
import { NetEaseApi } from '../service/network/NetEaseApi';
import { OnlineDownloadService } from '../service/network/OnlineDownloadService';
import { queueViewModel } from './QueueViewModel';
import { playerViewModel } from './PlayerViewModel';
import { ApiError } from '../service/network/ApiClient';
import { PlayerState } from '../model/Playback';

/** 在线歌单/我喜欢状态容器与在线歌曲播放入口。 */
@Observed
export class OnlineMusicViewModel {
  playlists: OnlinePlaylistSummary[] = [];
  selectedPlaylist: OnlinePlaylistSummary | null = null;
  selectedSongs: OnlineSong[] = [];
  likedSongs: OnlineSong[] = [];
  loading: boolean = false;
  statusText: string = '';

  loadCached(context: common.Context): void {
    const cached = OnlineMusicService.cached(context);
    this.playlists = cached.playlists;
    this.likedSongs = cached.likedSongs;
  }

  async prefetch(context: common.Context): Promise<void> {
    this.loadCached(context);
    if (!DreamMusicAuth.isLoggedIn(context) || !DreamMusicAuth.isBound(context)) {
      return;
    }
    try {
      await OnlineMusicService.prefetch(context);
      this.loadCached(context);
    } catch (err) {
      // 预取失败不阻塞登录和本地播放；页面打开时仍可按需重试。
      this.statusText = '在线资料预取失败,打开页面可重试';
    }
  }

  async loadPlaylists(context: common.Context): Promise<void> {
    this.loading = true;
    this.statusText = '';
    try {
      const page = await OnlineMusicService.playlists(context, 0, 30);
      this.playlists = page.playlists;
    } catch (err) {
      this.statusText = (err as Error).message;
    } finally {
      this.loading = false;
    }
  }

  async openPlaylist(context: common.Context, playlist: OnlinePlaylistSummary): Promise<void> {
    this.loading = true;
    this.selectedPlaylist = playlist;
    this.statusText = '';
    try {
      this.selectedSongs = await OnlineMusicService.allPlaylistSongs(context, playlist.id);
    } catch (err) {
      this.statusText = (err as Error).message;
      this.selectedSongs = [];
    } finally {
      this.loading = false;
    }
  }

  async loadLikedSongs(context: common.Context): Promise<void> {
    this.loading = true;
    this.statusText = '';
    try {
      this.likedSongs = await OnlineMusicService.likedSongs(context);
    } catch (err) {
      this.statusText = (err as Error).message;
      this.likedSongs = [];
    } finally {
      this.loading = false;
    }
  }

  async setLiked(context: common.Context, songId: number, liked: boolean): Promise<void> {
    await OnlineMusicService.setLiked(context, songId, liked);
    await this.loadLikedSongs(context);
  }

  /** 在线资料页复用搜索页的即时播放 + 后台入库链路。 */
  async playSong(context: common.Context, song: OnlineSong): Promise<void> {
    const mediaRef = song.mediaRef !== undefined ? song.mediaRef : '';
    const transient: Track = {
      id: song.id > 0 ? -song.id : -1,
      path: 'music/online-stream.mp3', title: song.name, artist: song.artist, album: song.album,
      durationMs: song.durationMs, coverPath: '', importedAt: Date.now(), missing: false,
      neteaseId: song.id > 0 ? song.id : 0, streamUrl: '', streamCoverUrl: song.coverUrl, mediaRef: mediaRef,
      catalogRef: song.catalogRef, playbackRef: song.playbackRef, lyricsRef: song.lyricsRef,
      playbackSource: song.playbackSource, lyricsSource: song.lyricsSource
    };
    const request = playerViewModel.beginTrack(transient, context, (readyRequest: number): void => {
      const expected = playerViewModel.currentTrack;
      if (expected === null || expected.id >= 0) { return; }
      if (song.coverUrl === '') {
        NetEaseApi.songDetailCover(context, song.id, song.catalogRef !== undefined ? song.catalogRef : mediaRef).then((url: string) => {
          if (playerViewModel.isCurrentRequest(readyRequest)) {
            queueViewModel.updateCurrentCover(expected, url);
          }
        }).catch(() => {});
      }
      if (song.id <= 0 || (song.source !== undefined && song.source !== 'api-enhanced') ||
        (expected.playbackRef !== undefined && expected.catalogRef !== expected.playbackRef)) { return; }
      OnlineDownloadService.ensureLocal(context, song, () => {}).then((track: Track) => {
        if (playerViewModel.isCurrentRequest(readyRequest) &&
          playerViewModel.currentTrack !== null && playerViewModel.currentTrack.id < 0) {
          queueViewModel.swapCurrentWithLocal(track);
        }
      }).catch(() => {
        // 下载失败不打断即时播放；下次点播会重试。
      });
    });
    try {
      let local: Track | null = null;
      try {
        if (song.id > 0 && (song.source === undefined || song.source === 'api-enhanced') &&
          (song.playbackRef === undefined || song.playbackRef === song.catalogRef)) {
          local = await OnlineDownloadService.findLocal(context, song.id);
        }
      } catch (err) {
        // 本地查询失败时仍允许统一在线入口；队列选择和恢复操作保持一致。
      }
      if (!playerViewModel.isCurrentRequest(request)) { return; }
      if (local !== null && song.catalogRef !== undefined) {
        // 本地命中只改变播放文件；本次 v2 选择仍展示原目录信息。
        local = {
          id: local.id, path: local.path, title: song.name, artist: song.artist, album: song.album,
          durationMs: local.durationMs, coverPath: song.coverUrl !== '' ? '' : local.coverPath,
          importedAt: local.importedAt, missing: local.missing, neteaseId: local.neteaseId,
          streamCoverUrl: song.coverUrl, mediaRef: song.mediaRef, catalogRef: song.catalogRef,
          playbackRef: song.playbackRef, lyricsRef: song.lyricsRef,
          playbackSource: song.source, lyricsSource: song.lyricsSource
        };
      }
      await queueViewModel.playFromList([local !== null ? local : transient], 0, context, request);
    } catch (err) {
      playerViewModel.failRequest(request, err instanceof ApiError ? err.code : '');
    }
    if (playerViewModel.isCurrentRequest(request) && playerViewModel.state === PlayerState.ERROR) {
      throw new ApiError(playerViewModel.errorCode, playerViewModel.errorText);
    }
  }
}

export const onlineMusicViewModel: OnlineMusicViewModel = new OnlineMusicViewModel();
