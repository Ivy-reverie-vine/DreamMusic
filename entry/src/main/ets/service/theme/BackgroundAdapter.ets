import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { extractColors, ExtractedColors } from '../color/ColorExtract';
import { ThemeService } from './ThemeService';
import { Track } from '../../model/Entities';

const DOMAIN = 0x0000;
const TAG = 'BackgroundAdapter';

/**
 * 取色适配层(issue-00/14):
 * 背景图使用内置预设(BG_PRESETS),主题色运行时从资源取色(extractPresetColors);
 * 另保留封面取色能力(正在播放页切歌取色 + 启动恢复)。
 */
export class BackgroundAdapter {
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
