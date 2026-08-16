import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { extractColors, ExtractedColors } from '../color/ColorExtract';
import { ThemeService } from './ThemeService';
import { Track } from '../../model/Entities';
import { copyFileRobust } from '../../common/FsUtil';

const DOMAIN = 0x0000;
const TAG = 'BackgroundAdapter';
const BG_DIR = 'background';
const BG_FILE = 'background_custom';

/**
 * 取色适配层(issue-00/14):
 * 背景图使用内置预设(BG_PRESETS),主题色运行时从资源取色(extractPresetColors);
 * 另保留封面取色能力(正在播放页切歌取色 + 启动恢复)。
 * 阶段 v2(8/16 用户拍板):恢复"自定义背景图"入口——
 * PhotoViewPicker 选图 → 复制进沙箱(固定名单份存储)→ 取色 → ThemeService.applyCustomBg;
 * 切换即时生效依赖 Index 的 bgStamp 奇偶重建(内置预设已验证的方案,替代 issue-14 的时间戳文件名)。
 */
export class BackgroundAdapter {
  /** 成功返回 '';失败返回用户可读原因(设置页展示,issue-12 修复) */
  static async pickAndApply(context: common.Context, theme: ThemeService): Promise<string> {
    const photoPicker = new picker.PhotoViewPicker();
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    let uri = '';
    try {
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        return '未选择图片';
      }
      uri = result.photoUris[0];
    } catch (err) {
      const e = err as Error;
      return '选择失败: ' + e.message;
    }
    try {
      // 先清旧自定义文件(固定名单份存储,避免旧文件残留导致切换不生效)
      BackgroundAdapter.removeBackgroundFiles(context);
      const destPath: string = BackgroundAdapter.copyToSandbox(context, uri);
      const colors = await BackgroundAdapter.extractFromFile(destPath);
      const relPath = BG_DIR + '/' + destPath.substring(destPath.lastIndexOf('/') + 1);
      theme.applyCustomBg(relPath, 'file://' + destPath, colors);
      ThemeService.saveCustomBg(context, relPath);
      return '';
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'pickAndApply failed: %{public}s', e.message);
      return '应用失败: ' + e.message;
    }
  }

  /** 固定文件名复制进沙箱 background/ 目录(带原扩展名,便于 ImageSource 解码) */
  private static copyToSandbox(context: common.Context, uri: string): string {
    const dir = context.filesDir + '/' + BG_DIR;
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
    let ext = '';
    const dot = uri.lastIndexOf('.');
    if (dot >= 0 && dot > uri.lastIndexOf('/')) {
      ext = uri.substring(dot);
      if (ext.length > 8) {
        ext = '';
      }
    }
    if (ext === '') {
      ext = '.jpg';
    }
    const dest = dir + '/' + BG_FILE + ext;
    copyFileRobust(uri, dest);
    return dest;
  }

  /** 重启恢复自定义背景图与取色(阶段 v2;无自定义文件时返回 false) */
  static async restoreIfPresent(context: common.Context, theme: ThemeService): Promise<boolean> {
    const dir = context.filesDir + '/' + BG_DIR;
    try {
      if (!fileIo.accessSync(dir)) {
        return false;
      }
      const names = await fileIo.listFile(dir);
      for (const n of names) {
        if (n.startsWith(BG_FILE)) {
          const abs = dir + '/' + n;
          const colors = await BackgroundAdapter.extractFromFile(abs);
          theme.applyCustomBg(BG_DIR + '/' + n, 'file://' + abs, colors);
          ThemeService.saveCustomBg(context, BG_DIR + '/' + n);
          return true;
        }
      }
      return false;
    } catch (err) {
      return false;
    }
  }

  /** 删除 background/ 下全部自定义背景文件(固定名 + 历史时间戳残留一并清理) */
  static removeBackgroundFiles(context: common.Context): void {
    try {
      const dir = context.filesDir + '/' + BG_DIR;
      if (!fileIo.accessSync(dir)) {
        return;
      }
      const names = fileIo.listFileSync(dir);
      for (const n of names) {
        if (n.startsWith(BG_FILE)) {
          fileIo.unlinkSync(dir + '/' + n);
        }
      }
    } catch (err) {
      // 删除失败静默(下次选择会再清一次)
    }
  }

  /** 从内置媒体资源取色(64x64 缩略 → 取色引擎) */
  static async extractPresetColors(context: common.Context, res: Resource): Promise<ExtractedColors> {
    const buf = await context.resourceManager.getMediaContent(res);
    const source: image.ImageSource = image.createImageSource(buf);
    const pm: image.PixelMap = await source.createPixelMap({ desiredSize: { width: 64, height: 64 } });
    const info: image.ImageInfo = await pm.getImageInfo();
    const size: image.Size = info.size;
    const buf2 = new ArrayBuffer(size.width * size.height * 4);
    await pm.readPixelsToBuffer(buf2);
    pm.release();
    return extractColors(new Uint8Array(buf2), size.width, size.height);
  }

  static async extractFromFile(path: string): Promise<ExtractedColors> {
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
