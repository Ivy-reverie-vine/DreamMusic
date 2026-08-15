import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { extractColors } from '../color/ColorExtract';
import { ThemeService } from './ThemeService';
import { Track } from '../../model/Entities';

const DOMAIN = 0x0000;
const TAG = 'BackgroundAdapter';
const BG_DIR = 'background';
const BG_FILE = 'background_bg';

interface ExtractedPair {
  primary: string;
  secondary: string;
}

/**
 * 背景图适配层(issue-00,真机验证项):
 * PhotoViewPicker 选图 → 复制进沙箱 → ImageKit 缩小读像素 → 取色引擎 → 主题服务。
 * API 均已对照 SDK d.ts 核实(@ohos.file.picker / @ohos.multimedia.image / @ohos.file.fs)。
 * 真机验证点:选择器弹出、URI 复制、readPixelsToBuffer 的像素格式(RGBA_8888)。
 */
export class BackgroundAdapter {
  static async pickAndApply(context: common.Context, theme: ThemeService): Promise<boolean> {
    const photoPicker = new picker.PhotoViewPicker();
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    try {
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        return false;
      }
      const uri: string = result.photoUris[0];
      const destPath: string = BackgroundAdapter.copyToSandbox(context, uri);
      const colors = await BackgroundAdapter.extractFromFile(destPath);
      theme.applyExtracted(colors.primary, colors.secondary);
      theme.bgImagePath = BG_DIR + '/' + destPath.substring(destPath.lastIndexOf('/') + 1);
      theme.setHasBackground(true);
      return true;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'pickAndApply failed: %{public}s', e.message);
      return false;
    }
  }

  private static copyToSandbox(context: common.Context, uri: string): string {
    const dir = context.filesDir + '/' + BG_DIR;
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
    // 保留原扩展名,便于 ImageSource 解码
    let ext = '';
    const dot = uri.lastIndexOf('.');
    if (dot >= 0 && dot > uri.lastIndexOf('/')) {
      ext = uri.substring(dot);
      if (ext.length > 8) {
        ext = '';
      }
    }
    const dest = dir + '/' + BG_FILE + ext;
    fileIo.copyFileSync(uri, dest);
    return dest;
  }

  /** 重启恢复背景图与取色(issue-00 AC「重启后保持」;真机验证) */
  static async restoreIfPresent(context: common.Context, theme: ThemeService): Promise<boolean> {
    const dir = context.filesDir + '/' + BG_DIR;
    try {
      if (!fileIo.accessSync(dir)) {
        return false;
      }
      const names = await fileIo.listFile(dir);
      for (const n of names) {
        if (n.startsWith(BG_FILE)) {
          const path = dir + '/' + n;
          const colors = await BackgroundAdapter.extractFromFile(path);
          theme.applyExtracted(colors.primary, colors.secondary);
          theme.bgImagePath = BG_DIR + '/' + n;
          theme.setHasBackground(true);
          return true;
        }
      }
      return false;
    } catch (err) {
      return false;
    }
  }

  static async extractFromFile(path: string): Promise<ExtractedPair> {
    const source: image.ImageSource = image.createImageSource(path);
    const pm: image.PixelMap = await source.createPixelMap({ desiredSize: { width: 64, height: 64 } });
    const info: image.ImageInfo = await pm.getImageInfo();
    const size: image.Size = info.size;
    const buf = new ArrayBuffer(size.width * size.height * 4);
    await pm.readPixelsToBuffer(buf);
    const pixels = new Uint8Array(buf);
    pm.release();
    return extractColors(pixels, size.width, size.height);
  }

  /** 从当前音轨封面取色并应用到主题(无动画;启动恢复场景,issue-12 修复) */
  static async applyCoverColors(context: common.Context, theme: ThemeService, track: Track): Promise<void> {
    if (track.coverPath === '') {
      return;
    }
    try {
      const abs = context.filesDir + '/' + track.coverPath;
      const colors = await BackgroundAdapter.extractFromFile(abs);
      theme.applyExtracted(colors.primary, colors.secondary);
    } catch (err) {
      // 封面取色失败静默,保持当前主题
    }
  }
}
