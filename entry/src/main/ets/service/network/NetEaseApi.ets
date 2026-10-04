import { common } from '@kit.AbilityKit';
import { ApiClient, ApiError, ApiJsonResult } from './ApiClient';
import { DreamMusicAuth } from './DreamMusicAuth';
import { OnlineSong } from '../../model/Entities';
import {
  classifyPlaybackError,
  DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL,
  DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT,
  playbackDiagnostics
} from '../playback/PlaybackDiagnostics';

const SEARCH_LIMIT = 30;
/** 音质:exhigh(320k)。8/16 接入 DreamMusic 后走真实账号绑定,与网页端默认一致(此前匿名 standard 决策作废) */
const QUALITY_LEVEL = 'exhigh';
const QUERY_CACHE_TTL_MS = 2 * 60 * 1000;
const RETRY_BASE_MS = 350;
const MAX_QUERY_RETRIES = 2;

export interface SearchPage {
  songs: OnlineSong[];
  hasMore: boolean;
}

interface RawArtist {
  name?: string;
}

interface RawAlbum {
  name?: string;
  picUrl?: string;
}

/** /search 单曲原始字段(网易云字段,防御性可选;兼容 ar/al 与 artists/album 两套命名) */
interface RawSong {
  id?: number;
  name?: string;
  ar?: RawArtist[];
  artists?: RawArtist[];
  al?: RawAlbum;
  album?: RawAlbum;
  dt?: number;
}

interface SearchResultBlock {
  songs?: RawSong[];
  more?: boolean;
}

interface UpstreamEnvelope {
  code?: number;
  message?: string;
}

interface SearchResponse extends UpstreamEnvelope {
  result?: SearchResultBlock;
}

interface UrlEntry {
  url?: string;
}

interface SongUrlResponse extends UpstreamEnvelope {
  data?: UrlEntry[];
}

interface MediaAlbum {
  name?: string;
  pictureUrl?: string;
}

interface MediaIdentity {
  catalogRef?: string;
  playbackRef?: string;
  lyricsRef?: string;
  playbackSource?: string;
  lyricsSource?: string;
}

export interface PlaybackResolution extends MediaIdentity {
  url: string;
}

interface MediaSong extends MediaIdentity {
  mediaRef?: string;
  source?: string;
  sourceId?: string;
  legacyId?: number;
  title?: string;
  artists?: string[];
  album?: MediaAlbum;
  durationMs?: number;
}

interface MediaSearchResponse extends UpstreamEnvelope {
  data?: MediaSong[];
  hasMore?: boolean;
}

interface MediaUrlResponse extends UpstreamEnvelope, MediaIdentity {
  data?: UrlEntry[];
  mediaRef?: string;
}

interface MediaDetailResponse extends UpstreamEnvelope {
  data?: MediaSong[];
}

interface SongDetailEntry {
  al?: RawAlbum;
  album?: RawAlbum;
}

interface SongDetailResponse extends UpstreamEnvelope {
  songs?: SongDetailEntry[];
}

interface LyricLrc {
  lyric?: string;
}

interface LyricNewResponse extends UpstreamEnvelope, MediaIdentity {
  lrc?: LyricLrc;
  yrc?: LyricLrc;
}

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

export interface LyricPayload extends MediaIdentity {
  lrc: string;
  yrc: string;
}

/** 上游业务码非 200(460/503 等)→ 抛可读错误 */
function ensureUpstreamOk(wrapper: UpstreamEnvelope): void {
  if (wrapper.code !== undefined && wrapper.code !== 200) {
    const msg = wrapper.message !== undefined && wrapper.message !== '' ? wrapper.message : '';
    throw new ApiError('UPSTREAM_' + wrapper.code,
      msg !== '' ? msg : '上游接口返回错误(' + wrapper.code + ')');
  }
}

/**
 * DreamMusic 中间层转发业务 API(API-DreamMusic.md §7):
 * 统一前缀 /dreammusic/api/v1 + X-API-Key 头 + randomCNIP=true;
 * 范围保持 8/16 拍板:搜索 / 播放链接 / 歌词 / 匿名→账户会话(QR 绑定)。
 */
export class NetEaseApi {
  private static searchCache: Map<string, CacheEntry<SearchPage>> =
    new Map<string, CacheEntry<SearchPage>>();
  private static coverCache: Map<string, CacheEntry<string>> =
    new Map<string, CacheEntry<string>>();
  private static lyricCache: Map<string, CacheEntry<LyricPayload>> =
    new Map<string, CacheEntry<LyricPayload>>();

