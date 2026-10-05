/**
 * 领域实体与纯类型定义(零 Kit 依赖,可单测)。
 * 术语与 CONTEXT.md 对齐:音轨/歌单/收藏/播放历史/服务器配置。
 */

export interface AudioIntegrity {
  status: string;
  reason: string;
  catalogDurationMs: number;
  resourceDurationMs: number;
  evidence: string[];
}

export interface PlaybackAttempt {
  mediaRef: string;
  source: string;
  status: string;
  reason?: string;
  matchReason: string;
  audioIntegrity?: AudioIntegrity;
}

export interface BilibiliPartResource {
  bvid: string;
  cid: string;
  page: number;
  title: string;
  partTitle: string;
  uploader: BilibiliUploader;
}

export interface BilibiliUploader {
  id: string;
  name: string;
}

export interface BilibiliMatchEvidence {
  policy: string;
  title: string;
  artists: string[];
  album: string;
  catalogDurationMs: number;
  partDurationMs: number;
  catalogLink: boolean;
  originalAlbumAudio: boolean;
}

export interface BilibiliRecordingMatch {
  status: string;
  reason: string;
  evidence: BilibiliMatchEvidence;
}

/** 搜索提示可能尚未取得 CID；只有具体分 P 才有 mediaRef。 */
export interface BilibiliFallbackCandidate {
  source: string;
  bvid?: string;
  mediaRef?: string;
  sourceId?: string;
  title: string;
  artists?: string[];
  durationMs?: number;
  resource?: BilibiliPartResource;
  status: string;
  reason: string;
  match?: BilibiliRecordingMatch;
  audioIntegrity?: AudioIntegrity;
}

export interface BilibiliFallbackOutcome {
  status: string;
  reason: string;
  query: string;
  candidates: BilibiliFallbackCandidate[];
}

export interface AutomaticPlaybackOutcome {
  status: string;
  reason: string;
  totalBudgetMs: number;
  stageBudgetMs: number;
  elapsedMs: number;
  remainingBudgetMs: number;
  attempts: PlaybackAttempt[];
  bilibili?: BilibiliFallbackOutcome;
}

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
  /** 网易目录歌曲 ID；0 = 本地导入或非网易目录。不是队列条目 ID。 */
  neteaseId: number;
  /** 瞬态在线音轨的普通播放直链(不落盘) */
  streamUrl?: string;
  audioIntegrity?: AudioIntegrity;
  /** 在线封面 URL；封面服务缓存到 cacheDir，转本地时暂留作封面缺失回退，不写数据库。 */
  streamCoverUrl?: string;
  /** v2 版本化来源引用;不包含可直接播放的 URL */
  mediaRef?: string;
  automaticSearchSession?: string;
  playbackOutcome?: AutomaticPlaybackOutcome;
  /** 当前队列条目的搜索候选快照与手动选择；不落数据库。 */
  sourceSearchSession?: string;
  sourceOptions?: OnlineSong[];
  manualPlaybackRef?: string;
  catalogRef?: string;
  playbackRef?: string;
  lyricsRef?: string;
  playbackSource?: string;
  lyricsSource?: string;
}

/** 在线搜索结果(v2 mediaRef 或 v1 api-enhanced;非数据库实体) */
export interface OnlineSong {
  /** 网易云歌曲 id;非网易来源为 0 */
  id: number;
  name: string;
  artist: string;
  album: string;
  /** 网易 CDN 封面 URL(可能为空,UI 用占位渐变) */
  coverUrl: string;
  durationMs: number;
  artists?: string[];
  versionTags?: string[];
  originalTitle?: string;
  /** v2 来源引用;普通在线播放和歌词请求使用它 */
  mediaRef?: string;
  automaticSearchSession?: string;
  source?: string;
  sourceId?: string;
  catalogRef?: string;
  playbackRef?: string;
  lyricsRef?: string;
  playbackSource?: string;
  lyricsSource?: string;
}

/** NightDream 确认的分组；展示条目与展开状态属于当前搜索页面。 */
export interface OnlineSearchGroup {
  id: string;
  entries: OnlineSong[];
  reason: string;
  selectedRef: string;
  expanded: boolean;
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
