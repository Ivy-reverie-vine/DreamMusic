// 主机运行实际 ArkTS；文件、Form Kit 和图像接口替身，不代表桌面/设备验收。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(path, names, dependencies = {}) {
  const source = readFileSync(new URL(path, root), 'utf8')
    .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^export (default )?/gm, '');
  return runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({${names.join(',')}})`,
    { Date, ...dependencies }, { filename: path });
}
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const flush = async () => { for (let n = 0; n < 8; n++) await new Promise(r => setImmediate(r)); };
const model = load('model/MusicCard.ets', ['MusicCardSnapshot', 'copyMusicCardSnapshot', 'cardSnapshotForDisplay',
  'isMusicCardCommand', 'MUSIC_FORM_NAME', 'MUSIC_FORM_METHOD', 'CARD_INK']);
const snapshot = new model.MusicCardSnapshot();
snapshot.state = 'playing'; snapshot.hasTrack = true; snapshot.updatedAt = 100;
assert.equal(model.cardSnapshotForDisplay(snapshot, 200).state, 'playing');
assert.equal(model.cardSnapshotForDisplay(snapshot, 50000).state, 'paused');
assert.equal(snapshot.state, 'playing', 'read normalization does not mutate live state');
assert.equal(model.isMusicCardCommand('delete'), false);

const files = new Map(), handles = new Map(); let fd = 0;
const fs = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_ONLY: 8 },
  accessSync: p => files.has(p), mkdirSync: p => files.set(p, ''),
  openSync(p, mode) { if (!(mode & 1) && !files.has(p)) throw Error('missing');
    if (mode & 1) files.set(p, ''); handles.set(++fd, p); return { fd }; },
  closeSync(n) { assert.ok(handles.delete(n)); },
  writeSync(n, data) { files.set(handles.get(n), data); },
  readTextSync(p) { if (!files.has(p)) throw Error('missing'); return files.get(p); },
  renameSync(a, b) { files.set(b, files.get(a)); files.delete(a); },
  listFileSync: dir => [...files.keys()].filter(p => p.startsWith(dir + '/')).map(p => p.slice(dir.length + 1)),
  unlinkSync: p => files.delete(p)
};
let forms = [{ formId: '1', formName: 'MusicCard' }, { formId: '2', formName: 'MusicCard' },
  { formId: '3', formName: 'OtherCard' }];
const updates = []; let updateGate = null, failId = '';
const formProvider = {
  async getPublishedRunningFormInfos() { return forms; },
  async updateForm(id, binding) {
    if (updateGate) { const gate = updateGate; updateGate = null; await gate.promise; }
    if (id === failId) throw Error('removed card');
    const imageFd = Object.values(binding.data.formImages)[0];
    if (imageFd !== undefined) assert.ok(handles.has(imageFd), 'fd alive through async update');
    updates.push({ id, ...binding.data });
  }
};
const formBindingData = { createFormBindingData: data => ({ data }) };
const { MusicFormStore } = load('service/form/MusicFormStore.ets', ['MusicFormStore'],
  { ...model, fileIo: fs, formProvider, formBindingData });
const context = { filesDir: '/app' };
MusicFormStore.save(context, snapshot);
assert.equal(MusicFormStore.read(context).state, 'paused');
assert.equal(handles.size, 0);
files.set('/app/music-form/cover-1-1.jpg', 'image'); snapshot.coverFile = 'cover-1-1.jpg';
failId = '1'; await assert.rejects(MusicFormStore.update(context, '1', snapshot));
assert.equal(handles.size, 0, 'failed update closes image'); failId = '';

let firstCover = deferred(), acquired = 0, returned = 0, packers = 0, releasedPackers = 0;
const CoverArtService = {
  identity: t => t?.id ?? '', resolve: (ctx, t) => t?.cover ?? '',
  getInstance: () => ({
    async acquire(ctx, uri) {
      acquired++;
      if (uri === 'slow') await firstCover.promise;
      return { pixelMap: { uri }, placeholder: uri === '', release() { returned++; } };
    }, async colors() { return { primary: '#78BFA8' }; }
  })
};
const image = { createImagePacker() { packers++; return {
  async packing(pm) { return pm.uri; }, async release() { releasedPackers++; }
}; } };
const { MusicFormPublisher } = load('service/form/MusicFormPublisher.ets', ['MusicFormPublisher'],
  { ...model, fileIo: fs, formProvider, MusicFormStore, CoverArtService, image, readableText: c => c });
const publisher = new MusicFormPublisher(context);
publisher.sync({ id: 'a', title: 'old', artist: 'a', cover: 'slow' }, 'playing', '正在播放', true);
await flush();
publisher.sync({ id: 'b', title: 'new', artist: 'b', cover: 'new' }, 'paused', '已暂停', true);
await flush(); firstCover.resolve(); await flush();
assert.equal(updates.at(-1).title, 'new'); assert.equal(updates.at(-1).state, 'paused');
assert.equal(files.get('/app/music-form/' + MusicFormStore.read(context).coverFile), 'new');
assert.deepEqual([...new Set(updates.map(u => u.id))].sort(), ['1', '2']);
assert.equal(returned, acquired, 'including stale cover leases'); assert.equal(packers, releasedPackers);
assert.equal(handles.size, 0);
const count = updates.length;
publisher.sync({ id: 'b', title: 'new', artist: 'b', cover: 'new' }, 'paused', '已暂停', true);
await flush(); assert.equal(updates.length, count, 'unchanged ticks do not update cards or decode images');
const previousImage = updates.at(-1).cover;
publisher.sync({ id: 'b', title: 'new', artist: 'b', cover: 'local-file' }, 'paused', '已暂停', true);
await flush();
assert.notEqual(updates.at(-1).cover, previousImage, 'new pixels get a new native memory key');
assert.ok(updates.at(-1).cover.startsWith('memory://cover-'));
forms = [{ formId: '2', formName: 'MusicCard' }];
const removalIndex = updates.length;
publisher.sync({ id: 'b', title: 'new', artist: 'b', cover: 'new' }, 'error', '请检查网络后重试', true);
await flush(); assert.equal(updates.at(-1).id, '2'); assert.equal(updates.at(-1).state, 'error');
assert.equal(updates.slice(removalIndex).some(u => u.id === '1'), false, 'removed card not retained');
const gate = deferred(); updateGate = gate;
publisher.sync({ id: 'b', title: 'new', artist: 'b', cover: 'new' }, 'playing', '正在播放', true);
await flush();
publisher.sync(null, 'idle', '请选择音乐', false); gate.resolve(); await flush();
assert.equal(updates.at(-1).hasTrack, false); assert.equal(updates.at(-1).cover, '');
assert.equal(updates.at(-1).canPlay, false, 'empty queue is unambiguous');
await publisher.dispose(); const disposedCount = updates.length;
publisher.sync({ id: 'c', title: 'late', cover: '' }, 'playing', '正在播放', true);
await flush(); assert.equal(updates.length, disposedCount); assert.equal(handles.size, 0);

// 独立 FormExtension 进程只能读取投影，不导入播放器；添加/刷新/多实例/移除。
const { MusicFormAbility } = load('entryformability/MusicFormAbility.ets', ['MusicFormAbility'], {
  FormExtensionAbility: class {}, MusicFormStore,
  formInfo: { FormParam: { IDENTITY_KEY: 'formId' }, VisibilityType: { FORM_VISIBLE: 1 } }
});
const extension = new MusicFormAbility(); extension.context = context;
const initial = extension.onAddForm({ parameters: { formId: '4' } });
assert.equal(initial.data.hasTrack, false); await flush(); assert.equal(updates.at(-1).id, '4');
extension.onUpdateForm('4'); extension.onRemoveForm('4'); await flush();
const removedCount = updates.length;
extension.onChangeFormVisibility({ 4: 1 }); await flush(); assert.equal(updates.length, removedCount);
const restarted = new MusicFormAbility(); restarted.context = context;
restarted.onUpdateForm('2'); await flush(); assert.equal(updates.at(-1).id, '2');
const config = JSON.parse(readFileSync(new URL('../entry/src/main/resources/base/profile/music_form_config.json', import.meta.url)));
assert.deepEqual(config.forms[0].supportDimensions, ['2*2', '2*4']);
assert.equal(config.forms[0].isDynamic, false); assert.equal(config.forms[0].updateEnabled, false);
assert.equal(config.forms[0].formVisibleNotify, true);
console.log('PASS: card projection, stale restart state, ordered multi-instance updates, image lifetime/stale loads, empty/error states, add/refresh/remove/restart and both form dimensions.');
