import { common } from '@kit.AbilityKit';
import { QueueEngine, PlayMode, QueueSnapshot } from '../service/playback/QueueEngine';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { LibraryStore } from '../service/library/LibraryStore';
import { playerViewModel } from './PlayerViewModel';
import { PlayerState } from '../model/Playback';
import { Track } from '../model/Entities';

const PERSIST_INTERVAL_MS = 15000;

/**
 * 播放队列状态容器(issue-06):引擎(纯逻辑)与播放会话/持久化的粘合层。
 * 断点续播语义:重启后恢复队列/当前曲/进度(暂停态),按播放从断点继续。
 * issue-13:随机洗牌序随队列持久化;播放中每 15s 落盘,切后台/销毁时落盘。
 */
@Observed
export class QueueViewModel {
  queueTracks: Track[] = [];
  currentId: number = -1;
  mode: PlayMode = PlayMode.SEQUENTIAL;
  private engine: QueueEngine = new QueueEngine();
  private context: common.Context | null = null;
  private persistChain: Promise<void> = Promise.resolve();
  private restoring: boolean = false;
  private persistAfterRestore: boolean = false;
  /**
   * id → Track 映射缓存(issue-14 修复):
   * syncDisplay 需要把队列 id 解析为 Track;此前依赖旧 queueTracks 自映射,
   * 首次点歌时为空导致队列/正在播放/播放全部静默失败。
   */
  private trackCache: Track[] = [];

  constructor() {
    // 播放自然结束 → 队列域接管切歌
    playerViewModel.endedHandler = (): void => {
      this.handleTrackEnded();
    };
    // 暂停时落盘进度
    playerViewModel.pausePositionHandler = (ms: number): void => {
      this.persist(ms);
    };
    playerViewModel.sleepTimerChangedHandler = (): void => {
      this.persist(playerViewModel.positionMs);
    };
    // 播放中每 15s 落盘(issue-13:强杀应用也能断点续播)
    setInterval(() => {
      if (playerViewModel.state === PlayerState.PLAYING) {
        this.persist(playerViewModel.positionMs);
      }
    }, PERSIST_INTERVAL_MS);
    // 系统播控命令(锁屏/控制中心/耳机键)→ 队列域(issue-07)
    const bp = BackgroundPlayback.getInstance();
    bp.onPlayCommand = (): void => {
      if (playerViewModel.state === PlayerState.PAUSED || playerViewModel.state === PlayerState.COMPLETED) {
        if (playerViewModel.checkSleepTimer()) {
          return;
        }
        playerViewModel.togglePause();
      }
    };
    bp.onPauseCommand = (): void => {
      if (playerViewModel.state === PlayerState.PLAYING) {
        playerViewModel.togglePause();
      }
    };
    bp.onNextCommand = (): void => {
      if (playerViewModel.checkSleepTimer()) {
        return;
      }
      this.playNext();
    };
    bp.onPrevCommand = (): void => {
      if (playerViewModel.checkSleepTimer()) {
        return;
      }
      this.playPrev();
    };
    bp.onSeekCommand = (ms: number): void => {
      playerViewModel.seekTo(ms);
    };
  }

  private trackById(id: number): Track | null {
    for (const t of this.trackCache) {
      if (t.id === id) {
        return t;
      }
    }
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
    this.trackCache = tracks.slice();
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
    if (playerViewModel.checkSleepTimer()) {
      return;
    }
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
    if (playerViewModel.checkSleepTimer()) {
      return;
    }
    const nextId = this.engine.next();
    if (nextId !== -1) {
      this.currentId = nextId;
      await this.playCurrent(0);
    }
  }

  async playPrev(): Promise<void> {
    if (playerViewModel.checkSleepTimer()) {
      return;
    }
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
    playerViewModel.playMode = this.mode;
    BackgroundPlayback.getInstance().sync(playerViewModel.currentTrack, playerViewModel.state,
      playerViewModel.positionMs, playerViewModel.durationMs, this.mode, true);
    this.persist(playerViewModel.positionMs);
  }

  move(from: number, to: number): void {
    this.engine.move(from, to);
    this.syncDisplay();
    this.persist(playerViewModel.positionMs);
  }

  /**
   * 拖拽实时重排(8/16 真机修复):
   * 引擎重排 + 显示数组**原地 splice**(不整组重建),ForEach 按 id 键最小 diff,
   * 避免拖拽过程中数据整体刷新导致拖拽被中断;落盘由 commitReorder 在松手后统一做。
   */
  moveLive(from: number, to: number): void {
    const n = this.queueTracks.length;
    if (from < 0 || to < 0 || from >= n || to >= n || from === to) {
      return;
    }
    this.engine.move(from, to);
    const moved = this.queueTracks.splice(from, 1)[0];
    if (moved !== undefined) {
      this.queueTracks.splice(to, 0, moved);
    }
    this.currentId = this.engine.current();
    this.mode = this.engine.currentMode;
  }

  /** 拖拽结束:按引擎最终顺序持久化(顺序变更重启后恢复) */
  commitReorder(): void {
    this.persist(playerViewModel.positionMs);
  }

