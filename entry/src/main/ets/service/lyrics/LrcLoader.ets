import { fileIo } from '@kit.CoreFileKit';
import { parseLrc, LyricLine } from './LrcParser';

/**
 * LRC 歌词加载适配层(issue-08,真机验证项):
 * 音轨同目录同名 .lrc(readTextSync);无文件/编码异常 → null(歌词区隐藏,优雅降级)。
 */
export class LrcLoader {
  /** absPath 为音轨沙箱绝对路径 */
  static loadForTrack(absPath: string): LyricLine[] | null {
    const dot = absPath.lastIndexOf('.');
    if (dot <= 0) {
      return null;
    }
    const lrcPath = absPath.substring(0, dot) + '.lrc';
    try {
      if (!fileIo.accessSync(lrcPath)) {
        return null;
      }
      const content = fileIo.readTextSync(lrcPath);
      return parseLrc(content);
    } catch (err) {
      // 编码异常/读取失败:降级为无歌词
      return null;
    }
  }
}
