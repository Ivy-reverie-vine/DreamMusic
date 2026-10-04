// Execute actual ArkTS logic on the host. Form Kit, storage and database use substitutes.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8')
    .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^@Observed\r?\n/gm, '')
    .replace(/^export (default )?/gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { Date, ...dependencies }, { filename: path });
}
function methods(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8');
  const bodies = names.map(name => {
    const match = new RegExp(`\\n  (?:private )?(?:async )?${name}\\(`).exec(source);
    assert.ok(match, name);
    const start = match.index + 3, brace = source.indexOf('{', start);
    let depth = 1, end = brace + 1;
    while (depth && end < source.length) {
      if (source[end] === '{') depth++;
      if (source[end] === '}') depth--;
      end++;
    }
    return source.slice(start, end).replace(/^private /, '');
  });
  return runInNewContext(stripTypeScriptTypes(`class Component { ${bodies.join('\n')} }\nnew Component()`,
    { mode: 'transform' }), dependencies);
}
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const flush = async () => { for (let i = 0; i < 8; i++) await new Promise(r => setImmediate(r)); };
const model = load('model/PlaylistCard.ets', ['PlaylistCardSnapshot', 'playlistCardSnapshot', 'PLAYLIST_FORM_NAME']);
const launch = load('model/PlaybackLaunch.ets', ['PlaybackLaunch', 'playbackLaunch', 'PLAYBACK_DESTINATION_KEY',
  'PLAYBACK_DESTINATION', 'PLAYLIST_DESTINATION', 'PLAYLIST_ID_KEY']);
const favorite = { id: 1, name: '我喜欢的音乐', systemReserved: true };
const custom = { id: 7, name: '通勤', systemReserved: false };
let playlists = [favorite, custom], tracks = [{ id: 10, title: '本地歌曲' }, { id: 11, title: '另一首歌' }];
let members = new Map([[1, [11]], [7, [10, 11, 404]]]), dbGate = null, dbFails = false;
const db = {
  async init() { if (dbGate) await dbGate.promise; if (dbFails) throw Error('database unavailable'); },
  async listPlaylists() { return playlists; }, async listTracks() { return tracks; },
  async listPlaylistTracks(p) { return members.get(p.id) ?? []; }
};
const LibraryStore = { getInstance: () => db };
const files = new Map(), handles = new Map(); let fd = 0;
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  accessSync: p => files.has(p), mkdirSync: p => files.set(p, ''),
  openSync(p) { files.set(p, ''); handles.set(++fd, p); return { fd }; },
  closeSync(n) { assert.ok(handles.delete(n)); },
  writeSync(n, data) { files.set(handles.get(n), data); },
  readTextSync(p) { if (!files.has(p)) throw Error('missing'); return files.get(p); },
  renameSync(a, b) { files.set(b, files.get(a)); files.delete(a); },
  unlinkSync(p) { files.delete(p); }
};
let forms = [{ formId: '91', formName: 'PlaylistCard' }, { formId: '92', formName: 'PlaylistCard' },
  { formId: '93', formName: 'MusicCard' }], updates = [], failId = '', updateGate = null;
const formProvider = {
  async getPublishedRunningFormInfos() { return forms; },
  async updateForm(id, binding) {
    if (id === failId) throw Error('removed');
    if (updateGate) { const gate = updateGate; updateGate = null; await gate.promise; }
    updates.push({ id, ...binding.data });
  }
};
const formBindingData = { createFormBindingData: data => ({ data }) };
const deps = { ...model, LibraryStore, fileIo, formProvider, formBindingData };
const { PlaylistFormStore: Store } = load('service/form/PlaylistFormStore.ets', ['PlaylistFormStore'], deps);
const ctx = { filesDir: '/app' };
const formInfo = { FormParam: { IDENTITY_KEY: 'id' }, VisibilityType: { FORM_VISIBLE: 1 } };
const { PlaylistFormAbility: Ability } = load('entryformability/PlaylistFormAbility.ets', ['PlaylistFormAbility'],
  { ...launch, ...model, FormExtensionAbility: class {}, PlaylistFormStore: Store, formInfo });
const ability = new Ability(); ability.context = ctx;
const initial = ability.onAddForm({ parameters: { id: '91', [launch.PLAYLIST_ID_KEY]: 7 } });
assert.equal(initial.data.playlistId, 7, 'early click must never open favorites for a custom card');
ability.onAddForm({ parameters: { id: '92' } });
await flush();
assert.equal(Store.readId(ctx, '91'), 7);
assert.equal(Store.readId(ctx, '92'), 1, 'default favorite resolves to stable ID');
assert.equal(updates.find(u => u.id === '91').summary, '2 首 · 本地歌曲 / 另一首歌', 'orphan track IDs are excluded');
assert.equal(updates.find(u => u.id === '92').title, '我喜欢的音乐');
ability.onAddForm({ parameters: { id: '91', [launch.PLAYLIST_ID_KEY]: 1 } });
await flush(); assert.equal(Store.readId(ctx, '91'), 7, 'duplicate add preserves binding');

