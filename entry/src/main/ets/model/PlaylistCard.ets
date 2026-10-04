import { Playlist, Track } from './Entities';

export const PLAYLIST_FORM_NAME: string = 'PlaylistCard';
export const PLAYLIST_FORM_ABILITY: string = 'PlaylistFormAbility';

export class PlaylistCardSnapshot {
  playlistId: number = 0;
  title: string = '我喜欢的音乐';
  summary: string = '正在读取本地歌单';
  action: string = '打开歌单';
  available: boolean = false;
}

/** 绑定的是稳定 ID；0 只用于首次添加时解析固定收藏歌单。 */
export function playlistCardSnapshot(id: number, playlist: Playlist | null, tracks: Track[]): PlaylistCardSnapshot {
  const snapshot = new PlaylistCardSnapshot();
  snapshot.playlistId = id;
  if (playlist === null) {
    snapshot.title = '歌单已删除';
    snapshot.summary = '原歌单已不存在，请在应用中选择歌单并重新添加卡片';
    snapshot.action = '查看本地歌单';
    return snapshot;
  }
  snapshot.playlistId = playlist.id;
  snapshot.title = playlist.name;
  snapshot.available = true;
  snapshot.summary = tracks.length === 0 ? '暂无歌曲 · 可在应用中添加' :
    `${tracks.length} 首 · ${tracks.slice(0, 3).map((track: Track) => track.title || '未命名歌曲').join(' / ')}`;
  return snapshot;
}
