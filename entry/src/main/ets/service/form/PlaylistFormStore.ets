import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { LibraryStore } from '../library/LibraryStore';
import { Playlist, Track } from '../../model/Entities';
import { PlaylistCardSnapshot, playlistCardSnapshot, PLAYLIST_FORM_NAME } from '../../model/PlaylistCard';

/** 每个 formId 单独持久化目标 ID。曲目/名称始终读取本地库，不缓存另一份歌单事实。 */
export class PlaylistFormStore {
  private static chains: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  private static path(context: common.Context, formId: string): string {
    if (!/^[0-9]+$/.test(formId)) { throw new Error('无效卡片标识'); }
    return context.filesDir + '/playlist-forms/' + formId + '.json';
  }

  static bind(context: common.Context, formId: string, playlistId: number): void {
    const path = PlaylistFormStore.path(context, formId);
    const dir = context.filesDir + '/playlist-forms';
    if (!fileIo.accessSync(dir)) { fileIo.mkdirSync(dir); }
    // 平台重发 onAddForm 时保留原绑定；未指定目标的新卡片默认为本地收藏。
    if (fileIo.accessSync(path)) { return; }
    const id = Number.isSafeInteger(playlistId) && playlistId > 0 ? playlistId : 0;
    PlaylistFormStore.write(context, formId, id);
  }

  private static write(context: common.Context, formId: string, playlistId: number): void {
    const path = PlaylistFormStore.path(context, formId);
    const file = fileIo.openSync(path + '.tmp', fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, JSON.stringify(playlistId)); } finally { fileIo.closeSync(file.fd); }
    fileIo.renameSync(path + '.tmp', path);
  }

  static readId(context: common.Context, formId: string): number {
    const id = JSON.parse(fileIo.readTextSync(PlaylistFormStore.path(context, formId))) as number;
    if (!Number.isSafeInteger(id) || id < 0) { throw new Error('歌单绑定无效'); }
    return id;
  }

  static remove(context: common.Context, formId: string): void {
    const path = PlaylistFormStore.path(context, formId);
    if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
  }

  static binding(snapshot: PlaylistCardSnapshot): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(snapshot);
  }

  static async snapshot(context: common.Context, playlistId: number): Promise<PlaylistCardSnapshot> {
    const store = LibraryStore.getInstance();
    await store.init(context);
    const playlists = await store.listPlaylists();
    const playlist = playlists.find((p: Playlist) => playlistId === 0 ? p.systemReserved : p.id === playlistId);
    if (playlist === undefined) { return playlistCardSnapshot(playlistId, null, []); }
    const ids = await store.listPlaylistTracks(playlist);
    const all = await store.listTracks();
    const byId = new Map<number, Track>();
    all.forEach((track: Track) => byId.set(track.id, track));
    const tracks: Track[] = [];
    ids.forEach((id: number) => { const track = byId.get(id); if (track !== undefined) { tracks.push(track); } });
    return playlistCardSnapshot(playlist.id, playlist, tracks);
  }

  static update(context: common.Context, formId: string): Promise<void> {
    const previous = PlaylistFormStore.chains.get(formId) ?? Promise.resolve();
    const next = previous.catch(() => {}).then(async () => {
      let id: number;
      try { id = PlaylistFormStore.readId(context, formId); } catch (err) { return; }
      let snapshot: PlaylistCardSnapshot;
      try { snapshot = await PlaylistFormStore.snapshot(context, id); } catch (err) {
        snapshot = new PlaylistCardSnapshot();
        snapshot.playlistId = id;
        snapshot.title = '暂时无法读取歌单';
        snapshot.summary = '点按打开应用重试';
      }
      // 异步读取期间移除卡片，不重新创建绑定或继续发布。
      try { if (PlaylistFormStore.readId(context, formId) !== id) { return; } } catch (err) { return; }
      if (id === 0 && snapshot.available) { PlaylistFormStore.write(context, formId, snapshot.playlistId); }
      await formProvider.updateForm(formId, PlaylistFormStore.binding(snapshot));
    }).catch(() => {});
    PlaylistFormStore.chains.set(formId, next);
    next.then(() => { if (PlaylistFormStore.chains.get(formId) === next) { PlaylistFormStore.chains.delete(formId); } });
    return next;
  }

  static async refreshAll(context: common.Context): Promise<void> {
    const forms = await formProvider.getPublishedRunningFormInfos();
    for (const form of forms) {
      if (form.formName === PLAYLIST_FORM_NAME) { await PlaylistFormStore.update(context, form.formId); }
    }
  }
}
