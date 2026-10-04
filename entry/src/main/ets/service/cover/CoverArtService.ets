import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { Track } from '../../model/Entities';
import { extractColors, ExtractedColors } from '../color/ColorExtract';

const MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024;
const MAX_DISK_BYTES = 32 * 1024 * 1024;
const MAX_IDLE_BYTES = 8 * 1024 * 1024;
const MAX_IDLE_ENTRIES = 12;
const FAILURE_RETRY_MS = 30000;

interface CoverPixels {
  pixelMap: image.PixelMap | null;
  placeholder: boolean;
}

class CoverEntry {
  key: string;
  size: number;
  users: number = 0;
  touched: number = Date.now();
  failedAt: number = 0;
  retired: boolean = false;
  pixels: CoverPixels | null = null;
  pending: Promise<CoverPixels>;

  constructor(key: string, size: number, pending: Promise<CoverPixels>) {
    this.key = key;
    this.size = size;
    this.pending = pending;
  }
}

/** 借用期间禁止直接 release PixelMap；页面和 AVSession 提交完成后归还 lease。 */
export class CoverLease {
  pixelMap: image.PixelMap | null;
  placeholder: boolean;
  private returned: boolean = false;
  private entry: CoverEntry;
  private owner: CoverArtService;

  constructor(owner: CoverArtService, entry: CoverEntry, pixels: CoverPixels) {
    this.owner = owner;
    this.entry = entry;
    this.pixelMap = pixels.pixelMap;
    this.placeholder = pixels.placeholder;
  }

  release(): void {
    if (!this.returned) {
      this.returned = true;
      this.owner.returnEntry(this.entry);
    }
  }
}

/** 四个入口和取色共用：本地优先、在线落盘、尺寸分档、请求合并、引用计数。 */
export class CoverArtService {
  private static instance: CoverArtService = new CoverArtService();
  private entries: Map<string, CoverEntry> = new Map<string, CoverEntry>();
  private downloads: Map<string, Promise<string>> = new Map<string, Promise<string>>();

  static getInstance(): CoverArtService {
    return CoverArtService.instance;
  }

  static resolve(context: common.Context, track: Track | null): string {
    if (track === null) {
      return '';
    }
    if (track.coverPath !== '') {
      const path = context.filesDir + '/' + track.coverPath;
      try {
        if (fileIo.accessSync(path)) {
          return 'file://' + path;
        }
      } catch (err) {
        // 缺失文件继续尝试瞬态在线封面；不影响音频。
      }
    }
    return track.streamCoverUrl !== undefined ? track.streamCoverUrl : '';
  }

  static identity(track: Track | null): string {
    if (track === null) {
      return '';
    }
    if (track.mediaRef !== undefined && track.mediaRef !== '') {
      return track.mediaRef;
    }
    return track.neteaseId > 0 ? 'netease:' + track.neteaseId : 'local:' + track.path;
  }

  private version(uri: string): string {
    if (uri.startsWith('file://')) {
      try {
        const stat = fileIo.statSync(uri.substring(7));
        return uri + '|' + stat.size + '|' + stat.mtime;
      } catch (err) {
        return uri + '|missing';
      }
    }
    return uri;
  }

  async acquire(context: common.Context, uri: string, requestedSize: number): Promise<CoverLease> {
    const size = requestedSize <= 64 ? 64 : requestedSize <= 96 ? 96 : 512;
    const key = context.filesDir + '|' + this.version(uri) + '|' + size;
    let entry = this.entries.get(key);
    if (entry !== undefined && entry.users === 0 && entry.failedAt > 0 &&
      Date.now() - entry.failedAt >= FAILURE_RETRY_MS) {
      this.retire(entry);
      entry = undefined;
    }
    if (entry === undefined) {
      entry = new CoverEntry(key, size, this.load(context, uri, size));
      this.entries.set(key, entry);
    }
    // await 前占用，防止同图并发等待期间被淘汰。
    entry.users++;
    entry.touched = Date.now();
    const pixels = await entry.pending;
    entry.pixels = pixels;
    if (pixels.placeholder && uri !== '' && entry.failedAt === 0) {
      entry.failedAt = Date.now();
    }
    this.trim();
    return new CoverLease(this, entry, pixels);
  }

  returnEntry(entry: CoverEntry): void {
    entry.users = Math.max(0, entry.users - 1);
    entry.touched = Date.now();
    if (entry.retired && entry.users === 0) {
      this.releasePixels(entry);
    }
    this.trim();
  }

  clear(): void {
    const entries: CoverEntry[] = Array.from(this.entries.values());
    entries.forEach((entry: CoverEntry) => this.retire(entry));
  }

  private releasePixels(entry: CoverEntry): void {
    const pixels = entry.pixels;
    entry.pixels = null;
    if (pixels !== null && pixels.pixelMap !== null) {
      pixels.pixelMap.release().catch(() => {});
    }
  }

  private retire(entry: CoverEntry): void {
    entry.retired = true;
    if (this.entries.get(entry.key) === entry) {
      this.entries.delete(entry.key);
    }
    if (entry.users === 0) {
      this.releasePixels(entry);
    }
  }

  private trim(): void {
    const idle: CoverEntry[] = [];
    let bytes = 0;
    this.entries.forEach((entry: CoverEntry) => {
      if (entry.users === 0) {
        idle.push(entry);
        bytes += entry.size * entry.size * 4;
      }
    });
    idle.sort((a: CoverEntry, b: CoverEntry) => a.touched - b.touched);
    while (idle.length > MAX_IDLE_ENTRIES || bytes > MAX_IDLE_BYTES) {
      const entry = idle.shift();
      if (entry === undefined) {
        break;
      }
      bytes -= entry.size * entry.size * 4;
      this.retire(entry);
    }
  }

