import { LibraryStore } from '../service/library/LibraryStore';
import { Track, Playlist, PlayHistoryEntry } from '../model/Entities';

/** 歌单/收藏/历史状态容器(issue-09) */
@Observed
export class PlaylistsViewModel {
  playlists: Playlist[] = [];
  selected: Playlist | null = null;
  selectedTracks: Track[] = [];
  historyTracks: Track[] = [];
  statusText: string = '';
  private byIdCache: Map<number, Track> = new Map<number, Track>();

  private store(): LibraryStore {
    return LibraryStore.getInstance();
  }

  private async refreshCache(): Promise<void> {
    const all = await this.store().listTracks();
    this.byIdCache.clear();
    all.forEach((t: Track) => {
      this.byIdCache.set(t.id, t);
    });
  }

  private resolve(ids: number[]): Track[] {
    const out: Track[] = [];
    ids.forEach((id: number) => {
      const t = this.byIdCache.get(id);
      if (t !== undefined) {
        out.push(t);
      }
    });
    return out;
  }

  async load(): Promise<void> {
    await this.refreshCache();
    this.playlists = await this.store().listPlaylists();
    if (this.selected !== null) {
      const cur = this.playlists.find((p: Playlist) => p.id === this.selected!.id);
      if (cur !== undefined) {
        this.selected = cur;
        await this.openPlaylist(cur);
      } else {
        this.selected = null;
        this.selectedTracks = [];
      }
    }
  }

  async openPlaylist(p: Playlist): Promise<void> {
    this.selected = p;
    const ids = await this.store().listPlaylistTracks(p);
    this.selectedTracks = this.resolve(ids);
  }

  async create(name: string): Promise<void> {
    if (name.trim() === '') {
      this.statusText = '歌单名不能为空';
      return;
    }
    await this.store().insertPlaylist(name.trim());
    this.statusText = `已创建「${name.trim()}」`;
    await this.load();
  }

  async rename(id: number, name: string): Promise<void> {
    if (name.trim() === '') {
      return;
    }
    await this.store().renamePlaylist(id, name.trim());
    await this.load();
  }

  async remove(p: Playlist): Promise<void> {
    await this.store().deletePlaylist(p.id);
    if (this.selected !== null && this.selected.id === p.id) {
      this.selected = null;
      this.selectedTracks = [];
    }
    await this.load();
  }

  async addTrackToSelected(trackId: number): Promise<void> {
    if (this.selected === null) {
      return;
    }
    await this.store().addTrackToPlaylist(this.selected.id, trackId);
    await this.openPlaylist(this.selected);
  }

  /** 从音乐库直接把歌加入指定自建歌单 */
  async addToPlaylist(playlistId: number, trackId: number): Promise<void> {
    await this.store().addTrackToPlaylist(playlistId, trackId);
  }

  /** 移除:自建歌单移出;系统保留歌单=取消收藏 */
  async removeTrackFromSelected(trackId: number): Promise<void> {
    if (this.selected === null) {
      return;
    }
    if (this.selected.systemReserved) {
      await this.store().toggleFavorite(trackId);
    } else {
      await this.store().removeTrackFromPlaylist(this.selected.id, trackId);
    }
    await this.openPlaylist(this.selected);
  }

  async toggleFavorite(trackId: number): Promise<boolean> {
    const nowFav = await this.store().toggleFavorite(trackId);
    // 若正查看"我喜欢的音乐",同步刷新
    if (this.selected !== null && this.selected.systemReserved) {
      await this.openPlaylist(this.selected);
    }
    return nowFav;
  }

  async loadHistory(): Promise<void> {
    await this.refreshCache();
    const entries = await this.store().listHistory();
    const ids: number[] = [];
    entries.forEach((e: PlayHistoryEntry) => {
      ids.push(e.trackId);
    });
    this.historyTracks = this.resolve(ids);
  }

  async clearHistory(): Promise<void> {
    await this.store().clearHistory();
    this.historyTracks = [];
  }
}

export const playlistsViewModel: PlaylistsViewModel = new PlaylistsViewModel();
