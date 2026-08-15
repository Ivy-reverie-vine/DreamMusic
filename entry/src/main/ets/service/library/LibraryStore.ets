import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { QueueSnapshot } from '../playback/QueueEngine';
import {
  Track, Album, Artist, Playlist, PlayHistoryEntry, ServerProfile,
  PLAY_HISTORY_LIMIT, FAVORITES_PLAYLIST_NAME
} from '../../model/Entities';

const DOMAIN = 0x0000;
const TAG = 'LibraryStore';
const DB_NAME = 'ivy.db';

/** 播放队列持久化记录(issue-06/13:含洗牌序,重启延续随机周期) */
export interface PlayerStateRecord {
  queue: number[];
  currentIndex: number;
  mode: string;
  positionMs: number;
  shuffleOrder: number[];
  shufflePos: number;
  shuffleSteps: number;
}

/**
 * 音乐库存储适配层(issue-02):relationalStore 8 张物理表。
 * 所有 schema 变更收在本文件;上层只见领域接口不见 SQL。
 * 真机验证项:建表幂等、路径唯一约束、历史 500 滚动、CRUD。
 */
export class LibraryStore {
  private static instance: LibraryStore | null = null;
  private store: relationalStore.RdbStore | null = null;

  static getInstance(): LibraryStore {
    if (LibraryStore.instance === null) {
      LibraryStore.instance = new LibraryStore();
    }
    return LibraryStore.instance;
  }

  /** 应用启动时调用一次(幂等) */
  async init(context: common.Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.createSchema();
    await this.ensureSystemPlaylist();
  }

  get isReady(): boolean {
    return this.store !== null;
  }

