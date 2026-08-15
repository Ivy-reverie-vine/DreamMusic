/**
 * 播放领域纯类型(零 Kit 依赖,可单测)。
 * 队列域(issue-06)与本文件对齐,不 import 任何适配层。
 */

export enum PlayerState {
  IDLE = 'IDLE',
  PREPARING = 'PREPARING',
  PLAYING = 'PLAYING',
  PAUSED = 'PAUSED',
  COMPLETED = 'COMPLETED',
  ERROR = 'ERROR'
}

/** 播放域对外快照(供 UI/队列域消费) */
export interface PlaybackSnapshot {
  trackId: number;
  state: PlayerState;
  positionMs: number;
  durationMs: number;
}