playlists = [favorite, { ...custom, name: '通勤已更名' }]; members.set(7, []);
updates = []; await Store.refreshAll(ctx);
assert.equal(updates.find(u => u.id === '91').title, '通勤已更名');
assert.match(updates.find(u => u.id === '91').summary, /暂无歌曲/);
assert.deepEqual(updates.map(u => u.id).sort(), ['91', '92'], 'playback cards remain isolated');
members.set(7, [10]); members.set(1, []); await Store.refreshAll(ctx);
assert.match(updates.at(-1).summary, /暂无歌曲/, 'unfavorite refreshes favorite card');
tracks = []; await Store.refreshAll(ctx);
assert.match(updates.findLast(u => u.id === '91').summary, /暂无歌曲/, 'library track deletion refreshes count');
playlists = [favorite, { id: 8, name: '通勤已更名', systemReserved: false }];
await Store.refreshAll(ctx);
const deleted = updates.findLast(u => u.id === '91');
assert.equal(deleted.playlistId, 7); assert.equal(deleted.available, false); assert.equal(deleted.title, '歌单已删除');
assert.equal(Store.readId(ctx, '91'), 7, 'same-name replacement must not retarget the card');

const { PlaylistFormStore: Restarted } = load('service/form/PlaylistFormStore.ets', ['PlaylistFormStore'], deps);
assert.equal(Restarted.readId(ctx, '91'), 7); await Restarted.refreshAll(ctx);
failId = '91'; updates = []; await Restarted.refreshAll(ctx);
assert.equal(updates.at(-1).id, '92', 'one failed instance cannot block another'); failId = '';
dbFails = true; await Store.update(ctx, '91'); dbFails = false;
assert.equal(updates.at(-1).title, '暂时无法读取歌单'); assert.equal(updates.at(-1).playlistId, 7);

dbGate = deferred(); const pendingUpdate = Store.update(ctx, '91'); await flush();
ability.onRemoveForm('91'); dbGate.resolve(); dbGate = null; const count = updates.length;
await pendingUpdate; assert.equal(updates.length, count, 'removal during load cancels publication');
assert.throws(() => Store.readId(ctx, '91')); assert.equal(handles.size, 0);
assert.throws(() => Store.bind(ctx, '../escape', 7));
ability.onCastToNormalForm('92'); ability.onChangeFormVisibility({ '92': 1 }); await flush();
assert.equal(Store.readId(ctx, '92'), 1);

// Serialized native updates finish with newest data.
playlists = [favorite, custom]; tracks = [{ id: 10, title: '新曲名' }]; members.set(7, [10]);
Store.bind(ctx, '91', 7); const gate = deferred(); updateGate = gate;
const old = Store.update(ctx, '91'); await flush();
playlists = [favorite, { ...custom, name: '最新名字' }]; const latest = Store.update(ctx, '91');
gate.resolve(); await Promise.all([old, latest]); assert.equal(updates.at(-1).title, '最新名字');
console.log('PASS: per-instance add/favorites/rename/count/empty/delete/restart/remove, failure isolation and playback-card coexistence.');

// Exercise actual shell, EntryAbility, page and view model methods together.
const nav = load('model/Navigation.ets', ['RootTab', 'MySubpage', 'BackAction', 'BackDispatcher', 'resolveBack', 'selectRoot']);
const { PlaylistsViewModel } = load('viewmodel/PlaylistsViewModel.ets', ['PlaylistsViewModel'], { LibraryStore });
const vm = new PlaylistsViewModel();
const shell = methods('pages/IndexV2.ets', ['navigation', 'selectTab', 'openPlaybackEntry', 'openExternalEntry', 'onBackPress', 'checkGate'],
  { ...nav, ...launch, DreamMusicAuth: { initialize: async () => {}, isLoggedIn: () => false } });
shell.childBack = new nav.BackDispatcher(); shell.externalSequence = 0; shell.ctx = () => ctx;
shell.current = nav.RootTab.LIBRARY; shell.myPage = nav.MySubpage.HOME;
const page = methods('pages/PlaylistsPage.ets', ['consumePlaylistRequest', 'aboutToAppear', 'aboutToDisappear',
  'handleBack', 'closeOnlineDetail', 'ctx'], { LibraryStore });
page.getUIContext = () => ({ getHostContext: () => ctx }); page.vm = vm;
page.backDispatcher = shell.childBack; page.requestVersion = 0; page.mounted = false;
page.onlineVm = { prefetch() { throw Error('external local path must not require network'); } };
page.onPlaylistRequestConsumed = () => { shell.playlistRequest = ''; page.playlistRequest = ''; };
const { EntryAbility } = load('entryability/EntryAbility.ets', ['EntryAbility'], { UIAbility: class {}, ...launch });
const entry = new EntryAbility();
const want = id => ({ parameters: { [launch.PLAYBACK_DESTINATION_KEY]: launch.PLAYLIST_DESTINATION,
  [launch.PLAYLIST_ID_KEY]: id } });
