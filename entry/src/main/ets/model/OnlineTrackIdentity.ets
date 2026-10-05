import { OnlineSong, Track } from './Entities';

/** Queue IDs identify selections, never platform numeric IDs or expiring URLs. */
let nextOnlineId: number = -2;

export function createOnlineTrack(song: OnlineSong): Track {
  const catalogRef = song.catalogRef !== undefined ? song.catalogRef : song.mediaRef;
  const netease = song.source === undefined || song.source === 'api-enhanced';
  return {
    id: nextOnlineId--, path: 'music/online-stream.mp3',
    title: song.name, artist: song.artist, album: song.album, durationMs: song.durationMs,
    coverPath: '', importedAt: Date.now(), missing: false,
    neteaseId: netease && song.id > 0 ? song.id : 0, streamUrl: '', streamCoverUrl: song.coverUrl,
    mediaRef: song.mediaRef, catalogRef: catalogRef,
    automaticSearchSession: song.automaticSearchSession,
    playbackRef: song.playbackRef !== undefined ? song.playbackRef : song.mediaRef,
    lyricsRef: song.lyricsRef !== undefined ? song.lyricsRef : song.mediaRef,
    playbackSource: song.playbackSource, lyricsSource: song.lyricsSource
  };
}

/** Only a confirmed NetEase audio resource may use the existing numeric-ID store. */
export function canDownloadNetEase(track: Track): boolean {
  if (track.neteaseId <= 0 || track.playbackSource !== 'api-enhanced' ||
    track.audioIntegrity?.status !== 'full') { return false; }
  const ref = track.playbackRef !== undefined ? track.playbackRef : '';
  const catalog = track.catalogRef !== undefined ? track.catalogRef : '';
  // Cross-resource NetEase migration is outside this slice too: no guessing another resource's ID.
  return ref === catalog;
}
