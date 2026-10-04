import { LibraryStore } from '../service/library/LibraryStore';
import { Track, Playlist, PlayHistoryEntry } from '../model/Entities';
import { common } from '@kit.AbilityKit';

/** 歌单/收藏/历史状态容器(issue-09) */
@Observed
export class PlaylistsViewModel {
  playlists: Playlist[] = [];
  selected: Playlist | null = null;
  selectedTracks: Track[] = [];
  historyTracks: Track[] = [];
  statusText: string = '';
  private byIdCache: Map<number, Track> = new Map<number, Track>();
  private openVersion: number = 0;

  cancelOpen(): void { this.openVersion++; }

  async openPlaylistId(id: number, context: common.Context): Promise<void> {
    const version = ++this.openVersion;
    this.selected = null;
    this.selectedTracks = [];
    this.statusText = '正在读取本地歌单';
    try {
      await this.store().init(context);
      if (version !== this.openVersion) { return; }
      const playlists = await this.store().listPlaylists();
      const target = playlists.find((p: Playlist) => id === 0 ? p.systemReserved : p.id === id);
      const all = await this.store().listTracks();
      const ids = target === undefined ? [] : await this.store().listPlaylistTracks(target);
      if (version !== this.openVersion) { return; }
      this.playlists = playlists;
      this.byIdCache.clear();
      all.forEach((track: Track) => this.byIdCache.set(track.id, track));
      if (target === undefined) {
        this.statusText = '该本地歌单已删除，请选择其他歌单';
        return;
      }
      this.selected = target;
      this.selectedTracks = this.resolve(ids);
      this.statusText = '';
    } catch (err) {
      if (version === this.openVersion) { this.statusText = '暂时无法读取本地歌单，请重新打开重试'; }
    }
  }

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
    const version = this.openVersion;
    await this.refreshCache();
    const playlists = await this.store().listPlaylists();
    if (version !== this.openVersion) { return; }
    this.playlists = playlists;
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
    this.cancelOpen();
    this.selected = p;
    const ids = await this.store().listPlaylistTracks(p);
    if (this.selected !== p) { return; }
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
