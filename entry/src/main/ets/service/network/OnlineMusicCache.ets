import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREF_NAME = 'ivy_online_cache';
const KEY_SNAPSHOT = 'snapshot';

export interface CachedPlaylist {
  id: number;
  name: string;
  coverUrl: string;
  trackCount: number;
  description: string;
  creatorName: string;
  creatorUid: number;
}

export interface CachedSong {
  id: number;
  name: string;
  artist: string;
  album: string;
  coverUrl: string;
  durationMs: number;
}

export interface OnlineMusicCacheRecord {
  accountKey: string;
  savedAt: number;
  playlists: CachedPlaylist[];
  likedSongs: CachedSong[];
}

/**
 * 在线资料缓存仅用于加速页面打开，不是账户事实源。
 * 账户/绑定变化时清理；网络请求成功后覆盖。
 */
export class OnlineMusicCache {
  static accountKey(username: string, uid: string): string {
    return username + '|' + uid;
  }

  static read(context: common.Context, accountKey: string): OnlineMusicCacheRecord | null {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const raw = prefs.getSync(KEY_SNAPSHOT, '') as string;
      if (raw === '') {
        return null;
      }
      const record = JSON.parse(raw) as OnlineMusicCacheRecord;
      return record.accountKey === accountKey ? record : null;
    } catch (err) {
      return null;
    }
  }

  static write(context: common.Context, record: OnlineMusicCacheRecord): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.putSync(KEY_SNAPSHOT, JSON.stringify(record));
      prefs.flush();
    } catch (err) {
      // 缓存失败不影响在线请求和本地播放。
    }
  }

  static clear(context: common.Context): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.deleteSync(KEY_SNAPSHOT);
      prefs.flush();
    } catch (err) {
      // 清理失败不影响退出登录。
    }
  }
}
