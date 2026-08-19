import { common } from '@kit.AbilityKit';
import { ApiClient, ApiError, ApiJsonResult } from './ApiClient';
import { DreamMusicAuth } from './DreamMusicAuth';
import { OnlineSong } from '../../model/Entities';
import { OnlineMusicCache, CachedPlaylist, CachedSong } from './OnlineMusicCache';

export interface OnlinePlaylistSummary {
  id: number;
  name: string;
  coverUrl: string;
  trackCount: number;
  description: string;
  creatorName: string;
  creatorUid: number;
}

export interface OnlinePlaylistPage {
  playlists: OnlinePlaylistSummary[];
  hasMore: boolean;
}

interface RawArtist {
  name?: string;
}

interface RawAlbum {
  name?: string;
  picUrl?: string;
}

interface RawCreator {
  nickname?: string;
  userId?: number;
}

interface RawSong {
  id?: number;
  name?: string;
  ar?: RawArtist[];
  artists?: RawArtist[];
  al?: RawAlbum;
  album?: RawAlbum;
  dt?: number;
}

interface PlaylistRaw {
  id?: number;
  name?: string;
  coverImgUrl?: string;
  picUrl?: string;
  trackCount?: number;
  description?: string;
  creator?: RawCreator;
}

interface UserPlaylistResponse extends UpstreamErrorEnvelope {
  playlist?: PlaylistRaw[];
  more?: boolean;
}

interface PlaylistTracksResponse extends UpstreamErrorEnvelope {
  songs?: RawSong[];
  more?: boolean;
}

interface SongDetailResponse extends UpstreamErrorEnvelope {
  songs?: RawSong[];
}

interface LikeResponse extends UpstreamErrorEnvelope {}

interface LikeListResponse extends UpstreamErrorEnvelope {
  ids?: number[];
}

interface UpstreamErrorEnvelope {
  code?: number;
  message?: string;
}

interface CachedOnlineData {
  playlists: OnlinePlaylistSummary[];
  likedSongs: OnlineSong[];
}

interface PlaylistSongsPage {
  songs: OnlineSong[];
  hasMore: boolean;
}

/**
 * 在线网易云音乐资料流:
 * - 歌单/我喜欢只读取服务端绑定账号数据,不复制成“第二份权威账户状态”;
 * - 红心操作直接写入网易云绑定账号,成功后由调用方刷新列表;
 * - 所有请求走 NightDream + X-API-Key,不携带网易云 Cookie。
 */
export class OnlineMusicService {
  static cached(context: common.Context): CachedOnlineData {
    const accountKey = OnlineMusicCache.accountKey(
      DreamMusicAuth.username(context), DreamMusicAuth.neteaseUid(context));
    const record = OnlineMusicCache.read(context, accountKey);
    if (record === null) {
      return { playlists: [], likedSongs: [] };
    }
    return {
      playlists: record.playlists as OnlinePlaylistSummary[],
      likedSongs: record.likedSongs as OnlineSong[]
    };
  }

  static clearCache(context: common.Context): void {
    OnlineMusicCache.clear(context);
  }

  static async prefetch(context: common.Context): Promise<void> {
    if (!DreamMusicAuth.isLoggedIn(context) || !DreamMusicAuth.isBound(context)) {
      return;
    }
    await OnlineMusicService.playlists(context, 0, 30);
    await OnlineMusicService.likedSongs(context);
  }

  static async playlists(context: common.Context, offset: number = 0,
    limit: number = 30): Promise<OnlinePlaylistPage> {
    const uid = await OnlineMusicService.ensureUid(context);
    const base = await DreamMusicAuth.base(context);
    const params: Record<string, string> = {};
    params['uid'] = uid;
    params['limit'] = String(Math.max(1, Math.min(100, limit)));
    params['offset'] = String(Math.max(0, offset));
    params['randomCNIP'] = 'true';
    const res = await OnlineMusicService.get(context, base, '/user/playlist', params);
    const body = res.body as UserPlaylistResponse;
    OnlineMusicService.ensureUpstreamOk(body);
    const raw = body.playlist !== undefined && body.playlist !== null ? body.playlist : [];
    const playlists: OnlinePlaylistSummary[] = [];
    for (let i = 0; i < raw.length; i++) {
      const p = raw[i];
      const creator = p.creator;
      const summary: OnlinePlaylistSummary = {
        id: p.id !== undefined ? p.id : 0,
        name: p.name !== undefined ? p.name : '',
        coverUrl: p.coverImgUrl !== undefined && p.coverImgUrl !== ''
          ? p.coverImgUrl : (p.picUrl !== undefined ? p.picUrl : ''),
        trackCount: p.trackCount !== undefined ? p.trackCount : 0,
        description: p.description !== undefined ? p.description : '',
        creatorName: creator !== undefined && creator.nickname !== undefined
          ? creator.nickname : '',
        creatorUid: creator !== undefined && creator.userId !== undefined
          ? creator.userId : 0
      };
      playlists.push(summary);
    }
    OnlineMusicService.writePlaylistCache(context, playlists);
    const page: OnlinePlaylistPage = { playlists: playlists, hasMore: body.more === true };
    return page;
  }

  static async playlistSongs(context: common.Context, playlistId: number,
    offset: number = 0, limit: number = 1000): Promise<PlaylistSongsPage> {
    const base = await DreamMusicAuth.base(context);
    const params: Record<string, string> = {};
    params['id'] = String(playlistId);
    params['limit'] = String(Math.max(1, Math.min(1000, limit)));
    params['offset'] = String(Math.max(0, offset));
    params['randomCNIP'] = 'true';
    const res = await OnlineMusicService.get(context, base, '/playlist/track/all', params);
    const body = res.body as PlaylistTracksResponse;
    OnlineMusicService.ensureUpstreamOk(body);
    const songs = OnlineMusicService.mapSongs(body.songs);
    const page: PlaylistSongsPage = { songs: songs, hasMore: body.more === true };
    return page;
  }