  private async decode(source: image.ImageSource, size: number): Promise<image.PixelMap> {
    try {
      return await source.createPixelMap({ desiredSize: { width: size, height: size },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    } finally {
      await source.release().catch(() => {});
    }
  }

  private async load(context: common.Context, uri: string, size: number): Promise<CoverPixels> {
    if (uri !== '') {
      try {
        const path = uri.startsWith('http://') || uri.startsWith('https://')
          ? await this.onlineFile(context, uri) : uri.startsWith('file://') ? uri.substring(7) : uri;
        const pm = await this.decode(image.createImageSource(path), size);
        return { pixelMap: pm, placeholder: false };
      } catch (err) {
        // 解码/下载失败统一占位；损坏的网络缓存不永久留存。
        if (uri.startsWith('http://') || uri.startsWith('https://')) {
          this.removeDiskEntry(context, uri);
        }
      }
    }
    try {
      const data = await context.resourceManager.getMediaContent($r('app.media.cover_placeholder'));
      const pm = await this.decode(image.createImageSource(data.buffer as ArrayBuffer), size);
      return { pixelMap: pm, placeholder: true };
    } catch (err) {
      return { pixelMap: null, placeholder: true };
    }
  }

  async colors(context: common.Context, uri: string): Promise<ExtractedColors | null> {
    const lease = await this.acquire(context, uri, 64);
    try {
      if (lease.placeholder || lease.pixelMap === null) {
        return null;
      }
      const info = await lease.pixelMap.getImageInfo();
      const data = new ArrayBuffer(info.size.width * info.size.height * 4);
      await lease.pixelMap.readPixelsToBuffer(data);
      return extractColors(new Uint8Array(data), info.size.width, info.size.height);
    } finally {
      lease.release();
    }
  }

  private diskBase(context: common.Context, uri: string): string {
    // 两个独立 32 位 hash；sidecar 再核对完整 URL，碰撞不会返回别的封面。
    let a = 2166136261;
    let b = 5381;
    for (let i = 0; i < uri.length; i++) {
      a = Math.imul(a ^ uri.charCodeAt(i), 16777619);
      b = Math.imul(b, 33) ^ uri.charCodeAt(i);
    }
    return context.cacheDir + '/cover-art/' + (a >>> 0).toString(16) + (b >>> 0).toString(16);
  }

  private removeDiskEntry(context: common.Context, uri: string): void {
    const base = this.diskBase(context, uri);
    try {
      if (fileIo.readTextSync(base + '.url') !== uri) {
        return;
      }
      fileIo.unlinkSync(base + '.img');
      fileIo.unlinkSync(base + '.url');
    } catch (err) {
      // OS 可能已清除 cacheDir。
    }
  }

  private async onlineFile(context: common.Context, uri: string): Promise<string> {
    const key = context.cacheDir + '|' + uri;
    const pending = this.downloads.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const task = this.download(context, uri);
    this.downloads.set(key, task);
    try {
      return await task;
    } finally {
      this.downloads.delete(key);
    }
  }

  private async download(context: common.Context, uri: string): Promise<string> {
    const base = this.diskBase(context, uri);
    const path = base + '.img';
    try {
      if (fileIo.accessSync(path) && fileIo.readTextSync(base + '.url') === uri &&
        fileIo.statSync(path).size > 0) {
        return path;
      }
    } catch (err) {
      // 缓存不存在/不完整时重新请求该封面 URL；不带账户凭据。
    }
    const client = http.createHttp();
    try {
      const response = await client.request(uri, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000,
        readTimeout: 8000,
        maxLimit: MAX_DOWNLOAD_BYTES,
        usingCache: false
      });
      const data = response.result;
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(data instanceof ArrayBuffer) || data.byteLength === 0 || data.byteLength > MAX_DOWNLOAD_BYTES) {
        throw new Error('Cover download failed');
      }
      const dir = context.cacheDir + '/cover-art';
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
      }
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, data);
      } finally {
        fileIo.closeSync(file.fd);
      }
      const sidecar = fileIo.openSync(base + '.url',
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(sidecar.fd, uri);
      } finally {
        fileIo.closeSync(sidecar.fd);
      }
      this.trimDisk(context, path);
      return path;
    } finally {
      client.destroy();
    }
  }

  private trimDisk(context: common.Context, keep: string): void {
    try {
      const dir = context.cacheDir + '/cover-art';
      const paths: string[] = fileIo.listFileSync(dir).filter((name: string) => name.endsWith('.img'))
        .map((name: string) => dir + '/' + name);
      paths.sort((a: string, b: string) => fileIo.statSync(a).mtime - fileIo.statSync(b).mtime);
      let bytes = 0;
      paths.forEach((path: string) => { bytes += fileIo.statSync(path).size; });
      let count = paths.length;
      for (const path of paths) {
        if (bytes <= MAX_DISK_BYTES && count <= 32) {
          break;
        }
        if (path !== keep) {
          bytes -= fileIo.statSync(path).size;
          count--;
          fileIo.unlinkSync(path);
          const sidecar = path.substring(0, path.length - 4) + '.url';
          if (fileIo.accessSync(sidecar)) {
            fileIo.unlinkSync(sidecar);
          }
        }
      }
    } catch (err) {
      // 缓存清理失败不影响解码或音频。
    }
  }
}
