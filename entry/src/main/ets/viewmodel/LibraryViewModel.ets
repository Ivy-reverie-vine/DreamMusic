import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { LibraryStore } from '../service/library/LibraryStore';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { playlistsViewModel } from './PlaylistsViewModel';
import { queueViewModel } from './QueueViewModel';
import { Track, Album, Artist } from '../model/Entities';

/** 音乐库页状态容器(MVVM,issue-04/09) */
@Observed
export class LibraryViewModel {
  tracks: Track[] = [];
  albums: Album[] = [];
  artists: Artist[] = [];
  favoriteIds: Set<number> = new Set<number>();
  loading: boolean = false;
  statusText: string = '';

  async load(): Promise<void> {
    this.loading = true;
    const store = LibraryStore.getInstance();
    this.tracks = await store.listTracks();
    this.albums = await store.listAlbums();
    this.artists = await store.listArtists();
    const favIds = await store.listFavoritesTrackIds();
    // issue-14 修复:整体赋值新 Set(原地 clear/add 不触发 @Observed 刷新)
    this.favoriteIds = new Set<number>(favIds);
    this.loading = false;
  }

  async toggleFavorite(trackId: number): Promise<void> {
    await playlistsViewModel.toggleFavorite(trackId);
    const favIds = await LibraryStore.getInstance().listFavoritesTrackIds();
    this.favoriteIds = new Set<number>(favIds);
  }

  async rescan(context: common.Context): Promise<void> {
    this.statusText = '扫描中…';
    const report = await LibraryScanService.scan(context);
    await this.load();
    this.statusText = `扫描完成:新增 ${report.added},缺失 ${report.missing}`;
  }

  /** 移除音轨:仅出库,或连同沙箱文件删除 */
  async removeTrack(context: common.Context, track: Track, deleteFile: boolean): Promise<void> {
    const store = LibraryStore.getInstance();
    await store.deleteTrack(track.id);
    // issue-14:删歌后同步清理播放队列,避免残留
    queueViewModel.purgeTrack(track.id);
    if (deleteFile) {
      try {
        fileIo.unlinkSync(context.filesDir + '/' + track.path);
      } catch (err) {
        const e = err as Error;
        this.statusText = '文件删除失败: ' + e.message;
      }
    }
    if (track.album !== '') {
      await store.decrementAlbumCount(track.album);
    }
    if (track.artist !== '') {
      await store.decrementArtistCount(track.artist);
    }
    await this.load();
  }
}
