/** 卡片只携带展示数据和命令，不携带队列、音频 URL 或凭据。 */
export const MUSIC_FORM_NAME: string = 'MusicCard';
export const MUSIC_FORM_METHOD: string = 'musicCardControl';
// 与 ThemeService 的深色角色一致；卡片不导入应用进程的主题/Kit 对象。
export const CARD_BG: string = '#0D0F10';
export const CARD_INK: string = '#F2F5F6';
export const CARD_MUTED: string = '#A8B0B3';

export class MusicCardSnapshot {
  title: string = '还没有播放的音乐';
  artist: string = '打开应用，选择一首歌';
  status: string = '暂无歌曲';
  state: string = 'idle';
  hasTrack: boolean = false;
  canPlay: boolean = false;
  coverFile: string = '';
  accent: string = CARD_INK;
  updatedAt: number = 0;
}

export interface MusicCardCommand {
  command: string;
}

export function isMusicCardCommand(command: string): boolean {
  return command === 'play' || command === 'pause' || command === 'previous' || command === 'next';
}

/** 进程被回收后不把磁盘上的 playing/preparing 当成正在运行的播放器。 */
export function cardSnapshotForDisplay(snapshot: MusicCardSnapshot, now: number): MusicCardSnapshot {
  const result = copyMusicCardSnapshot(snapshot);
  if ((result.state === 'playing' || result.state === 'preparing') &&
    (now < result.updatedAt || now - result.updatedAt > 45000)) {
    result.state = 'paused';
    result.status = '点按播放，恢复上次音乐';
    result.canPlay = result.hasTrack;
  }
  return result;
}

export function copyMusicCardSnapshot(snapshot: MusicCardSnapshot): MusicCardSnapshot {
  return {
    title: snapshot.title, artist: snapshot.artist, status: snapshot.status, state: snapshot.state,
    hasTrack: snapshot.hasTrack, canPlay: snapshot.canPlay, coverFile: snapshot.coverFile,
    accent: snapshot.accent, updatedAt: snapshot.updatedAt
  };
}