  /** 按拖拽后的 id 顺序重建引擎并落盘(8/16 修复:拖拽在页面本地数组上进行,松手统一提交) */
  reorder(ids: number[]): void {
    if (ids.length !== this.engine.queueLength) {
      return;
    }
    const cur = this.engine.current();
    const curIdx = ids.indexOf(cur);
    this.engine.setQueue(ids, Math.max(0, curIdx), this.mode);
    this.syncDisplay();
    this.persist(playerViewModel.positionMs);
  }

  /**
   * 下载完成后把当前瞬态在线音轨替换为已入库的正式音轨。
   * 播放会话继续使用已打开的流地址；下一次切歌、重启和音乐库操作均解析本地记录。
   */
  swapCurrentWithLocal(track: Track): void {
    const oldId = this.engine.current();
    if (oldId >= 0 || !this.engine.replaceTrackId(oldId, track.id)) {
      return;
    }
    let cached = false;
    for (let i = 0; i < this.trackCache.length; i++) {
      if (this.trackCache[i].id === track.id) {
        cached = true;
        break;
      }
    }
    if (!cached) {
      this.trackCache.push(track);
    }
    this.syncDisplay();
    playerViewModel.currentTrack = track;
    if (playerViewModel.trackChangeHandler !== null) {
      playerViewModel.trackChangeHandler(track);
    }
    if (playerViewModel.coverColorHandler !== null) {
      playerViewModel.coverColorHandler(track);
    }
    this.persist(playerViewModel.positionMs);
  }

  removeAt(index: number): void {
    this.engine.removeAt(index);
    this.syncDisplay();
    this.persist(playerViewModel.positionMs);
  }

  private persist(positionMs: number): void {
    if (this.restoring) {
      this.persistAfterRestore = true;
      return;
    }
    const store = LibraryStore.getInstance();
    const snapshot = this.engine.toSnapshot();
    const sleepTimer = playerViewModel.sleepTimerSnapshot;
    this.persistChain = this.persistChain
      .then(() => store.savePlayerState(snapshot, positionMs, sleepTimer))
      .catch(() => {
      });
  }

  /** 立即落盘(切后台/销毁时由 EntryAbility 调用,issue-13) */
  persistNow(positionMs: number): void {
    if (this.context === null) {
      return;
    }
    this.persist(positionMs);
  }

  /** 音轨被删除时从队列中清除(issue-14:删歌后队列不再残留) */
  purgeTrack(trackId: number): void {
    const ids = this.engine.queueIds;
    let changed = false;
    for (let i = ids.length - 1; i >= 0; i--) {
      if (ids[i] === trackId) {
        this.engine.removeAt(i);
        changed = true;
      }
    }
    if (changed) {
      const kept: Track[] = [];
      this.trackCache.forEach((t: Track) => {
        if (t.id !== trackId) {
          kept.push(t);
        }
      });
      this.trackCache = kept;
      this.syncDisplay();
      this.persist(playerViewModel.positionMs);
    }
  }

  /** 启动恢复:还原队列/当前曲/进度(暂停态,按播放续播);洗牌序随队列恢复 */
  async restore(context: common.Context): Promise<void> {
    this.restoring = true;
    this.persistAfterRestore = false;
    try {
      this.context = context;
      const store = LibraryStore.getInstance();
      await store.init(context);
      const state = await store.loadPlayerState();
      if (state === null) {
        return;
      }
      const timerExpired = playerViewModel.restoreSleepTimer({
        active: state.sleepTimerActive,
        deadlineMs: state.sleepTimerDeadlineMs
      });
      if (state.queue.length === 0) {
        if (timerExpired) {
          this.persist(state.positionMs);
        }
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
        if (timerExpired) {
          this.persist(state.positionMs);
        }
        return;
      }
      // 恢复 current:按原 current id 定位(找不到则回到队首)
      const originalCurrentId = state.currentIndex >= 0 && state.currentIndex < state.queue.length
        ? state.queue[state.currentIndex] : -1;
      let currentIdx = validIds.indexOf(originalCurrentId);
      if (currentIdx < 0) {
        currentIdx = 0;
      }
      const snap: QueueSnapshot = {
        tracks: validIds,
        currentIndex: currentIdx,
        mode: state.mode as PlayMode,
        shuffleOrder: state.shuffleOrder,
        shufflePos: state.shufflePos,
        shuffleSteps: state.shuffleSteps
      };
      this.engine.fromSnapshot(snap);
      this.trackCache = all;
      this.syncDisplay();
      const t = this.trackById(this.engine.current());
      if (t !== null) {
        playerViewModel.restorePaused(t, state.positionMs, context);
      }
      if (timerExpired) {
        this.persist(state.positionMs);
      }
    } finally {
      this.restoring = false;
      if (this.persistAfterRestore) {
        this.persistAfterRestore = false;
        this.persist(playerViewModel.positionMs);
      }
    }
  }
}

export const queueViewModel: QueueViewModel = new QueueViewModel();
