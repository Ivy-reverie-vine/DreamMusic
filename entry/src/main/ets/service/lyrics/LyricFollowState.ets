/** 只在活动行变化或恢复跟随时请求滚动；切歌清除上一首的浏览状态。 */
export class LyricFollowState {
  paused: boolean = false;
  private lastIndex: number = -1;
  private revision: number = -1;

  nextIndex(activeIndex: number, revision: number): number | null {
    if (revision !== this.revision) {
      this.revision = revision;
      this.resume();
    }
    if (this.paused) {
      return null;
    }
    const index = Math.max(0, activeIndex);
    if (index === this.lastIndex) {
      return null;
    }
    this.lastIndex = index;
    return index;
  }

  pause(revision: number): void {
    this.revision = revision;
    this.paused = true;
  }

  reset(revision: number): void {
    this.revision = revision;
    this.resume();
  }

  resume(): void {
    this.paused = false;
    this.lastIndex = -1;
  }
}
