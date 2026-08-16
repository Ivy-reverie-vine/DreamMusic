import { common } from '@kit.AbilityKit';
import { ApiClient, ApiError, ApiJsonResult } from './ApiClient';
import { DreamMusicAuth } from './DreamMusicAuth';
import { OnlineSong } from '../../model/Entities';

const SEARCH_LIMIT = 30;
/** 音质:exhigh(320k)。8/16 接入 DreamMusic 后走真实账号绑定,与网页端默认一致(此前匿名 standard 决策作废) */
const QUALITY_LEVEL = 'exhigh';

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

interface LyricNewResponse extends UpstreamEnvelope {
  lrc?: LyricLrc;
  yrc?: LyricLrc;
}

export interface LyricPayload {
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
  /** 单曲搜索(分页) */
  static async search(context: common.Context, keywords: string, offset: number): Promise<SearchPage> {
    const base = await DreamMusicAuth.base(context);
    const headers = await NetEaseApi.keyHeaders(context);
    const params: Record<string, string> = {};
    params['keywords'] = keywords;
    params['type'] = '1';
    params['limit'] = String(SEARCH_LIMIT);
    params['offset'] = String(offset);
    params['randomCNIP'] = 'true';
    const res: ApiJsonResult = await ApiClient.getJson(base, '/search', params, headers);
    const wrapper = res.body as SearchResponse;
    ensureUpstreamOk(wrapper);
    const result = wrapper.result;
    if (result === undefined || result === null) {
      const empty: OnlineSong[] = [];
      return { songs: empty, hasMore: false };
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
    return { songs: songs, hasMore: result.more === true };
  }

  /** 播放直链(level=exhigh;空 URL = 无版权/需会员) */
  static async resolveUrl(context: common.Context, id: number): Promise<string> {
    const base = await DreamMusicAuth.base(context);
    const headers = await NetEaseApi.keyHeaders(context);
    const params: Record<string, string> = {};
    params['id'] = String(id);
    params['level'] = QUALITY_LEVEL;
    params['randomCNIP'] = 'true';
    const res: ApiJsonResult = await ApiClient.getJson(base, '/song/url/v1', params, headers);
    const wrapper = res.body as SongUrlResponse;
    ensureUpstreamOk(wrapper);
    const data = wrapper.data;
    if (data === undefined || data === null || data.length === 0) {
      return '';
    }
    const url = data[0].url !== undefined ? data[0].url : '';
    return url === null ? '' : url;
  }

  /** 歌曲详情封面兜底(白名单 /song/detail;搜索未带 picUrl 时用) */
  static async songDetailCover(context: common.Context, id: number): Promise<string> {
    const base = await DreamMusicAuth.base(context);
    const headers = await NetEaseApi.keyHeaders(context);
    const params: Record<string, string> = {};
    params['ids'] = String(id);
    params['randomCNIP'] = 'true';
    const res: ApiJsonResult = await ApiClient.getJson(base, '/song/detail', params, headers);
    const wrapper = res.body as SongDetailResponse;
    ensureUpstreamOk(wrapper);
    const songs = wrapper.songs;
    if (songs === undefined || songs === null || songs.length === 0) {
      return '';
    }
    const al = songs[0].al !== undefined ? songs[0].al
      : (songs[0].album !== undefined ? songs[0].album : undefined);
    if (al !== undefined && al.picUrl !== undefined && al.picUrl !== null && al.picUrl !== '') {
      return al.picUrl;
    }
    return '';
  }

  /** 歌词正文(白名单为 /lyric/new;取 lrc.lyric,无则返回 '') */
  static async lyric(context: common.Context, id: number): Promise<string> {
    const raw = await NetEaseApi.lyricRaw(context, id);
    return raw.lrc;
  }

  /** 新版歌词原文(lrc + yrc;阶段 v2.3:lrc 缺失时用 yrc 兜底) */
  static async lyricRaw(context: common.Context, id: number): Promise<LyricPayload> {
    const base = await DreamMusicAuth.base(context);
    const headers = await NetEaseApi.keyHeaders(context);
    const params: Record<string, string> = {};
    params['id'] = String(id);
    params['randomCNIP'] = 'true';
    const res: ApiJsonResult = await ApiClient.getJson(base, '/lyric/new', params, headers);
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
    return { lrc: lrcText, yrc: yrcText };
  }

  /** 转发类接口统一鉴权头 */
  private static async keyHeaders(context: common.Context): Promise<Record<string, string>> {
    const out: Record<string, string> = {};
    out['X-API-Key'] = await DreamMusicAuth.ensureApiKey(context);
    return out;
  }
}
