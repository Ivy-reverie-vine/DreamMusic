import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { formProvider } from '@kit.FormKit';
import { Track } from '../../model/Entities';
import { MusicCardSnapshot, MUSIC_FORM_NAME, CARD_INK, copyMusicCardSnapshot } from '../../model/MusicCard';
import { CoverArtService } from '../cover/CoverArtService';
import { readableText } from '../color/TextContrast';
import { MusicFormStore } from './MusicFormStore';

/** 应用进程发布；没有轮询/定时器，卡片进程不会实例化播放器。 */
export class MusicFormPublisher {
  private context: common.Context;
  private snapshot: MusicCardSnapshot = new MusicCardSnapshot();
  private key: string = '';
  private coverKey: string = '';
  private coverIdentity: string = '';
  private coverVersion: number = 0;
  private coverFailedAt: number = 0;
  private chain: Promise<void> = Promise.resolve();
  private revision: number = 0;
  private disposed: boolean = false;

  constructor(context: common.Context) { this.context = context; }

  sync(track: Track | null, state: string, status: string, canPlay: boolean): void {
    if (this.disposed) { return; }
    const uri = CoverArtService.resolve(this.context, track);
    const identity = CoverArtService.identity(track);
    const coverKey = identity + '|' + uri;
    const key = JSON.stringify([identity, track?.title, track?.artist, state, status, canPlay]);
    const changed = key !== this.key;
    this.key = key;
    this.snapshot.title = track === null ? '还没有播放的音乐' : track.title || '未知歌曲';
    this.snapshot.artist = track === null ? '打开应用，选择一首歌' : track.artist || '未知艺术家';
    this.snapshot.hasTrack = track !== null;
    this.snapshot.state = state;
    this.snapshot.status = track === null ? '暂无歌曲' : status;
    this.snapshot.canPlay = canPlay;
    const coverChanged = coverKey !== this.coverKey;
    if (coverChanged) {
      this.coverKey = coverKey;
      if (identity !== this.coverIdentity) {
        this.snapshot.coverFile = '';
        this.snapshot.accent = CARD_INK;
      }
      this.coverIdentity = identity;
    }
    if (changed || coverChanged) { this.publish(); }
    else if (Date.now() - this.snapshot.updatedAt >= 15000) {
      // 借用播放器已有的进度回调刷新存活时间，不建立卡片刷新任务。
      this.save();
    }
    if (coverChanged || (this.coverFailedAt > 0 && Date.now() - this.coverFailedAt >= 30000)) {
      this.coverFailedAt = 0;
      const version = ++this.coverVersion;
      if (track !== null) { this.loadCover(uri, version).catch(() => {}); }
    }
  }

  private save(): void {
    this.snapshot.updatedAt = Date.now();
    try { MusicFormStore.save(this.context, this.snapshot); } catch (err) {
      // 展示缓存不可写不影响播放；运行中的卡片仍可通过 updateForm 更新。
    }
  }

  private publish(): void {
    this.save();
    const revision = ++this.revision;
    const snapshot = copyMusicCardSnapshot(this.snapshot);
    this.chain = this.chain.then(async () => {
      if (revision !== this.revision) { return; }
      // 平台持有实例清单；不保存跨进程易过期的自建 formId 列表。
      const forms = await formProvider.getPublishedRunningFormInfos();
      for (const form of forms) {
        if (revision !== this.revision) { return; }
        if (form.formName === MUSIC_FORM_NAME) {
          await MusicFormStore.update(this.context, form.formId, snapshot).catch(() => {});
        }
      }
    }).catch(() => {});
  }

  private async loadCover(uri: string, version: number): Promise<void> {
    const service = CoverArtService.getInstance();
    const lease = await service.acquire(this.context, uri, 96);
    let packer: image.ImagePacker | null = null;
    try {
      if (this.disposed || version !== this.coverVersion) { return; }
      if (lease.pixelMap === null) { this.coverFailedAt = Date.now(); return; }
      packer = image.createImagePacker();
      const data = await packer.packing(lease.pixelMap, { format: 'image/jpeg', quality: 85 });
      const colors = lease.placeholder ? null : await service.colors(this.context, uri);
      if (this.disposed || version !== this.coverVersion) { return; }
      const dir = MusicFormStore.directory(this.context);
      if (!fileIo.accessSync(dir)) { fileIo.mkdirSync(dir); }
      const name = 'cover-' + Date.now() + '-' + version + '.jpg';
      const file = fileIo.openSync(dir + '/' + name,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, data); } finally { fileIo.closeSync(file.fd); }
      this.snapshot.coverFile = name;
      this.snapshot.accent = colors === null ? CARD_INK : readableText(colors.primary, true);
      this.coverFailedAt = lease.placeholder && uri !== '' ? Date.now() : 0;
      this.publish();
      // 限定本功能生成的文件；保留当前与上一张，跨进程读取竞争时允许占位回退。
      const files = fileIo.listFileSync(dir).filter((name: string) => /^cover-[0-9-]+\.jpg$/.test(name)).sort();
      for (const old of files.slice(0, Math.max(0, files.length - 2))) {
        try { fileIo.unlinkSync(dir + '/' + old); } catch (err) {}
      }
    } catch (err) { this.coverFailedAt = Date.now(); }
    finally { lease.release(); if (packer !== null) { await packer.release().catch(() => {}); } }
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    this.coverVersion++;
    this.snapshot.state = this.snapshot.hasTrack ? 'paused' : 'idle';
    this.snapshot.canPlay = this.snapshot.hasTrack;
    this.snapshot.status = this.snapshot.hasTrack ? '点按播放，恢复上次音乐' : '暂无歌曲';
    this.publish();
    await this.chain;
  }
}