  private db(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('LibraryStore 未初始化,先调用 init(context)');
    }
    return this.store;
  }

  private async createSchema(): Promise<void> {
    const ddl: string[] = [
      `CREATE TABLE IF NOT EXISTS tracks (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         path TEXT NOT NULL UNIQUE,
         title TEXT NOT NULL DEFAULT '',
         artist TEXT NOT NULL DEFAULT '',
         album TEXT NOT NULL DEFAULT '',
         duration_ms INTEGER NOT NULL DEFAULT 0,
         cover_path TEXT NOT NULL DEFAULT '',
         imported_at INTEGER NOT NULL DEFAULT 0,
         missing INTEGER NOT NULL DEFAULT 0
       )`,
      `CREATE TABLE IF NOT EXISTS albums (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         name TEXT NOT NULL UNIQUE,
         artist TEXT NOT NULL DEFAULT '',
         track_count INTEGER NOT NULL DEFAULT 0
       )`,
      `CREATE TABLE IF NOT EXISTS artists (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         name TEXT NOT NULL UNIQUE,
         track_count INTEGER NOT NULL DEFAULT 0
       )`,
      `CREATE TABLE IF NOT EXISTS playlists (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         name TEXT NOT NULL,
         system_reserved INTEGER NOT NULL DEFAULT 0,
         created_at INTEGER NOT NULL DEFAULT 0
       )`,
      `CREATE TABLE IF NOT EXISTS playlist_tracks (
         playlist_id INTEGER NOT NULL,
         track_id INTEGER NOT NULL,
         position INTEGER NOT NULL DEFAULT 0,
         PRIMARY KEY (playlist_id, track_id)
       )`,
      `CREATE TABLE IF NOT EXISTS play_history (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         track_id INTEGER NOT NULL,
         played_at INTEGER NOT NULL DEFAULT 0
       )`,
      `CREATE TABLE IF NOT EXISTS favorites (
         track_id INTEGER PRIMARY KEY,
         created_at INTEGER NOT NULL DEFAULT 0
       )`,
      `CREATE TABLE IF NOT EXISTS server_profiles (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         alias TEXT NOT NULL,
         url TEXT NOT NULL,
         is_current INTEGER NOT NULL DEFAULT 0,
         last_status INTEGER NOT NULL DEFAULT 0
       )`,
      `CREATE TABLE IF NOT EXISTS player_state (
         id INTEGER PRIMARY KEY CHECK (id = 1),
         queue TEXT NOT NULL DEFAULT '[]',
         current_index INTEGER NOT NULL DEFAULT -1,
         mode TEXT NOT NULL DEFAULT 'SEQUENTIAL',
         position_ms INTEGER NOT NULL DEFAULT 0
       )`
    ];
    for (const sql of ddl) {
      await this.db().executeSql(sql);
    }
    await this.migratePlayerState();
  }

  /** 旧库补列(issue-13:洗牌序持久化;列已存在时忽略) */
  private async migratePlayerState(): Promise<void> {
    const cols: string[] = [
      "shuffle_order TEXT NOT NULL DEFAULT '[]'",
      'shuffle_pos INTEGER NOT NULL DEFAULT -1',
      'shuffle_steps INTEGER NOT NULL DEFAULT 0'
    ];
    for (const c of cols) {
      try {
        await this.db().executeSql('ALTER TABLE player_state ADD COLUMN ' + c);
      } catch (err) {
        // 列已存在(重复启动幂等)
      }
    }
  }

  private async ensureSystemPlaylist(): Promise<void> {
    const pred = new relationalStore.RdbPredicates('playlists');
    pred.equalTo('system_reserved', 1);
    const rs = await this.db().query(pred);
    const hasReserved = rs.rowCount > 0;
    rs.close();
    if (!hasReserved) {
      const values: relationalStore.ValuesBucket = {
        'name': FAVORITES_PLAYLIST_NAME,
        'system_reserved': 1,
        'created_at': Date.now()
      };
      await this.db().insert('playlists', values);
    }
  }

  // ---------- tracks ----------

  /** 按唯一键(沙箱相对路径)插入;重复路径被数据库约束拒绝 → 返回 -1 */
  async insertTrack(t: Track): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'path': t.path,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'duration_ms': t.durationMs,
      'cover_path': t.coverPath,
      'imported_at': t.importedAt
    };
    return await this.db().insert('tracks', values);
  }

  async getTrackByPath(path: string): Promise<Track | null> {
    const pred = new relationalStore.RdbPredicates('tracks');
    pred.equalTo('path', path);
    const rs = await this.db().query(pred);
    if (rs.goToFirstRow()) {
      const t = this.rowToTrack(rs);
      rs.close();
      return t;
    }
    rs.close();
    return null;
  }

  async listTracks(): Promise<Track[]> {
    const pred = new relationalStore.RdbPredicates('tracks');
    pred.orderByAsc('title');
    const rs = await this.db().query(pred);
    const out: Track[] = [];
    while (rs.goToNextRow()) {
      out.push(this.rowToTrack(rs));
    }
    rs.close();
    return out;
  }

  async deleteTrack(id: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('tracks');
    pred.equalTo('id', id);
    await this.db().delete(pred);
  }

  private rowToTrack(rs: relationalStore.ResultSet): Track {
    return {
      id: rs.getLong(rs.getColumnIndex('id')),
      path: rs.getString(rs.getColumnIndex('path')),
      title: rs.getString(rs.getColumnIndex('title')),
      artist: rs.getString(rs.getColumnIndex('artist')),
      album: rs.getString(rs.getColumnIndex('album')),
      durationMs: rs.getLong(rs.getColumnIndex('duration_ms')),
      coverPath: rs.getString(rs.getColumnIndex('cover_path')),
      importedAt: rs.getLong(rs.getColumnIndex('imported_at')),
      missing: rs.getLong(rs.getColumnIndex('missing')) === 1
    };
  }

  // ---------- 扫描状态(issue-04) ----------

  async markMissing(path: string): Promise<void> {
    const values: relationalStore.ValuesBucket = { 'missing': 1 };
    const pred = new relationalStore.RdbPredicates('tracks');
    pred.equalTo('path', path);
    await this.db().update(values, pred);
  }

  async markPresent(path: string): Promise<void> {
    const values: relationalStore.ValuesBucket = { 'missing': 0 };
    const pred = new relationalStore.RdbPredicates('tracks');
    pred.equalTo('path', path);
    await this.db().update(values, pred);
  }

  /** 迁移旧路径数据(issue-14:兼容无 music/ 前缀的历史记录) */
  async renameTrackPath(oldPath: string, newPath: string): Promise<void> {
    const values: relationalStore.ValuesBucket = { 'path': newPath };
    const pred = new relationalStore.RdbPredicates('tracks');
    pred.equalTo('path', oldPath);
    await this.db().update(values, pred);
  }

  async decrementAlbumCount(name: string): Promise<void> {
    await this.db().executeSql(
      'UPDATE albums SET track_count = track_count - 1 WHERE name = ? AND track_count > 0', [name]);
  }

  async decrementArtistCount(name: string): Promise<void> {
    await this.db().executeSql(
      'UPDATE artists SET track_count = track_count - 1 WHERE name = ? AND track_count > 0', [name]);
  }

  // ---------- albums / artists ----------

  async upsertAlbum(name: string, artist: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('albums');
    pred.equalTo('name', name);
    const rs = await this.db().query(pred);
    if (rs.goToFirstRow()) {
      const id = rs.getLong(rs.getColumnIndex('id'));
      rs.close();
      await this.db().executeSql('UPDATE albums SET track_count = track_count + 1 WHERE id = ?', [id]);
      return;
    }
    rs.close();
    const values: relationalStore.ValuesBucket = {
      'name': name,
      'artist': artist,
      'track_count': 1
    };
    await this.db().insert('albums', values);
  }

  async upsertArtist(name: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('artists');
    pred.equalTo('name', name);
    const rs = await this.db().query(pred);
    if (rs.goToFirstRow()) {
      const id = rs.getLong(rs.getColumnIndex('id'));
      rs.close();
      await this.db().executeSql('UPDATE artists SET track_count = track_count + 1 WHERE id = ?', [id]);
      return;
    }
    rs.close();
    const values: relationalStore.ValuesBucket = {
      'name': name,
      'track_count': 1
    };
    await this.db().insert('artists', values);
  }

  /** 专辑/艺术家聚合统一入口(导入与扫描共用;空值守卫在此统一) */
  async indexTrackMeta(meta: Track): Promise<void> {
    if (meta.artist !== '') {
      await this.upsertArtist(meta.artist);
    }
    if (meta.album !== '' || meta.artist !== '') {
      await this.upsertAlbum(meta.album, meta.artist);
    }
  }

  async listAlbums(): Promise<Album[]> {
    const rs = await this.db().querySql('SELECT * FROM albums ORDER BY name');
    const out: Album[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        artist: rs.getString(rs.getColumnIndex('artist')),
        trackCount: rs.getLong(rs.getColumnIndex('track_count'))
      });
    }
    rs.close();
    return out;
  }

  async listArtists(): Promise<Artist[]> {
    const rs = await this.db().querySql('SELECT * FROM artists ORDER BY name');
    const out: Artist[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        trackCount: rs.getLong(rs.getColumnIndex('track_count'))
      });
    }
    rs.close();
    return out;
  }

  // ---------- playlists ----------

  async insertPlaylist(name: string): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'name': name,
      'system_reserved': 0,
      'created_at': Date.now()
    };
    return await this.db().insert('playlists', values);
  }

  async renamePlaylist(id: number, name: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('playlists');
    pred.equalTo('id', id);
    pred.equalTo('system_reserved', 0); // 系统保留歌单不可重命名
    const values: relationalStore.ValuesBucket = { 'name': name };
    await this.db().update(values, pred);
  }

  async deletePlaylist(id: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('playlists');
    pred.equalTo('id', id);
    pred.equalTo('system_reserved', 0); // 系统保留歌单不可删除
    await this.db().delete(pred);
  }

  async listPlaylists(): Promise<Playlist[]> {
    const rs = await this.db().querySql('SELECT * FROM playlists ORDER BY system_reserved DESC, created_at');
    const out: Playlist[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        systemReserved: rs.getLong(rs.getColumnIndex('system_reserved')) === 1,
        createdAt: rs.getLong(rs.getColumnIndex('created_at'))
      });
    }
    rs.close();
    return out;
  }

  async addTrackToPlaylist(playlistId: number, trackId: number): Promise<void> {
    const rs = await this.db().querySql(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_pos FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId]);
    let pos = 0;
    if (rs.goToFirstRow()) {
      pos = rs.getLong(rs.getColumnIndex('next_pos'));
    }
    rs.close();
    const values: relationalStore.ValuesBucket = {
      'playlist_id': playlistId,
      'track_id': trackId,
      'position': pos
    };
    await this.db().insert('playlist_tracks', values);
  }

  async removeTrackFromPlaylist(playlistId: number, trackId: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('playlist_tracks');
    pred.equalTo('playlist_id', playlistId);
    pred.equalTo('track_id', trackId);
    await this.db().delete(pred);
  }

  /** 收藏音轨 id(按收藏时间倒序)——"我喜欢的音乐"聚合来源 */
  async listFavoritesTrackIds(): Promise<number[]> {
    const rs = await this.db().querySql('SELECT track_id FROM favorites ORDER BY created_at DESC');
    const out: number[] = [];
    while (rs.goToNextRow()) {
      out.push(rs.getLong(rs.getColumnIndex('track_id')));
    }
    rs.close();
    return out;
  }

  /** 歌单曲目 id(按顺序):系统保留歌单实时聚合收藏 */
  async listPlaylistTracks(playlist: Playlist): Promise<number[]> {
    if (playlist.systemReserved) {
      return await this.listFavoritesTrackIds();
    }
    const rs = await this.db().querySql(
      'SELECT track_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position', [playlist.id]);
    const out: number[] = [];
    while (rs.goToNextRow()) {
      out.push(rs.getLong(rs.getColumnIndex('track_id')));
    }
    rs.close();
    return out;
  }

  // ---------- favorites(收藏 = 单曲级标记,聚合进"我喜欢的音乐") ----------

  async toggleFavorite(trackId: number): Promise<boolean> {
    const pred = new relationalStore.RdbPredicates('favorites');
    pred.equalTo('track_id', trackId);
    const rs = await this.db().query(pred);
    const exists = rs.goToFirstRow();
    rs.close();
    if (exists) {
      await this.db().delete(pred);
      return false;
    }
    const values: relationalStore.ValuesBucket = {
      'track_id': trackId,
      'created_at': Date.now()
    };
    await this.db().insert('favorites', values);
    return true;
  }

  async isFavorite(trackId: number): Promise<boolean> {
    const pred = new relationalStore.RdbPredicates('favorites');
    pred.equalTo('track_id', trackId);
    const rs = await this.db().query(pred);
    const exists = rs.goToFirstRow();
    rs.close();
    return exists;
  }

  // ---------- play history(500 条滚动淘汰) ----------

  async insertHistory(trackId: number): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'track_id': trackId,
      'played_at': Date.now()
    };
    await this.db().insert('play_history', values);
    await this.db().executeSql(
      `DELETE FROM play_history WHERE id NOT IN
         (SELECT id FROM play_history ORDER BY played_at DESC, id DESC LIMIT ?)`,
      [PLAY_HISTORY_LIMIT]);
  }

  async listHistory(): Promise<PlayHistoryEntry[]> {
    const rs = await this.db().querySql(
      'SELECT * FROM play_history ORDER BY played_at DESC LIMIT ?',
      [PLAY_HISTORY_LIMIT]);
    const out: PlayHistoryEntry[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        trackId: rs.getLong(rs.getColumnIndex('track_id')),
        playedAt: rs.getLong(rs.getColumnIndex('played_at'))
      });
    }
    rs.close();
    return out;
  }

  async clearHistory(): Promise<void> {
    await this.db().executeSql('DELETE FROM play_history');
  }

  // ---------- server profiles(issue-10) ----------

  async insertProfile(alias: string, url: string): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'alias': alias,
      'url': url,
      'is_current': 0,
      'last_status': 0
    };
    return await this.db().insert('server_profiles', values);
  }

  async listProfiles(): Promise<ServerProfile[]> {
    const rs = await this.db().querySql('SELECT * FROM server_profiles ORDER BY id');
    const out: ServerProfile[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        alias: rs.getString(rs.getColumnIndex('alias')),
        url: rs.getString(rs.getColumnIndex('url')),
        isCurrent: rs.getLong(rs.getColumnIndex('is_current')) === 1,
        lastStatus: rs.getLong(rs.getColumnIndex('last_status'))
      });
    }
    rs.close();
    return out;
  }

  async setCurrentProfile(id: number): Promise<void> {
    await this.db().executeSql('UPDATE server_profiles SET is_current = 0');
    const values: relationalStore.ValuesBucket = { 'is_current': 1 };
    const pred = new relationalStore.RdbPredicates('server_profiles');
    pred.equalTo('id', id);
    await this.db().update(values, pred);
  }

  async deleteProfile(id: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('server_profiles');
    pred.equalTo('id', id);
    await this.db().delete(pred);
  }

  // ---------- 播放队列持久化(issue-06/13) ----------

  async savePlayerState(snap: QueueSnapshot, positionMs: number): Promise<void> {
    const queueJson = JSON.stringify(snap.tracks);
    await this.db().executeSql('DELETE FROM player_state WHERE id = 1');
    const values: relationalStore.ValuesBucket = {
      'id': 1,
      'queue': queueJson,
      'current_index': snap.currentIndex,
      'mode': snap.mode,
      'position_ms': positionMs,
      'shuffle_order': JSON.stringify(snap.shuffleOrder),
      'shuffle_pos': snap.shufflePos,
      'shuffle_steps': snap.shuffleSteps
    };
    await this.db().insert('player_state', values);
  }

  async loadPlayerState(): Promise<PlayerStateRecord | null> {
    const rs = await this.db().querySql('SELECT * FROM player_state WHERE id = 1');
    if (!rs.goToFirstRow()) {
      rs.close();
      return null;
    }
    const queueJson = rs.getString(rs.getColumnIndex('queue'));
    let shuffleOrder: number[] = [];
    try {
      const raw = rs.getString(rs.getColumnIndex('shuffle_order'));
      if (raw !== '') {
        shuffleOrder = JSON.parse(raw) as number[];
      }
    } catch (err) {
      shuffleOrder = [];
    }
    const out: PlayerStateRecord = {
      queue: JSON.parse(queueJson) as number[],
      currentIndex: rs.getLong(rs.getColumnIndex('current_index')),
      mode: rs.getString(rs.getColumnIndex('mode')),
      positionMs: rs.getLong(rs.getColumnIndex('position_ms')),
      shuffleOrder: shuffleOrder,
      shufflePos: rs.getLong(rs.getColumnIndex('shuffle_pos')),
      shuffleSteps: rs.getLong(rs.getColumnIndex('shuffle_steps'))
    };
    rs.close();
    return out;
  }

  // ---------- util ----------

  close(): void {
    this.store = null;
  }

  static log(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', msg);
  }
}
