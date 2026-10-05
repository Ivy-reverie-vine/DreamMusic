import { common } from '@kit.AbilityKit';
import {
  OnlineMusicService,
  OnlinePlaylistSummary
} from '../service/network/OnlineMusicService';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { OnlineSong, Track } from '../model/Entities';
import { createOnlineTrack, canDownloadNetEase } from '../model/OnlineTrackIdentity';
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
  async playSong(context: common.Context, song: OnlineSong, automatic: boolean = false,
    sourceOptions: OnlineSong[] = []): Promise<void> {
    const mediaRef = song.mediaRef !== undefined ? song.mediaRef : '';
    const transient = createOnlineTrack(song);
    transient.sourceSearchSession = song.automaticSearchSession;
    transient.sourceOptions = sourceOptions.slice();
    if (!automatic) { transient.automaticSearchSession = undefined; }
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
      if (!canDownloadNetEase(expected)) { return; }
      // Capture the resolved audio before any later source change or metadata update.
      const audio: Track = {
        id: expected.id, path: expected.path, title: expected.title, artist: expected.artist,
        album: expected.album, durationMs: expected.durationMs, coverPath: expected.coverPath,
        importedAt: expected.importedAt, missing: expected.missing, neteaseId: expected.neteaseId,
        streamUrl: expected.streamUrl, streamCoverUrl: expected.streamCoverUrl, mediaRef: expected.mediaRef,
        audioIntegrity: expected.audioIntegrity,
        catalogRef: expected.catalogRef, playbackRef: expected.playbackRef, lyricsRef: expected.lyricsRef,
        playbackSource: expected.playbackSource, lyricsSource: expected.lyricsSource
      };
      const playbackRef = expected.playbackRef !== undefined ? expected.playbackRef : '';
      const streamUrl = expected.streamUrl !== undefined ? expected.streamUrl : '';
      const downloadSong: OnlineSong = {
        id: song.id, name: song.name, artist: song.artist, album: song.album,
        coverUrl: song.coverUrl, durationMs: song.durationMs, mediaRef: song.mediaRef,
        source: song.source, sourceId: song.sourceId,
        catalogRef: expected.catalogRef, playbackRef: expected.playbackRef,
        lyricsRef: expected.lyricsRef, playbackSource: expected.playbackSource, lyricsSource: expected.lyricsSource
      };
      OnlineDownloadService.ensureLocal(context, downloadSong, () => {}, audio).then((track: Track) => {
        queueViewModel.swapCurrentWithLocal(track, expected, readyRequest, playbackRef, streamUrl);
      }).catch(() => {
        // 下载失败不打断即时播放；下次点播会重试。
      });
    });
    queueViewModel.selectFromList([transient], 0, context, request);
    try {
      const ref = transient.playbackRef !== undefined ? transient.playbackRef : '';
      const resolution = await NetEaseApi.resolvePlayback(context, transient.neteaseId, ref,
        transient.automaticSearchSession ?? '', (cancel: () => void): void => { playerViewModel.setResolutionCancel(request, cancel); });
      if (!playerViewModel.isCurrentRequest(request)) { return; }
      if (transient.catalogRef !== undefined && transient.catalogRef !== '' &&
        resolution.catalogRef !== transient.catalogRef) {
        throw new ApiError('IDENTITY_MISMATCH', '播放目录身份不一致');
      }
      transient.audioIntegrity = resolution.audioIntegrity;
      transient.playbackOutcome = resolution.playback;
      if (resolution.playback !== undefined && resolution.playback.status !== 'success') {
        throw new ApiError('PLAYBACK_' + resolution.playback.status.toUpperCase(), '暂无可靠完整版音频');
      }
      if (resolution.url === '') { throw new ApiError('EMPTY_URL', '暂无可播放音频'); }
      if (resolution.audioIntegrity?.status !== 'full') {
        const status = resolution.audioIntegrity?.status ?? 'unknown';
        throw new ApiError('AUDIO_' + status.toUpperCase(), '暂无可靠完整版音频');
      }
      transient.playbackRef = resolution.playbackRef;
      transient.lyricsRef = resolution.lyricsRef;
      transient.playbackSource = resolution.playbackSource;
      transient.lyricsSource = resolution.lyricsSource;
      transient.streamUrl = resolution.url;
      let local: Track | null = null;
      try {
        if (canDownloadNetEase(transient)) {
          local = await OnlineDownloadService.findLocal(context, transient.neteaseId);
        }
      } catch (err) {
        // 本地查询失败时仍允许统一在线入口；队列选择和恢复操作保持一致。
      }
      if (!playerViewModel.isCurrentRequest(request)) { return; }
      if (local !== null) {
        // 本地命中只改变播放文件；本次 v2 选择仍展示原目录信息。
        local = {
          id: local.id, path: local.path, title: song.name, artist: song.artist, album: song.album,
          durationMs: local.durationMs, coverPath: song.coverUrl !== '' ? '' : local.coverPath,
          importedAt: local.importedAt, missing: local.missing, neteaseId: local.neteaseId,
          streamCoverUrl: song.coverUrl, mediaRef: song.mediaRef, catalogRef: transient.catalogRef,
          audioIntegrity: transient.audioIntegrity,
          playbackRef: transient.playbackRef, lyricsRef: transient.lyricsRef,
          playbackSource: transient.playbackSource, lyricsSource: transient.lyricsSource,
          sourceSearchSession: transient.sourceSearchSession, sourceOptions: transient.sourceOptions,
          automaticSearchSession: transient.automaticSearchSession, playbackOutcome: transient.playbackOutcome
        };
      }
      await queueViewModel.playFromList([local !== null ? local : transient], 0, context, request, resolution);
    } catch (err) {
      playerViewModel.failRequest(request, err instanceof ApiError ? err.code : '');
    }
    if (playerViewModel.isCurrentRequest(request) && playerViewModel.state === PlayerState.ERROR) {
      throw new ApiError(playerViewModel.errorCode, playerViewModel.errorText);
    }
  }
}

export const onlineMusicViewModel: OnlineMusicViewModel = new OnlineMusicViewModel();
