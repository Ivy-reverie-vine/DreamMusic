import { common } from '@kit.AbilityKit';
import { QueueEngine, PlayMode } from '../service/playback/QueueEngine';
import { LibraryStore } from '../service/library/LibraryStore';
import { playerViewModel } from './PlayerViewModel';
import { Track } from '../model/Entities';

/**
 * 播放队列状态容器(issue-06):引擎(纯逻辑)与播放会话/持久化的粘合层。
 * 断点续播语义:重启后恢复队列/当前曲/进度(暂停态),按播放从断点继续。
 */
@Observed
export class QueueViewModel {
  queueTracks: Track[] = [];
  currentId: number = -1;
  mode: PlayMode = PlayMode.SEQUENTIAL;
  private engine: QueueEngine = new QueueEngine();
  private context: common.Context | null = null;

  constructor() {
    // 播放自然结束 → 队列域接管切歌
    playerViewModel.endedHandler = (): void => {
      this.handleTrackEnded();
    };
    // 暂停时落盘进度
    playerViewModel.pausePositionHandler = (ms: number): void => {
      this.persist(ms);
    };
  }

  private trackById(id: number): Track | null {
    for (const t of this.queueTracks) {
      if (t.id === id) {
        return t;
      }
    }
    return null;
  }

  /** 当前曲在队列中的索引(UI 高亮用) */
  currentIndexId(): number {
    return this.engine.currentIndexValue;
  }

  private syncDisplay(): void {
    const ids = this.engine.queueIds;
    const display: Track[] = [];
    ids.forEach((id: number) => {
      const t = this.trackById(id);
      if (t !== null) {
        display.push(t);
      }
    });
    this.queueTracks = display;
    this.currentId = this.engine.current();
    this.mode = this.engine.currentMode;
  }

  /** 点歌:来源列表成为队列,从 startIndex 开始播 */
  async playFromList(tracks: Track[], startIndex: number, context: common.Context): Promise<void> {
    this.context = context;
    const ids: number[] = [];
    tracks.forEach((t: Track) => {
      ids.push(t.id);
    });
    this.engine.setQueue(ids, startIndex, this.mode);
    this.syncDisplay();
    await this.playCurrent(0);
  }

  private async playCurrent(seekMs: number): Promise<void> {
    if (this.context === null) {
      return;
    }
    const id = this.engine.current();
    const t = this.trackById(id);
    if (t === null) {
      return;
    }
    await playerViewModel.playTrack(t, this.context);
    if (seekMs > 0) {
      playerViewModel.seekTo(seekMs);
    }
    this.currentId = id;
    this.persist(seekMs);
  }

  handleTrackEnded(): void {
    const nextId = this.engine.next();
    if (nextId === -1) {
      // 顺序模式播完停住
      this.persist(0);
      return;
    }
    this.currentId = nextId;
    this.playCurrent(0);
  }

  async playNext(): Promise<void> {
    const nextId = this.engine.next();
    if (nextId !== -1) {
      this.currentId = nextId;
      await this.playCurrent(0);
    }
  }

  async playPrev(): Promise<void> {
    const prevId = this.engine.prev();
    if (prevId !== -1) {
      this.currentId = prevId;
      await this.playCurrent(0);
    }
  }

  cycleMode(): void {
    const order: PlayMode[] = [PlayMode.SEQUENTIAL, PlayMode.REPEAT_ALL, PlayMode.REPEAT_ONE, PlayMode.SHUFFLE];
    const idx = order.indexOf(this.mode);
    this.mode = order[(idx + 1) % order.length];
    this.engine.setMode(this.mode);
    this.persist(playerViewModel.positionMs);
  }

  move(from: number, to: number): void {
    this.engine.move(from, to);
    this.syncDisplay();
    this.persist(playerViewModel.positionMs);
  }

  removeAt(index: number): void {
    this.engine.removeAt(index);
    this.syncDisplay();
    this.persist(playerViewModel.positionMs);
  }

  private persist(positionMs: number): void {
    const store = LibraryStore.getInstance();
    store.savePlayerState(this.engine.queueIds, this.engine.currentIndexValue,
      this.engine.currentMode, positionMs).catch(() => {
    });
  }

  /** 启动恢复:还原队列/当前曲/进度(暂停态,按播放续播) */
  async restore(context: common.Context): Promise<void> {
    this.context = context;
    const store = LibraryStore.getInstance();
    const state = await store.loadPlayerState();
    if (state === null || state.queue.length === 0) {
      return;
    }
    const all = await store.listTracks();
    const byId = new Map<number, Track>();
    all.forEach((t: Track) => {
      byId.set(t.id, t);
    });
    // 过滤已不存在的音轨 id,保持相对顺序
    const validIds: number[] = [];
    state.queue.forEach((id: number) => {
      if (byId.has(id)) {
        validIds.push(id);
      }
    });
    if (validIds.length === 0) {
      return;
    }
    this.engine.setQueue(validIds, 0);
    this.engine.setMode(state.mode as PlayMode);
    // 恢复 current:按原 current id 定位(找不到则回到队首)
    const originalCurrentId = state.currentIndex >= 0 && state.currentIndex < state.queue.length
      ? state.queue[state.currentIndex] : -1;
    let currentIdx = validIds.indexOf(originalCurrentId);
    if (currentIdx < 0) {
      currentIdx = 0;
    }
    const snap = this.engine.toSnapshot();
    snap.currentIndex = currentIdx;
    this.engine.fromSnapshot(snap);
    this.syncDisplay();
    const t = this.trackById(this.engine.current());
    if (t !== null) {
      playerViewModel.restorePaused(t, state.positionMs, context);
    }
  }
}

export const queueViewModel: QueueViewModel = new QueueViewModel();