  /** 单曲搜索(分页) */
  static async search(context: common.Context, keywords: string, offset: number): Promise<SearchPage> {
    try {
      return await NetEaseApi.searchV2(context, keywords, offset);
    } catch (err) {
      // 新服务端不可用或尚未升级时保留 v1 网易云兼容路径。
      if (!(err instanceof ApiError) ||
        (err.code !== 'NOT_ALLOWED' && err.code !== 'UPSTREAM_DOWN' &&
          err.code !== 'NETWORK' && err.code !== 'TIMEOUT')) {
        if (err instanceof Error) {
          throw err;
        }
        throw new Error('搜索失败');
      }
    }
    const base = await DreamMusicAuth.base(context);
    const cacheKey = 'search|' + base + '|' + DreamMusicAuth.username(context) + '|' +
      keywords + '|' + offset;
    const cached = NetEaseApi.getCache(NetEaseApi.searchCache, cacheKey);
    if (cached !== null) {
      return cached;
    }
    const params: Record<string, string> = {};
    params['keywords'] = keywords;
    params['type'] = '1';
    params['limit'] = String(SEARCH_LIMIT);
    params['offset'] = String(offset);
    params['randomCNIP'] = 'true';
    const res: ApiJsonResult = await NetEaseApi.withQueryRetry<ApiJsonResult>(
      () => DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
        return ApiClient.getJson(base, '/search', params, headers);
      })
    );
    const wrapper = res.body as SearchResponse;
    ensureUpstreamOk(wrapper);
    const result = wrapper.result;
    if (result === undefined || result === null) {
      const empty: OnlineSong[] = [];
      const result: SearchPage = { songs: empty, hasMore: false };
      NetEaseApi.putCache(NetEaseApi.searchCache, cacheKey, result);
      return result;
    }
    const songs: OnlineSong[] = [];
    const raw = result.songs !== undefined ? result.songs : [];
    for (let i = 0; i < raw.length; i++) {
      const s = raw[i];
      const ar = s.ar !== undefined && s.ar.length > 0 ? s.ar[0].name : '';
      const artists = s.artists !== undefined && s.artists.length > 0 ? s.artists[0].name : '';
      const al = s.al !== undefined ? s.al : (s.album !== undefined ? s.album : undefined);
      let artist = '';
      if (ar !== undefined && ar !== '') {
        artist = ar;
      } else if (artists !== undefined && artists !== '') {
        artist = artists;
      }
      let albumName = '';
      let coverUrl = '';
      if (al !== undefined) {
        if (al.name !== undefined) {
          albumName = al.name;
        }
        if (al.picUrl !== undefined) {
          coverUrl = al.picUrl;
        }
      }
      const song: OnlineSong = {
        id: s.id !== undefined ? s.id : 0,
        name: s.name !== undefined ? s.name : '',
        artist: artist,
        album: albumName,
        coverUrl: coverUrl,
        durationMs: s.dt !== undefined ? s.dt : 0
      };
      songs.push(song);
    }
    const page: SearchPage = { songs: songs, hasMore: result.more === true };
    NetEaseApi.putCache(NetEaseApi.searchCache, cacheKey, page);
    return page;
  }

  private static async searchV2(context: common.Context, keywords: string, offset: number): Promise<SearchPage> {
    const base = await DreamMusicAuth.baseV2(context);
    const cacheKey = 'search-v2|' + base + '|' + DreamMusicAuth.username(context) + '|' +
      keywords + '|' + offset;
    const cached = NetEaseApi.getCache(NetEaseApi.searchCache, cacheKey);
    if (cached !== null) {
      return cached;
    }
    const params: Record<string, string> = {};
    params['keywords'] = keywords;
    params['limit'] = String(SEARCH_LIMIT);
    params['offset'] = String(offset);
    const res: ApiJsonResult = await NetEaseApi.withQueryRetry<ApiJsonResult>(
      () => DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
        return ApiClient.getJson(base, '/search', params, headers);
      })
    );
    const wrapper = res.body as MediaSearchResponse;
    ensureUpstreamOk(wrapper);
    const raw = wrapper.data !== undefined && wrapper.data !== null ? wrapper.data : [];
    const songs: OnlineSong[] = [];
    for (let i = 0; i < raw.length; i++) {
      const s = raw[i];
      const artists = s.artists !== undefined ? s.artists : [];
      const album: MediaAlbum = s.album !== undefined ? s.album : {};
      songs.push({
        id: s.source === 'api-enhanced' && s.legacyId !== undefined ? s.legacyId : 0,
        name: s.title !== undefined ? s.title : '',
        artist: artists.length > 0 ? artists[0] : '',
        album: album.name !== undefined ? album.name : '',
        coverUrl: album.pictureUrl !== undefined ? album.pictureUrl : '',
        durationMs: s.durationMs !== undefined ? s.durationMs : 0,
        mediaRef: s.mediaRef,
        source: s.source,
        sourceId: s.sourceId,
        catalogRef: s.catalogRef !== undefined ? s.catalogRef : s.mediaRef,
        playbackRef: s.playbackRef !== undefined ? s.playbackRef : s.mediaRef,
        lyricsRef: s.lyricsRef !== undefined ? s.lyricsRef : s.mediaRef,
        playbackSource: s.playbackSource,
        lyricsSource: s.lyricsSource
      });
    }
    const page: SearchPage = { songs: songs, hasMore: wrapper.hasMore === true };
    NetEaseApi.putCache(NetEaseApi.searchCache, cacheKey, page);
    return page;
  }

  /** 普通在线播放直链(level=exhigh;不执行解灰) */
  static async resolveUrl(context: common.Context, id: number, mediaRef: string = ''): Promise<string> {
    return (await NetEaseApi.resolvePlayback(context, id, mediaRef)).url;
  }

  /** 返回真实音频身份；旧调用仍可通过 resolveUrl 只取 URL。 */
  static async resolvePlayback(context: common.Context, id: number, mediaRef: string = ''): Promise<PlaybackResolution> {
    const versioned = mediaRef !== '';
    const base = versioned ? await DreamMusicAuth.baseV2(context) : await DreamMusicAuth.base(context);
    const params: Record<string, string> = {};
    if (versioned) {
      params['mediaRef'] = mediaRef;
    } else {
      params['id'] = String(id);
    }
    params['level'] = QUALITY_LEVEL;
    params['randomCNIP'] = 'true';
    const startedAt = Date.now();
    try {
      const res: ApiJsonResult = await NetEaseApi.withQueryRetry<ApiJsonResult>(
        () => DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
          return ApiClient.getJson(base, '/song/url/v1', params, headers);
        })
      );
      const wrapper = versioned ? res.body as MediaUrlResponse : res.body as SongUrlResponse;
      ensureUpstreamOk(wrapper);
      playbackDiagnostics.record({
        source: versioned ? 'media-ref' : 'api-enhanced',
        capability: 'media-resolution',
        stage: 'source_resolution',
        durationMs: Date.now() - startedAt,
        ok: true
      });
      const url = NetEaseApi.extractUrl(wrapper);
      playbackDiagnostics.record({
        source: versioned ? 'media-ref' : 'api-enhanced',
        capability: 'media-resolution',
        stage: 'url_response',
        durationMs: Date.now() - startedAt,
        ok: url !== '',
        errorCategory: url === '' ? DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL : undefined
      });
      const identity = res.body as MediaUrlResponse;
      return {
        url: url,
        catalogRef: versioned ? (identity.catalogRef !== undefined ? identity.catalogRef : mediaRef) : undefined,
        playbackRef: versioned ? (identity.playbackRef !== undefined ? identity.playbackRef : mediaRef) : undefined,
        lyricsRef: versioned ? (identity.lyricsRef !== undefined ? identity.lyricsRef : mediaRef) : undefined,
        playbackSource: identity.playbackSource,
        lyricsSource: identity.lyricsSource
      };
    } catch (err) {
      const e = err instanceof Error ? err : new Error('音乐源解析失败');
      const category = err instanceof ApiError && err.code === 'TIMEOUT'
        ? DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT
        : classifyPlaybackError('source_resolution', e.message);
      playbackDiagnostics.record({
        source: versioned ? 'media-ref' : 'api-enhanced',
        capability: 'media-resolution',
        stage: 'source_resolution',
        durationMs: Date.now() - startedAt,
        ok: false,
        errorCategory: category
      });
      throw e;
    }
  }

  /** 歌曲详情封面兜底(白名单 /song/detail;搜索未带 picUrl 时用) */
  static async songDetailCover(context: common.Context, id: number, mediaRef: string = ''): Promise<string> {
    const versioned = mediaRef !== '';
    const base = versioned ? await DreamMusicAuth.baseV2(context) : await DreamMusicAuth.base(context);
    const cacheKey = 'cover|' + base + '|' + DreamMusicAuth.username(context) + '|' +
      (versioned ? 'v2|' + mediaRef : String(id));
    const cached = NetEaseApi.getCache(NetEaseApi.coverCache, cacheKey);
    if (cached !== null) {
      return cached;
    }
    const params: Record<string, string> = {};
    if (versioned) {
      params['mediaRef'] = mediaRef;
    } else {
      params['ids'] = String(id);
    }
    params['randomCNIP'] = 'true';
    const res: ApiJsonResult = await NetEaseApi.withQueryRetry<ApiJsonResult>(
      () => DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
        return ApiClient.getJson(base, '/song/detail', params, headers);
      })
    );
    const wrapper = res.body as SongDetailResponse;
    ensureUpstreamOk(wrapper);
    if (versioned) {
      const data = (res.body as MediaDetailResponse).data;
      const pictureUrl = data !== undefined && data.length > 0 && data[0].album !== undefined
        && data[0].album.pictureUrl !== undefined ? data[0].album.pictureUrl : '';
      NetEaseApi.putCache(NetEaseApi.coverCache, cacheKey, pictureUrl);
      return pictureUrl;
    }
    const songs = wrapper.songs;
    if (songs === undefined || songs === null || songs.length === 0) {
      NetEaseApi.putCache(NetEaseApi.coverCache, cacheKey, '');
      return '';
    }
    const al = songs[0].al !== undefined ? songs[0].al
      : (songs[0].album !== undefined ? songs[0].album : undefined);
    if (al !== undefined && al.picUrl !== undefined && al.picUrl !== null && al.picUrl !== '') {
      NetEaseApi.putCache(NetEaseApi.coverCache, cacheKey, al.picUrl);
      return al.picUrl;
    }
    NetEaseApi.putCache(NetEaseApi.coverCache, cacheKey, '');
    return '';
  }

  /** 歌词正文(白名单为 /lyric/new;取 lrc.lyric,无则返回 '') */
  static async lyric(context: common.Context, id: number): Promise<string> {
    const raw = await NetEaseApi.lyricRaw(context, id);
    return raw.lrc;
  }

  /** 新版歌词原文(lrc + yrc;阶段 v2.3:lrc 缺失时用 yrc 兜底) */
  static async lyricRaw(context: common.Context, id: number, mediaRef: string = ''): Promise<LyricPayload> {
    const versioned = mediaRef !== '';
    const base = versioned ? await DreamMusicAuth.baseV2(context) : await DreamMusicAuth.base(context);
    const cacheKey = 'lyric|' + base + '|' + DreamMusicAuth.username(context) + '|' +
      (versioned ? 'v2|' + mediaRef : String(id));
    const cached = NetEaseApi.getCache(NetEaseApi.lyricCache, cacheKey);
    if (cached !== null) {
      return cached;
    }
    const params: Record<string, string> = {};
    if (versioned) {
      params['mediaRef'] = mediaRef;
    } else {
      params['id'] = String(id);
    }
    params['randomCNIP'] = 'true';
    const res: ApiJsonResult = await NetEaseApi.withQueryRetry<ApiJsonResult>(
      () => DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
        return ApiClient.getJson(base, '/lyric/new', params, headers);
      })
    );
    const wrapper = res.body as LyricNewResponse;
    ensureUpstreamOk(wrapper);
    let lrcText = '';
    if (wrapper.lrc !== undefined && wrapper.lrc !== null &&
      wrapper.lrc.lyric !== undefined && wrapper.lrc.lyric !== null) {
      lrcText = wrapper.lrc.lyric;
    }
    let yrcText = '';
    if (wrapper.yrc !== undefined && wrapper.yrc !== null &&
      wrapper.yrc.lyric !== undefined && wrapper.yrc.lyric !== null) {
      yrcText = wrapper.yrc.lyric;
    }
    const payload: LyricPayload = {
      lrc: lrcText, yrc: yrcText,
      lyricsRef: versioned ? (wrapper.lyricsRef !== undefined ? wrapper.lyricsRef : mediaRef) : undefined,
      lyricsSource: wrapper.lyricsSource
    };
    NetEaseApi.putCache(NetEaseApi.lyricCache, cacheKey, payload);
    return payload;
  }

  private static extractUrl(wrapper: SongUrlResponse): string {
    const data = wrapper.data;
    if (data === undefined || data === null || data.length === 0) {
      return '';
    }
    const url = data[0].url !== undefined ? data[0].url : '';
    return url === null ? '' : url;
  }

  private static async withQueryRetry<T>(request: () => Promise<T>): Promise<T> {
    let attempt = 0;
    let delay = RETRY_BASE_MS;
    while (true) {
      try {
        return await request();
      } catch (err) {
        const retryable = err instanceof ApiError &&
          (err.code === 'RATE_LIMIT' || err.code === 'UPSTREAM_503' || err.code === 'HTTP_503');
        if (!retryable || attempt >= MAX_QUERY_RETRIES) {
          if (err instanceof Error) {
            throw err;
          }
          throw new Error('查询失败');
        }
        await NetEaseApi.sleep(delay);
        delay = delay * 2;
        attempt++;
      }
    }
  }

  private static getCache<T>(cache: Map<string, CacheEntry<T>>, key: string): T | null {
    const item = cache.get(key);
    if (item === undefined) {
      return null;
    }
    if (item.expiresAt <= Date.now()) {
      cache.delete(key);
      return null;
    }
    return item.value;
  }

  private static putCache<T>(cache: Map<string, CacheEntry<T>>, key: string, value: T): void {
    cache.set(key, { value: value, expiresAt: Date.now() + QUERY_CACHE_TTL_MS });
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
