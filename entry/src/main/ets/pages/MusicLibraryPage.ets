import { ThemeService } from '../service/theme/ThemeService';
import { ImportService } from '../service/library/ImportService';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { QueueViewModel, queueViewModel } from '../viewmodel/QueueViewModel';
import { playlistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { Track, Album, Artist, Playlist } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { EmptyState } from '../components/EmptyState';
import {
  FONT_TITLE, FONT_BODY, FONT_LABEL, RADIUS_CARD, RADIUS_CAPSULE, RADIUS_CONTROL,
  SHADOW_CARD_RADIUS, SHADOW_CARD_COLOR, SHADOW_CARD_OFFSET_Y
} from '../common/DesignTokens';

/**
 * 音乐库页(issue-03/04 + issue-12 视觉):
 * 歌曲/专辑/艺术家三视图,行带封面缩略图 + 柔和阴影卡片,图标全部 SymbolGlyph。
 */
@Component
export struct MusicLibraryPage {
  @Prop theme: ThemeService;
  @State vm: LibraryViewModel = new LibraryViewModel();
  @State qvm: QueueViewModel = queueViewModel;
  @State tab: number = 0;
  @State importStatus: string = '';
  @State addTrack: Track | null = null;
  @State showAdd: boolean = false;

  @Builder
  addPanel() {
    Column({ space: 10 }) {
      ForEach(playlistsViewModel.playlists, (p: Playlist) => {
        if (!p.systemReserved) {
          Row() {
            Text(p.name)
              .fontSize(FONT_BODY)
              .fontColor(this.theme.ink)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(RADIUS_CONTROL)
          .backgroundColor(this.theme.card)
          .onClick(() => {
            if (this.addTrack !== null) {
              playlistsViewModel.addToPlaylist(p.id, this.addTrack.id);
            }
            this.showAdd = false;
          })
        }
      })
      if (playlistsViewModel.playlists.filter((p: Playlist) => !p.systemReserved).length === 0) {
        Text('还没有自建歌单,先去歌单页新建')
          .fontSize(13)
          .fontColor(this.theme.muted)
      }
    }
    .width('100%')
    .padding(16)
  }

  aboutToAppear(): void {
    this.vm.load();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private coverUri(t: Track): string {
    return t.coverPath !== '' ? 'file://' + this.ctx().filesDir + '/' + t.coverPath : '';
  }

  async importFiles(): Promise<void> {
    const context = this.ctx();
    this.importStatus = '选择文件中…';
    let sources: string[] = [];
    try {
      sources = await ImportService.pickAudioFiles(context);
    } catch (err) {
      this.importStatus = '文件选择失败: ' + (err as Error).message;
      return;
    }
    if (sources.length === 0) {
      this.importStatus = '未选择文件';
      return;
    }
    this.importStatus = `导入 0/${sources.length}`;
    const result = await ImportService.importSources(context, sources, (done: number, total: number): void => {
      this.importStatus = `导入 ${done}/${total}`;
    });
    this.importStatus = `完成:导入 ${result.imported},跳过 ${result.skipped},重复 ${result.duplicates}` +
      (result.failed > 0 ? `,失败 ${result.failed}:${result.lastError}` : '');
    await this.vm.load();
  }

  async importFolder(): Promise<void> {
    const context = this.ctx();
    this.importStatus = '选择文件夹中…';
    let sources: string[] = [];
    try {
      sources = await ImportService.pickAudioFolder(context);
    } catch (err) {
      // 手机等设备可能不支持文件夹选择模式(DocumentSelectMode.FOLDER 仅 2-in-1)
      this.importStatus = '文件夹选择失败: ' + (err as Error).message;
      return;
    }
    if (sources.length === 0) {
      this.importStatus = '文件夹中没有支持的音频';
      return;
    }
    const result = await ImportService.importSources(context, sources, (done: number, total: number): void => {
      this.importStatus = `导入 ${done}/${total}`;
    });
    this.importStatus = `完成:导入 ${result.imported},跳过 ${result.skipped},重复 ${result.duplicates}` +
      (result.failed > 0 ? `,失败 ${result.failed}:${result.lastError}` : '');
    await this.vm.load();
  }

  confirmRemove(track: Track): void {
    const context = this.ctx();
    this.getUIContext().showAlertDialog({
      title: track.title !== '' ? track.title : track.path,
      message: '从音乐库移除,或连同沙箱文件一起删除?',
      primaryButton: {
        value: '仅出库',
        action: () => {
          this.vm.removeTrack(context, track, false);
        }
      },
      secondaryButton: {
        value: '连文件删除',
        action: () => {
          this.vm.removeTrack(context, track, true);
        }
      }
    });
  }

  @Builder
  TrackList() {
    List({ space: 10 }) {
      ForEach(this.vm.tracks, (t: Track, index: number) => {
        ListItem() {
          Row({ space: 12 }) {
            CoverThumb({ theme: this.theme, uri: this.coverUri(t), thumbSize: 44 })
            Column({ space: 3 }) {
              Text(t.title !== '' ? t.title : t.path)
                .fontSize(FONT_BODY)
                .fontWeight(queueViewModel.currentId === t.id ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.theme.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${t.artist}${t.album !== '' ? ' · ' + t.album : ''}${t.missing ? ' · 文件缺失' : ''}`)
                .fontSize(FONT_LABEL)
                .fontColor(t.missing ? this.theme.secondary : this.theme.muted)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph(this.vm.favoriteIds.has(t.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(21)
              .fontColor([this.vm.favoriteIds.has(t.id) ? this.theme.primary : this.theme.muted])
              .padding(4)
              .onClick(() => {
                this.vm.toggleFavorite(t.id);
              })
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(20)
              .fontColor([this.theme.muted])
              .padding(4)
              .onClick(() => {
                this.addTrack = t;
                this.showAdd = true;
              })
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor([this.theme.muted])
              .padding(5)
              .onClick(() => {
                this.confirmRemove(t);
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(RADIUS_CARD)
          .backgroundColor(this.theme.card)
          .border({
            width: queueViewModel.currentId === t.id && !t.missing ? 1 : 0,
            color: ThemeService.alpha(this.theme.primary, 0.5)
          })
          .shadow({ radius: SHADOW_CARD_RADIUS, color: SHADOW_CARD_COLOR, offsetX: 0, offsetY: SHADOW_CARD_OFFSET_Y })
          .onClick(() => {
            if (!t.missing) {
              // 点歌:来源列表成为播放队列,从点击处开始
              queueViewModel.playFromList(this.vm.tracks, index, this.ctx());
            }
          })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  AlbumList() {
    List({ space: 10 }) {
      ForEach(this.vm.albums, (a: Album) => {
        ListItem() {
          Row({ space: 12 }) {
            Column()
              .width(44)
              .height(44)
              .borderRadius(11)
              .linearGradient({
                angle: 135,
                colors: [
                  [ThemeService.alpha(this.theme.primary, 0.42), 0.0],
                  [ThemeService.alpha(this.theme.secondary, 0.28), 1.0]
                ]
              })
            Column({ space: 3 }) {
              Text(a.name !== '' ? a.name : '未知专辑')
                .fontSize(FONT_BODY)
                .fontColor(this.theme.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${a.artist} · ${a.trackCount} 首`)
                .fontSize(FONT_LABEL)
                .fontColor(this.theme.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(RADIUS_CARD)
          .backgroundColor(this.theme.card)
          .shadow({ radius: SHADOW_CARD_RADIUS, color: SHADOW_CARD_COLOR, offsetX: 0, offsetY: SHADOW_CARD_OFFSET_Y })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  ArtistList() {
    List({ space: 10 }) {
      ForEach(this.vm.artists, (a: Artist) => {
        ListItem() {
          Row({ space: 12 }) {
            Column()
              .width(44)
              .height(44)
              .borderRadius(22)
              .linearGradient({
                angle: 135,
                colors: [
                  [ThemeService.alpha(this.theme.secondary, 0.45), 0.0],
                  [ThemeService.alpha(this.theme.primary, 0.3), 1.0]
                ]
              })
            Column({ space: 3 }) {
              Text(a.name !== '' ? a.name : '未知艺术家')
                .fontSize(FONT_BODY)
                .fontColor(this.theme.ink)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${a.trackCount} 首`)
                .fontSize(FONT_LABEL)
                .fontColor(this.theme.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(RADIUS_CARD)
          .backgroundColor(this.theme.card)
          .shadow({ radius: SHADOW_CARD_RADIUS, color: SHADOW_CARD_COLOR, offsetX: 0, offsetY: SHADOW_CARD_OFFSET_Y })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  build() {
    Column({ space: 16 }) {
      Text('音乐库')
        .fontSize(FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .width('100%')

      Row({ space: 8 }) {
        ForEach(['歌曲', '专辑', '艺术家'], (item: string, index: number) => {
          Text(item)
            .fontSize(14)
            .fontWeight(index === this.tab ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.tab ? this.theme.primary : this.theme.muted)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(RADIUS_CAPSULE)
            .backgroundColor(index === this.tab ? ThemeService.alpha(this.theme.primary, 0.16) : this.theme.transparent)
            .onClick(() => {
              this.tab = index;
            })
        })
        Blank()
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(14)
            .fontColor([this.theme.primary])
          Text('扫描')
            .fontSize(13)
            .fontColor(this.theme.primary)
        }
        .padding(6)
        .borderRadius(RADIUS_CAPSULE)
        .onClick(() => {
          this.vm.rescan(this.ctx());
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(15)
            .fontColor([this.theme.ink])
          Text('导入文件')
            .fontSize(13)
            .fontColor(this.theme.ink)
        }
        .padding({ left: 16, right: 16, top: 9, bottom: 9 })
        .borderRadius(RADIUS_CAPSULE)
        .backgroundColor(this.theme.primary)
        .onClick(() => {
          this.importFiles();
        })
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(15)
            .fontColor([this.theme.ink])
          Text('导入文件夹')
            .fontSize(13)
            .fontColor(this.theme.ink)
        }
        .padding({ left: 16, right: 16, top: 9, bottom: 9 })
        .borderRadius(RADIUS_CAPSULE)
        .backgroundColor(this.theme.secondary)
        .onClick(() => {
          this.importFolder();
        })
        Text(this.importStatus !== '' ? this.importStatus : this.vm.statusText)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (this.tab === 0) {
        if (this.vm.tracks.length === 0) {
          EmptyState({
            theme: this.theme,
            symbol: $r('sys.symbol.music_note_list'),
            title: '这里还是空的',
            hint: '用上方按钮导入 MP3/AAC(M4A)/FLAC/WAV'
          })
        } else {
          this.TrackList()
        }
      } else if (this.tab === 1) {
        if (this.vm.albums.length === 0) {
          EmptyState({
            theme: this.theme,
            symbol: $r('sys.symbol.rectangle_stack'),
            title: '还没有专辑',
            hint: '导入带专辑信息的音乐后会按专辑聚合'
          })
        } else {
          this.AlbumList()
        }
      } else {
        if (this.vm.artists.length === 0) {
          EmptyState({
            theme: this.theme,
            symbol: $r('sys.symbol.person'),
            title: '还没有艺术家',
            hint: '导入带艺术家信息的音乐后会按艺术家聚合'
          })
        } else {
          this.ArtistList()
        }
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .bindSheet(this.showAdd, this.addPanel(), {
      height: 420,
      title: { title: '添加到歌单' }
    })
  }
}
