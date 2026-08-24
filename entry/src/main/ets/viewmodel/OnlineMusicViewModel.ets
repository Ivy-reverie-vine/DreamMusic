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
    if (song.id > 0) {
      const local = await OnlineDownloadService.findLocal(context, song.id);
      if (local !== null) {
        await queueViewModel.playFromList([local], 0, context);
        return;
      }
    }
    const mediaRef = song.mediaRef !== undefined ? song.mediaRef : '';
    const url = await NetEaseApi.resolveUrl(context, song.id, mediaRef);
    if (url === '') {
      throw new Error('无版权或需要会员,无法播放');
    }
    let coverUrl = song.coverUrl;
    if (coverUrl === '') {
      coverUrl = await NetEaseApi.songDetailCover(context, song.id, mediaRef).catch(() => '');
    }
    const transient: Track = {
      id: song.id > 0 ? -song.id : -1,
      path: 'music/online-stream.mp3',
      title: song.name,
      artist: song.artist,
      album: song.album,
      durationMs: song.durationMs,
      coverPath: '',
      importedAt: Date.now(),
      missing: false,
      neteaseId: song.id > 0 ? song.id : 0,
      streamUrl: url,
      streamCoverUrl: coverUrl,
      mediaRef: mediaRef
    };
    await queueViewModel.playFromList([transient], 0, context);
    if (playerViewModel.errorText !== '') {
      throw new Error(playerViewModel.errorText);
    }
    if (song.id <= 0) {
      return;
    }
    OnlineDownloadService.ensureLocal(context, song, () => {
    }).then((track: Track) => {
      const current = playerViewModel.currentTrack;
      if (current !== null && current.neteaseId === song.id &&
        current.streamUrl !== undefined && current.streamUrl !== '') {
        queueViewModel.swapCurrentWithLocal(track);
      }
    }).catch(() => {
      // 下载失败不打断即时播放；下次点播会重试。
    });
  }
}

export const onlineMusicViewModel: OnlineMusicViewModel = new OnlineMusicViewModel();
