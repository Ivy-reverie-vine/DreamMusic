// Node.js 24+: 在主机检查纯逻辑及异步歌词状态，Kit 调用用边界替身。
// 不替代 ArkUI 布局、触摸、动画或真机播放验收。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';

const sourceRoot = new URL('../entry/src/main/ets/', import.meta.url);
function loadSource(path, exports, dependencies = {}) {
  const source = readFileSync(new URL(path, sourceRoot), 'utf8')
    .replace(/^import .+;\r?\n/gm, '')
    .replace(/^@Observed\r?\n/gm, '')
    .replace(/^export /gm, '');
  const javascript = stripTypeScriptTypes(source, { mode: 'transform' });
  return runInNewContext(`${javascript}\n({ ${exports.join(', ')} })`, dependencies, {
    filename: fileURLToPath(new URL(path, sourceRoot))
  });
}

const { LyricFollowState } = loadSource('service/lyrics/LyricFollowState.ets', ['LyricFollowState']);
const parser = loadSource('service/lyrics/LrcParser.ets', ['parseLrc', 'parseYrc', 'findActiveLine']);
const follow = new LyricFollowState();
follow.reset(1);
assert.equal(follow.nextIndex(-1, 1), 0);
assert.equal(follow.nextIndex(0, 1), null);
assert.equal(follow.nextIndex(1, 1), 1);
assert.equal(follow.nextIndex(1, 1), null);
follow.pause(1);
assert.equal(follow.nextIndex(2, 1), null);
follow.resume();
assert.equal(follow.nextIndex(2, 1), 2);
assert.equal(follow.nextIndex(2, 1), null);
// 同一行恢复浏览也必须重新对齐；向后 seek 必须滚回。
follow.pause(1);
follow.resume();
assert.equal(follow.nextIndex(2, 1), 2);
assert.equal(follow.nextIndex(0, 1), 0);
follow.pause(1);
assert.equal(follow.nextIndex(0, 2), 0);
// 新歌词挂载后、第一次轮询之前触摸，不得被 revision 检查抢回。
follow.pause(3);
assert.equal(follow.nextIndex(1, 3), null);

const playerViewModel = { currentTrack: null, positionMs: 0 };
const pending = [];
let localLyrics = null;
let localReads = 0;
const { lyricsViewModel: lyrics, LyricsLoadState: state } = loadSource(
  'viewmodel/LyricsViewModel.ets', ['lyricsViewModel', 'LyricsLoadState'], {
    ...parser,
    playerViewModel,
    LrcLoader: { loadForTrack() { localReads += 1; return localLyrics; } },
    NetEaseApi: {
      lyricRaw() {
        return new Promise((resolve, reject) => { pending.push({ resolve, reject }); });
      }
    }
  }
);
const changeTrack = (track) => {
  playerViewModel.currentTrack = track;
  playerViewModel.trackChangeHandler(track);
};
const local = { path: 'music/local.mp3' };
const online = { path: '', streamUrl: 'https://example.invalid/audio', neteaseId: 1 };
const flush = () => new Promise((resolve) => setImmediate(resolve));

assert.equal(lyrics.loadState, state.IDLE);
changeTrack(local);
assert.equal(lyrics.loadState, state.LOADING);
lyrics.setContext({ filesDir: '/sandbox' });
assert.equal(lyrics.loadState, state.EMPTY);
// 确认缺失后不持续读取；允许保留现有的一次补查。
playerViewModel.positionTickHandler(1000);
const checkedReads = localReads;
playerViewModel.positionTickHandler(2000);
assert.equal(localReads, checkedReads);
localLyrics = parser.parseLrc('[00:01]本地歌词');
changeTrack(local);
assert.equal(lyrics.loadState, state.READY);

changeTrack(online);
assert.equal(lyrics.loadState, state.LOADING);
assert.equal(lyrics.lines.length, 0);
const first = pending.shift();
playerViewModel.positionTickHandler(4000);
assert.equal(lyrics.loadState, state.LOADING);
lyrics.setContext({ filesDir: '/sandbox' });
assert.equal(pending.length, 0); // 重新进入播放页不重复发起请求。
playerViewModel.positionMs = 4000;
first.resolve({ lrc: '[00:01]第一句\n[00:03]第二句', yrc: '' });
await flush();
assert.equal(lyrics.loadState, state.READY);
assert.equal(lyrics.activeIndex, 1);

changeTrack(online);
pending.shift().resolve({ lrc: '', yrc: '' });
await flush();
assert.equal(lyrics.loadState, state.EMPTY);
changeTrack(online);
pending.shift().reject(new Error('network unavailable'));
await flush();
assert.equal(lyrics.loadState, state.ERROR);

// 快速切歌：旧请求的成功和失败都不能覆盖新歌。
changeTrack(online);
const staleSuccess = pending.shift();
changeTrack(online);
const current = pending.shift();
staleSuccess.resolve({ lrc: '[00:00]旧歌', yrc: '' });
await flush();
assert.equal(lyrics.loadState, state.LOADING);
assert.equal(lyrics.lines.length, 0);
current.resolve({ lrc: '', yrc: '[0,1000](0,100,0)新歌' });
await flush();
assert.equal(lyrics.loadState, state.READY);
assert.equal(lyrics.lines[0].text, '新歌');
changeTrack(online);
const staleFailure = pending.shift();
changeTrack(local);
staleFailure.reject(new Error('old request failed'));
await flush();
assert.equal(lyrics.loadState, state.READY);
assert.equal(lyrics.lines[0].text, '本地歌词');

console.log('PASS: lyric follow transitions, manual browsing, seek, loading/empty/error, context recovery and stale requests.');