entry.handlePlaybackWant(want(7));
launch.playbackLaunch.attach(target => shell.openExternalEntry(target));
assert.equal(shell.current, nav.RootTab.MY); assert.equal(shell.myPage, nav.MySubpage.PLAYLISTS);
page.playlistRequest = shell.playlistRequest; page.aboutToAppear(); await flush();
assert.equal(vm.selected.id, 7); assert.equal(vm.selectedTracks.length, 1);
await shell.checkGate(); assert.equal(shell.loginPromptVisible, false);
assert.equal(shell.playlistRequest, '', 'consumed request cannot replay after reentry');
assert.equal(shell.onBackPress(), true); assert.equal(vm.selected, null);
assert.equal(shell.onBackPress(), true); assert.equal(shell.myPage, nav.MySubpage.HOME);

// Warm entry replaces both pending initialization and in-flight playlist lookup.
dbGate = deferred(); entry.onNewWant(want(7), {}); page.playlistRequest = shell.playlistRequest; page.consumePlaylistRequest();
entry.onNewWant(want(1), {}); page.playlistRequest = shell.playlistRequest; page.consumePlaylistRequest();
dbGate.resolve(); dbGate = null; await flush(); assert.equal(vm.selected.id, 1);
dbGate = deferred(); const initializing = vm.openPlaylistId(7, ctx); await flush();
await vm.openPlaylist(favorite); dbGate.resolve(); dbGate = null; await initializing;
assert.equal(vm.selected.id, 1, 'manual selection cancels a route still waiting for database initialization');
dbFails = true; await vm.openPlaylistId(7, ctx); dbFails = false;
assert.equal(vm.selected, null); assert.match(vm.statusText, /暂时无法读取/);
let slow = deferred(); const readMembers = db.listPlaylistTracks;
db.listPlaylistTracks = async p => { if (p.id === 7) await slow.promise; return readMembers(p); };
const first = vm.openPlaylistId(7, ctx); await flush(); await vm.openPlaylistId(1, ctx); slow.resolve(); await first;
assert.equal(vm.selected.id, 1, 'older lookup cannot replace latest destination');
slow = deferred(); const cancelled = vm.openPlaylistId(7, ctx); await flush(); page.handleBack(); slow.resolve(); await cancelled;
assert.equal(vm.selected, null, 'back cancels pending detail'); db.listPlaylistTracks = readMembers;
playlists = [favorite, { id: 8, name: custom.name }]; await vm.openPlaylistId(7, ctx);
assert.equal(vm.selected, null); assert.match(vm.statusText, /已删除/);
await vm.openPlaylistId(0, ctx); assert.equal(vm.selected.id, 1);
page.aboutToDisappear(); assert.equal(shell.childBack.handle(), false);
launch.playbackLaunch.detach();
for (const invalid of [-1, 1.5, NaN, Infinity]) {
  launch.playbackLaunch.request(launch.PLAYLIST_DESTINATION, invalid);
  assert.equal(launch.playbackLaunch.pending, false);
}
console.log('PASS: cold/warm external entry, login-free local routing, stable ID, newest request wins, return/unmount cancellation and invalid targets.');

const my = methods('pages/MyPageV2.ets', ['aboutToAppear', 'pageChanged', 'handleBack'], nav);
let homeLoads = 0; my.backDispatcher = new nav.BackDispatcher(); my.loadHome = () => { homeLoads++; };
my.page = nav.MySubpage.PLAYLISTS; my.aboutToAppear(); assert.equal(homeLoads, 0);
my.page = nav.MySubpage.HOME; my.pageChanged(); assert.equal(homeLoads, 1, 'returning from local entry loads My home normally');

// Actual LibraryStore mutation notification points (native SQLite substituted).
const { LibraryStore: RealStore } = load('service/library/LibraryStore.ets', ['LibraryStore'], {
  relationalStore: { RdbPredicates: class { equalTo() {} } }
});
const real = new RealStore(); let notifications = 0, exists = false;
const rs = { goToFirstRow: () => exists, close() {}, getColumnIndex: () => 0, getLong: () => 0 };
real.store = { async insert() { return 20; }, async update() {}, async delete() {}, async querySql() { return rs; },
  async query() { return rs; } };
real.onPlaylistContentChanged = () => { notifications++; };
await real.insertPlaylist('新歌单'); await real.renamePlaylist(7, '改名'); await real.deletePlaylist(7);
await real.addTrackToPlaylist(7, 10); await real.removeTrackFromPlaylist(7, 10); await real.deleteTrack(10);
await real.toggleFavorite(10); exists = true; await real.toggleFavorite(10);
assert.equal(notifications, 8);
real.onPlaylistContentChanged = () => { throw Error('form refresh failure'); };
await real.renamePlaylist(7, '仍然成功');
console.log('PASS: persisted local writes notify cards, and refresh errors do not break library operations.');
