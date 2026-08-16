import { common } from '@kit.AbilityKit';
import { LyricLine, findActiveLine } from '../service/lyrics/LrcParser';
import { LrcLoader } from '../service/lyrics/LrcLoader';
import { playerViewModel } from './PlayerViewModel';
import { Track } from '../model/Entities';

/** 歌词状态容器(issue-08):当前曲目歌词 + 随播放高亮行 */
@Observed
export class LyricsViewModel {
  lines: LyricLine[] = [];
  activeIndex: number = -1;
  private context: common.Context | null = null;
  /** 防重复:当前曲已确认无歌词后不再每 tick 重读文件 */
  private reloadChecked: boolean = false;

  constructor() {
    // 切歌 → 重新加载歌词
    playerViewModel.trackChangeHandler = (t: Track): void => {
      this.onTrackChanged(t);
    };
    // 播放位置 → 更新高亮行
    playerViewModel.positionTickHandler = (ms: number): void => {
      if (this.lines.length === 0 && !this.reloadChecked) {
        // 流式即播时歌词文件可能在播放中途才落盘(阶段 v2.3):有文件就补加载
        const t = playerViewModel.currentTrack;
        if (t !== null && this.context !== null) {
          const abs = this.context.filesDir + '/' + t.path;
          const loaded = LrcLoader.loadForTrack(abs);
          if (loaded !== null && loaded.length > 0) {
            this.lines = loaded;
          } else {
            this.reloadChecked = true;
          }
        }
      }
      this.activeIndex = findActiveLine(this.lines, ms);
    };
  }

  private onTrackChanged(t: Track): void {
    if (this.context === null) {
      this.lines = [];
      this.activeIndex = -1;
      return;
    }
    const abs = this.context.filesDir + '/' + t.path;
    const loaded = LrcLoader.loadForTrack(abs);
    this.lines = loaded !== null ? loaded : [];
    this.activeIndex = -1;
    this.reloadChecked = loaded !== null && loaded.length > 0;
  }

  setContext(context: common.Context): void {
    this.context = context;
  }
}

export const lyricsViewModel: LyricsViewModel = new LyricsViewModel();