  static async allPlaylistSongs(context: common.Context, playlistId: number): Promise<OnlineSong[]> {
    const all: OnlineSong[] = [];
    let offset = 0;
    while (true) {
      const page = await OnlineMusicService.playlistSongs(context, playlistId, offset, 1000);
      all.push(...page.songs);
      if (!page.hasMore || page.songs.length === 0) {
        return all;
      }
      offset += page.songs.length;
    }
  }

  static async likedSongIds(context: common.Context): Promise<number[]> {
    const uid = await OnlineMusicService.ensureUid(context);
    const base = await DreamMusicAuth.base(context);
    const params: Record<string, string> = {};
    params['uid'] = uid;
    params['randomCNIP'] = 'true';
    const res = await OnlineMusicService.get(context, base, '/likelist', params);
    const body = res.body as LikeListResponse;
    OnlineMusicService.ensureUpstreamOk(body);
    return body.ids !== undefined && body.ids !== null ? body.ids : [];
  }

  static async likedSongs(context: common.Context): Promise<OnlineSong[]> {
    const ids = await OnlineMusicService.likedSongIds(context);
    const all: OnlineSong[] = [];
    for (let start = 0; start < ids.length; start += 500) {
      const batch = ids.slice(start, Math.min(ids.length, start + 500));
      const base = await DreamMusicAuth.base(context);
      const params: Record<string, string> = {};
      params['ids'] = batch.join(',');
      params['randomCNIP'] = 'true';
      const res = await OnlineMusicService.get(context, base, '/song/detail', params);
      const body = res.body as SongDetailResponse;
      OnlineMusicService.ensureUpstreamOk(body);
      all.push(...OnlineMusicService.mapSongs(body.songs));
    }
    OnlineMusicService.writeLikedCache(context, all);
    return all;
  }

  static async setLiked(context: common.Context, songId: number, liked: boolean): Promise<void> {
    const base = await DreamMusicAuth.base(context);
    const params: Record<string, string> = {};
    params['id'] = String(songId);
    params['like'] = liked ? 'true' : 'false';
    params['randomCNIP'] = 'true';
    const res = await OnlineMusicService.get(context, base, '/like', params);
    const body = res.body as LikeResponse;
    OnlineMusicService.ensureUpstreamOk(body);
  }

  private static writePlaylistCache(context: common.Context,
    playlists: OnlinePlaylistSummary[]): void {
    const current = OnlineMusicService.cached(context);
    const accountKey = OnlineMusicCache.accountKey(
      DreamMusicAuth.username(context), DreamMusicAuth.neteaseUid(context));
    OnlineMusicCache.write(context, {
      accountKey: accountKey,
      savedAt: Date.now(),
      playlists: playlists as CachedPlaylist[],
      likedSongs: current.likedSongs as CachedSong[]
    });
  }

  private static writeLikedCache(context: common.Context, songs: OnlineSong[]): void {
    const current = OnlineMusicService.cached(context);
    const accountKey = OnlineMusicCache.accountKey(
      DreamMusicAuth.username(context), DreamMusicAuth.neteaseUid(context));
    OnlineMusicCache.write(context, {
      accountKey: accountKey,
      savedAt: Date.now(),
      playlists: current.playlists as CachedPlaylist[],
      likedSongs: songs as CachedSong[]
    });
  }

  private static async ensureUid(context: common.Context): Promise<string> {
    let uid = DreamMusicAuth.neteaseUid(context);
    if (uid === '') {
      const user = await DreamMusicAuth.me(context);
      uid = user !== null && user.neteaseUid !== undefined && user.neteaseUid !== null
        ? String(user.neteaseUid) : '';
    }
    if (uid === '') {
      throw new ApiError('NO_NETEASE_UID', '未获取到网易云 UID,请重新绑定');
    }
    return uid;
  }

  private static async get(context: common.Context, base: string, path: string,
    params: Record<string, string>): Promise<ApiJsonResult> {
    return DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
      return ApiClient.getJson(base, path, params, headers);
    });
  }

  private static ensureUpstreamOk(body: UpstreamErrorEnvelope): void {
    if (body.code !== undefined && body.code !== 200) {
      const message = body.message !== undefined && body.message !== ''
        ? body.message : '上游接口返回错误(' + body.code + ')';
      throw new ApiError('UPSTREAM_' + body.code, message);
    }
  }

  private static mapSongs(raw: RawSong[] | undefined): OnlineSong[] {
    const songs: OnlineSong[] = [];
    const list = raw !== undefined && raw !== null ? raw : [];
    for (let i = 0; i < list.length; i++) {
      const s = list[i];
      const artistList = s.ar !== undefined && s.ar.length > 0 ? s.ar
        : (s.artists !== undefined ? s.artists : []);
      const album = s.al !== undefined ? s.al : s.album;
      songs.push({
        id: s.id !== undefined ? s.id : 0,
        name: s.name !== undefined ? s.name : '',
        artist: artistList.length > 0 && artistList[0].name !== undefined
          ? artistList[0].name : '',
        album: album !== undefined && album.name !== undefined ? album.name : '',
        coverUrl: album !== undefined && album.picUrl !== undefined ? album.picUrl : '',
        durationMs: s.dt !== undefined ? s.dt : 0
      });
    }
    return songs;
  }
}
