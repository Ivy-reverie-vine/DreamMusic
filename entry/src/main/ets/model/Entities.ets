/**
 * 领域实体与纯类型定义(零 Kit 依赖,可单测)。
 * 术语与 CONTEXT.md 对齐:音轨/歌单/收藏/播放历史/服务器配置。
 */

export interface Track {
  id: number;
  /** 沙箱相对路径,音乐库唯一键(ADR-0001) */
  path: string;
  title: string;
  artist: string;
  album: string;
  durationMs: number;
  coverPath: string;
  importedAt: number;
}

export interface Album {
  id: number;
  name: string;
  artist: string;
  trackCount: number;
}

export interface Artist {
  id: number;
  name: string;
  trackCount: number;
}

export interface Playlist {
  id: number;
  name: string;
  /** 系统保留歌单(我喜欢的音乐)不可删除/重命名 */
  systemReserved: boolean;
  createdAt: number;
}

export interface PlayHistoryEntry {
  id: number;
  trackId: number;
  playedAt: number;
}

export interface ServerProfile {
  id: number;
  alias: string;
  url: string;
  isCurrent: boolean;
  lastStatus: number;
}

/** 播放历史上限(PRD 决策 #12) */
export const PLAY_HISTORY_LIMIT = 500;

/** 系统保留歌单名 */
export const FAVORITES_PLAYLIST_NAME = '我喜欢的音乐';
