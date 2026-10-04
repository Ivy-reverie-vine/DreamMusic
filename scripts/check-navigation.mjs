// Node.js 24+: 执行真实返回方法与状态逻辑；不模拟 ArkUI 手势或设备布局。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8')
    .replace(/^import[\s\S]*?;\r?\n/gm, '')
    .replace(/^@Observed\r?\n/gm, '').replace(/^export /gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({ ${names.join(', ')} })`, dependencies);
}
// 只提取组件的普通方法；页面的 ArkUI builder 由 ArkTS 编译器验证。
function methods(path, names, dependencies) {
  const source = readFileSync(new URL(path, root), 'utf8');
  const bodies = names.map((name) => {
    const match = new RegExp(`\\n  (?:private )?${name}\\(`).exec(source);
    assert.ok(match, `Missing ${path}:${name}`);
    const start = match.index + 3;
    const brace = source.indexOf('{', start);
    let depth = 1;
    let end = brace + 1;
    while (depth > 0 && end < source.length) {
      if (source[end] === '{') depth += 1;
      if (source[end] === '}') depth -= 1;
      end += 1;
    }
    return source.slice(start, end).replace(/^private /, '');
  });
  return runInNewContext(stripTypeScriptTypes(`class Component { ${bodies.join('\n')} }\nnew Component()`,
    { mode: 'transform' }), dependencies);
}
const nav = load('model/Navigation.ets',
  ['RootTab', 'MySubpage', 'BackAction', 'BackDispatcher', 'resolveBack', 'openMyPage', 'selectRoot']);
const { RootTab, MySubpage, BackDispatcher } = nav;
const shell = methods('pages/IndexV2.ets', ['navigation', 'onBackPress', 'openMyPage', 'selectTab'], nav);
shell.childBack = new BackDispatcher();
shell.showLoginOverlay = shell.showBindAtStart = shell.loginPromptVisible = false;
for (const source of Object.values(RootTab).filter((v) => typeof v === 'number')) {
  shell.current = source;
  shell.myPage = MySubpage.HOME;
  shell.sourceRoot = source;
  for (const page of Object.values(MySubpage).filter((p) => p !== MySubpage.HOME)) {
    shell.openMyPage(page, source);
    shell.showLoginOverlay = true;
    assert.equal(shell.onBackPress(), true);
    assert.equal(shell.myPage, page);
    assert.equal(shell.showLoginOverlay, false);
    shell.showBindAtStart = true;
    assert.equal(shell.onBackPress(), true);
    assert.equal(shell.myPage, page);
    assert.equal(shell.showBindAtStart, false);
    assert.equal(shell.onBackPress(), true);
    assert.equal(shell.current, source);
    assert.equal(shell.myPage, MySubpage.HOME);
    assert.equal(shell.onBackPress(), false);
  }
}
shell.loginPromptVisible = true;
assert.equal(shell.onBackPress(), true);
assert.equal(shell.loginPromptVisible, false);
for (const tab of [RootTab.LIBRARY, RootTab.NOW_PLAYING, RootTab.QUEUE, RootTab.MY]) {
  shell.openMyPage(MySubpage.SETTINGS, RootTab.LIBRARY);
  shell.selectTab(tab);
  assert.equal(shell.current, tab);
  assert.equal(shell.myPage, MySubpage.HOME);
  assert.equal(shell.sourceRoot, tab);
}

const playlist = methods('pages/PlaylistsPage.ets',
  ['handleBack', 'closeOnlineDetail', 'aboutToAppear', 'aboutToDisappear', 'ctx'], {});
playlist.vm = { selected: { id: 1 }, selectedTracks: [1], load() {}, cancelOpen() {} };
playlist.playlistRequest = '';
playlist.requestVersion = 0;
playlist.onlineVm = { selectedPlaylist: null, selectedSongs: [], prefetch() {} };
playlist.getUIContext = () => ({ getHostContext: () => ({}) });
playlist.backDispatcher = shell.childBack;
playlist.onlineDetailMode = playlist.onlineParentMode = 0;
playlist.showRename = false;
playlist.aboutToAppear();
assert.equal(playlist.vm.selected, null, 'Reentry resets the shared playlist selection');
shell.openMyPage(MySubpage.PLAYLISTS);
playlist.vm.selected = { id: 2 };
playlist.vm.selectedTracks = [2];
playlist.showRename = true;
assert.equal(shell.onBackPress(), true);
assert.equal(playlist.showRename, false);
assert.equal(playlist.vm.selected.id, 2);
assert.equal(shell.myPage, MySubpage.PLAYLISTS);
assert.equal(shell.onBackPress(), true);
assert.equal(playlist.vm.selected, null);
assert.equal(playlist.vm.selectedTracks.length, 0);
assert.equal(shell.myPage, MySubpage.PLAYLISTS);
playlist.onlineDetailMode = 2;
playlist.onlineParentMode = 3;
assert.equal(shell.onBackPress(), true);
assert.equal(playlist.onlineDetailMode, 3);
assert.equal(shell.onBackPress(), true);
assert.equal(playlist.onlineDetailMode, 0);
assert.equal(shell.onBackPress(), true);
assert.equal(shell.myPage, MySubpage.HOME);
playlist.aboutToDisappear();
assert.equal(shell.childBack.handle(), false, 'Unmount removes the child handler');

const settings = methods('pages/SettingsPage.ets', ['handleBack'], {});
shell.openMyPage(MySubpage.SETTINGS, RootTab.LIBRARY);
settings.showSheet = true;
settings.sheetMode = 2;
shell.childBack.register('settings', 30, () => settings.handleBack());
assert.equal(shell.onBackPress(), true);
assert.equal(settings.showSheet, false);
assert.equal(settings.sheetMode, 0);
assert.equal(shell.myPage, MySubpage.SETTINGS);
assert.equal(shell.onBackPress(), true);
assert.equal(shell.current, RootTab.LIBRARY);
shell.childBack.unregister('settings');
shell.openMyPage(MySubpage.SETTINGS, RootTab.LIBRARY);
shell.openMyPage(MySubpage.SETTINGS, RootTab.MY);
assert.equal(shell.sourceRoot, RootTab.LIBRARY, 'Opening settings again from the resident player retains the original source');
assert.equal(shell.onBackPress(), true);
assert.equal(shell.current, RootTab.LIBRARY);

const library = methods('pages/MusicLibraryPage.ets', ['handleBack', 'closeDetail'], {});
library.vm = { load() {} };
library.showSheet = true;
library.sheetMode = 3;
library.detailAlbum = { name: 'Long album name' };
library.detailArtist = null;
library.detailTracks = [1];
library.showSearch = true;
shell.childBack.register('library', 20, () => library.handleBack());
assert.equal(shell.onBackPress(), true);
assert.equal(library.showSheet, false);
assert.ok(library.detailAlbum);
assert.equal(shell.onBackPress(), true);
assert.equal(library.detailAlbum, null);
assert.equal(library.detailTracks.length, 0);
assert.equal(library.showSearch, true);
assert.equal(shell.onBackPress(), true);
assert.equal(library.showSearch, false);
assert.equal(shell.onBackPress(), false);
shell.childBack.unregister('library');

const my = methods('pages/MyPageV2.ets', ['handleBack', 'pageChanged'], { MySubpage });
my.loadHome = () => {};
my.page = MySubpage.ANNOUNCEMENTS;
my.messageExpanded = true;
shell.openMyPage(MySubpage.ANNOUNCEMENTS);
shell.childBack.register('my', 20, () => my.handleBack());
assert.equal(shell.onBackPress(), true);
assert.equal(my.messageExpanded, false);
assert.equal(shell.myPage, MySubpage.ANNOUNCEMENTS);
assert.equal(shell.onBackPress(), true);
my.messageExpanded = true;
my.page = MySubpage.HOME;
my.pageChanged();
assert.equal(my.messageExpanded, false);
let refreshed = 0;
my.page = MySubpage.STATS;
my.ctx = () => ({});
my.stats = { load() { refreshed += 1; } };
my.pageChanged();
assert.equal(refreshed, 1);
shell.childBack.unregister('my');
const order = [];
shell.childBack.register('parent', 20, () => { order.push('parent'); return true; });
shell.childBack.register('child', 30, () => { order.push('child'); return true; });
assert.equal(shell.childBack.handle(), true);
assert.deepEqual(order, ['child']);
shell.childBack.unregister('child');
shell.childBack.unregister('parent');

let loggedIn = false;
let profileFails = false;
let profile = { playSeconds: 0, playedSongCount: 0, syncedAt: 123456789 };
const auth = {
  async initialize() {}, isLoggedIn() { return loggedIn; },
  async profile() { if (profileFails) throw new Error('offline'); return profile; },
  async announcements() { throw new Error('offline'); },
  async pointLogs() { throw new Error('offline'); }
};
const store = { async localPlaybackStats() { return { playRecordCount: 4, customPlaylistCount: 2, favoriteCount: 1 }; } };
const { PlaybackStatsViewModel } = load('viewmodel/PlaybackStatsViewModel.ets', ['PlaybackStatsViewModel'],
  { DreamMusicAuth: auth, LibraryStore: { getInstance: () => store } });
const stats = new PlaybackStatsViewModel();
await stats.load({});
assert.equal(stats.accountState, 'unauthenticated');
assert.equal(stats.hasAccountData, false);
loggedIn = profileFails = true;
await stats.load({});
assert.equal(stats.accountState, 'unavailable');
assert.equal(stats.hasAccountData, false, 'Failure without a snapshot must not display default zero');
assert.equal(stats.local.playRecordCount, 4, 'Account failure leaves device data usable');
profileFails = false;
await stats.load({});
assert.equal(stats.accountState, 'success-zero');
assert.equal(stats.hasAccountData, true, 'A verified zero is displayable');
profile = { playSeconds: 120, playedSongCount: 3, syncedAt: 123456790 };
await stats.load({});
assert.equal(stats.accountState, 'success');
profileFails = true;
await stats.refresh({});
assert.equal(stats.accountState, 'stale');
assert.equal(stats.hasAccountData, true);
assert.equal(stats.account.playedSongCount, 3);
loggedIn = false;
await stats.load({});
assert.equal(stats.hasAccountData, false, 'Logout hides the previous account snapshot');

const { AccountViewModel } = load('viewmodel/AccountViewModel.ets', ['AccountViewModel'], { DreamMusicAuth: auth });
const account = new AccountViewModel();
await account.loadAnnouncements({});
assert.equal(account.announcementsLoading, false);
assert.ok(account.announcementsError);
account.loggedIn = true;
await account.loadPointLogs({});
assert.equal(account.pointLogsLoading, false);
assert.ok(account.pointLogsError);
auth.announcements = auth.pointLogs = async () => [];
await account.loadAnnouncements({});
await account.loadPointLogs({});
assert.equal(account.announcementsError, '');
assert.equal(account.pointLogsError, '');

let libraryFails = true;
const libraryStore = {
  async listTracks() { if (libraryFails) throw new Error('unavailable'); return [{ id: 1 }]; },
  async listAlbums() { return []; }, async listArtists() { return []; }, async listFavoritesTrackIds() { return [1]; }
};
const { LibraryViewModel } = load('viewmodel/LibraryViewModel.ets', ['LibraryViewModel'],
  { LibraryStore: { getInstance: () => libraryStore } });
const libraryVm = new LibraryViewModel();
await libraryVm.load();
assert.equal(libraryVm.loading, false);
assert.ok(libraryVm.loadError);
libraryFails = false;
await libraryVm.load();
assert.equal(libraryVm.loadError, '');
assert.equal(libraryVm.tracks.length, 1);
assert.equal(libraryVm.favoriteIds.has(1), true);

let resolveTracks;
const { PlaylistsViewModel } = load('viewmodel/PlaylistsViewModel.ets', ['PlaylistsViewModel'], {
  LibraryStore: { getInstance: () => ({ listPlaylistTracks: () => new Promise((resolve) => { resolveTracks = resolve; }) }) }
});
const playlists = new PlaylistsViewModel();
const opening = playlists.openPlaylist({ id: 1 });
playlists.selected = null;
playlists.selectedTracks = [];
resolveTracks([1]);
await opening;
assert.equal(playlists.selected, null);
assert.equal(playlists.selectedTracks.length, 0, 'A late detail response does not repopulate an exited page');
console.log('Navigation, child back dispatch, reentry and unavailable/zero/stale data checks passed.');
