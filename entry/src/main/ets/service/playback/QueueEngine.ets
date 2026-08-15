import { PlayerState } from '../../model/Playback';

/**
 * 播放队列引擎(纯逻辑,零 Kit 依赖)——issue-06 单测主战场。
 * 队列以音轨 id 列表表示;四种播放模式;随机洗牌周期内不重复、新周期首曲不复现上一曲;
 * 拖拽移动/移除时 current 始终跟随同一音轨。
 */

export enum PlayMode {
  SEQUENTIAL = 'SEQUENTIAL',
  REPEAT_ONE = 'REPEAT_ONE',
  REPEAT_ALL = 'REPEAT_ALL',
  SHUFFLE = 'SHUFFLE'
}

export interface QueueSnapshot {
  tracks: number[];
  currentIndex: number;
  mode: PlayMode;
}

export class QueueEngine {
  private tracks: number[] = [];
  private currentIndex: number = -1;
  private mode: PlayMode = PlayMode.SEQUENTIAL;
  private shuffleOrder: number[] = [];
  private shufflePos: number = -1;
  /** 本次洗牌序内已推进的步数(步数达队列长度 = 周期完成,再推进则重建) */
  private shuffleSteps: number = 0;

  setQueue(tracks: number[], startIndex: number, mode?: PlayMode): void {
    this.tracks = tracks.slice();
    if (this.tracks.length === 0) {
      this.currentIndex = -1;
    } else {
      this.currentIndex = Math.max(0, Math.min(startIndex, this.tracks.length - 1));
    }
    if (mode !== undefined) {
      this.mode = mode;
    }
    this.buildShuffle();
  }

  get queueLength(): number {
    return this.tracks.length;
  }

  getTrackAt(index: number): number {
    if (index < 0 || index >= this.tracks.length) {
      return -1;
    }
    return this.tracks[index];
  }

  get queueIds(): number[] {
    return this.tracks.slice();
  }

  current(): number {
    if (this.currentIndex < 0 || this.currentIndex >= this.tracks.length) {
      return -1;
    }
    return this.tracks[this.currentIndex];
  }

  get currentIndexValue(): number {
    return this.currentIndex;
  }

  get currentMode(): PlayMode {
    return this.mode;
  }

  setMode(mode: PlayMode): void {
    this.mode = mode;
    this.buildShuffle();
  }

  /** 洗牌;lastExcluded = 上一周期最后一首的队列索引(新周期首曲不复现) */
  private buildShuffle(lastExcluded?: number): void {
    const n = this.tracks.length;
    const order: number[] = [];
    for (let i = 0; i < n; i++) {
      order.push(i);
    }
    for (let i = n - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    if (n > 1 && lastExcluded !== undefined && order[0] === lastExcluded) {
      const t = order[0];
      order[0] = order[1];
      order[1] = t;
    }
    this.shuffleOrder = order;
    this.shufflePos = n > 0 ? order.indexOf(this.currentIndex) : -1;
    this.shuffleSteps = 0;
  }

  /** 取下一首并推进;顺序模式播完最后一首返回 -1(停住) */
  next(): number {
    const n = this.tracks.length;
    if (n === 0) {
      return -1;
    }
    switch (this.mode) {
      case PlayMode.REPEAT_ONE:
        return this.current();
      case PlayMode.REPEAT_ALL:
        this.currentIndex = (this.currentIndex + 1) % n;
        return this.current();
      case PlayMode.SHUFFLE: {
        if (n === 1) {
          return this.current();
        }
        this.shuffleSteps++;
        if (this.shuffleSteps >= n) {
          // 周期完成:新周期首曲不复现上一周期最后一首
          const lastPlayed = this.currentIndex;
          this.buildShuffle(lastPlayed);
          this.shuffleSteps = 1;
          this.shufflePos = 0;
        } else {
          this.shufflePos = (this.shufflePos + 1) % n;
        }
        this.currentIndex = this.shuffleOrder[this.shufflePos];
        return this.current();
      }
      default:
        if (this.currentIndex + 1 >= n) {
          return -1;
        }
        this.currentIndex++;
        return this.current();
    }
  }

  /** 上一首:顺序模式在队首停留;列表循环回绕;随机沿洗牌序回退 */
  prev(): number {
    const n = this.tracks.length;
    if (n === 0) {
      return -1;
    }
    switch (this.mode) {
      case PlayMode.REPEAT_ONE:
        return this.current();
      case PlayMode.REPEAT_ALL:
        this.currentIndex = (this.currentIndex - 1 + n) % n;
        return this.current();
      case PlayMode.SHUFFLE:
        if (n === 1) {
          return this.current();
        }
        this.shufflePos = (this.shufflePos - 1 + n) % n;
        this.currentIndex = this.shuffleOrder[this.shufflePos];
        return this.current();
      default:
        if (this.currentIndex > 0) {
          this.currentIndex--;
        }
        return this.current();
    }
  }

  /** 拖拽排序:from → to,current 始终跟随同一音轨 */
  move(from: number, to: number): void {
    const n = this.tracks.length;
    if (n === 0 || from < 0 || from >= n || to < 0 || to >= n || from === to) {
      return;
    }
    const moved = this.tracks[from];
    this.tracks.splice(from, 1);
    this.tracks.splice(to, 0, moved);
    if (from === this.currentIndex) {
      this.currentIndex = to;
    } else if (from < this.currentIndex && to >= this.currentIndex) {
      this.currentIndex--;
    } else if (from > this.currentIndex && to <= this.currentIndex) {
      this.currentIndex++;
    }
    this.buildShuffle();
  }

  removeAt(index: number): void {
    const n = this.tracks.length;
    if (n === 0 || index < 0 || index >= n) {
      return;
    }
    this.tracks.splice(index, 1);
    if (this.tracks.length === 0) {
      this.currentIndex = -1;
    } else if (index < this.currentIndex) {
      this.currentIndex--;
    } else if (index === this.currentIndex) {
      this.currentIndex = Math.min(this.currentIndex, this.tracks.length - 1);
    }
    this.buildShuffle();
  }

  toSnapshot(): QueueSnapshot {
    return { tracks: this.tracks.slice(), currentIndex: this.currentIndex, mode: this.mode };
  }

  fromSnapshot(snap: QueueSnapshot): void {
    this.tracks = snap.tracks.slice();
    this.currentIndex = snap.currentIndex;
    this.mode = snap.mode;
    this.buildShuffle();
  }
}
