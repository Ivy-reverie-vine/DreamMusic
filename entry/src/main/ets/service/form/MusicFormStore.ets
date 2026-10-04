import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { MusicCardSnapshot, cardSnapshotForDisplay } from '../../model/MusicCard';

/** 跨进程只读展示缓存；播放事实和断点仍只来自 player_state / QueueViewModel。 */
export class MusicFormStore {
  static directory(context: common.Context): string { return context.filesDir + '/music-form'; }

  static save(context: common.Context, snapshot: MusicCardSnapshot): void {
    const dir = MusicFormStore.directory(context);
    if (!fileIo.accessSync(dir)) { fileIo.mkdirSync(dir); }
    const file = fileIo.openSync(dir + '/snapshot.tmp',
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, JSON.stringify(snapshot)); } finally { fileIo.closeSync(file.fd); }
    fileIo.renameSync(dir + '/snapshot.tmp', dir + '/snapshot.json');
  }

  static read(context: common.Context): MusicCardSnapshot {
    try {
      const snapshot = JSON.parse(fileIo.readTextSync(MusicFormStore.directory(context) + '/snapshot.json')) as MusicCardSnapshot;
      if (typeof snapshot.title !== 'string' || typeof snapshot.updatedAt !== 'number') {
        return new MusicCardSnapshot();
      }
      return cardSnapshotForDisplay(snapshot, Date.now());
    } catch (err) { return new MusicCardSnapshot(); }
  }

  static binding(snapshot: MusicCardSnapshot, imageFd: number = -1): formBindingData.FormBindingData {
    const images: Record<string, number> = {};
    // Form Image 以 memory key 判断是否换图；每版文件名必须作为新的 key。
    if (imageFd >= 0) { images[snapshot.coverFile] = imageFd; }
    return formBindingData.createFormBindingData({
      title: snapshot.title, artist: snapshot.artist, status: snapshot.status,
      state: snapshot.state, hasTrack: snapshot.hasTrack, canPlay: snapshot.canPlay,
      accent: snapshot.accent, cover: imageFd >= 0 ? 'memory://' + snapshot.coverFile : '', formImages: images
    });
  }

  static async update(context: common.Context, formId: string, snapshot: MusicCardSnapshot): Promise<void> {
    let file: fileIo.File | null = null;
    try {
      // 文件名只由发布者生成；缺失/回收的封面降级为统一占位。
      if (/^cover-[0-9-]+\.jpg$/.test(snapshot.coverFile)) {
        try { file = fileIo.openSync(MusicFormStore.directory(context) + '/' + snapshot.coverFile,
          fileIo.OpenMode.READ_ONLY); } catch (err) {}
      }
      await formProvider.updateForm(formId, MusicFormStore.binding(snapshot, file === null ? -1 : file.fd));
    } finally {
      if (file !== null) { fileIo.closeSync(file.fd); }
    }
  }
}
