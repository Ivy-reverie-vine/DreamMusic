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
  /** 扫描判定:文件已从沙箱消失(保留记录,不自动删) */
  missing: boolean;
  /** 网易云歌曲 id(0 = 本地导入;>0 = 瞬态在线播放来源标记) */
  neteaseId: number;
  /** 瞬态在线音轨的普通播放直链(不落盘) */
  streamUrl?: string;
  /** 瞬态在线音轨的远程封面 URL(不落盘,仅正在播放页显示) */
  streamCoverUrl?: string;
}

/** 在线搜索结果(api-enhanced /search 返回;非数据库实体,阶段 v2) */
export interface OnlineSong {
  /** 网易云歌曲 id(后续 /song/url/v1、/lyric 共用) */
  id: number;
  name: string;
  artist: string;
  album: string;
  /** 网易 CDN 封面 URL(可能为空,UI 用占位渐变) */
  coverUrl: string;
  durationMs: number;
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

/** 仅来自本机 SQLite 的播放统计，不代表账户生命周期总量。 */
export interface LocalPlaybackStats {
  playRecordCount: number;
  customPlaylistCount: number;
  favoriteCount: number;
}

/** 来自 DreamMusic 账户的跨设备播放统计。 */
export interface AccountPlaybackStats {
  playSeconds: number;
  playedSongCount: number;
  syncedAt: number;
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
