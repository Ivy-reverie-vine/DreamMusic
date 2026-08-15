import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { extractColors } from '../color/ColorExtract';
import { ThemeService } from './ThemeService';
import { Track } from '../../model/Entities';

const DOMAIN = 0x0000;
const TAG = 'BackgroundAdapter';

interface ExtractedPair {
  primary: string;
  secondary: string;
}

/**
 * 取色适配层(issue-00/14):
 * 背景图自选方案已废弃(用户定稿:内置固定背景图,见 BG_PRESETS);
 * 本文件保留封面取色能力(正在播放页切歌取色 + 启动恢复)。
 */
export class BackgroundAdapter {
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
