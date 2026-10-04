import { ThemeService } from '../service/theme/ThemeService';
import { BackDispatcher } from '../model/Navigation';
import { ImportService } from '../service/library/ImportService';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { QueueViewModel, queueViewModel } from '../viewmodel/QueueViewModel';
import { PlayerViewModel, playerViewModel } from '../viewmodel/PlayerViewModel';
import { playlistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { Track, Album, Artist, Playlist } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { EmptyState } from '../components/EmptyState';
import { OnlineSearchView } from '../components/OnlineSearchView';
import {
  FONT_TITLE, FONT_BODY, FONT_LABEL, RADIUS_CARD, RADIUS_CAPSULE, RADIUS_CONTROL,
  SHADOW_CARD_RADIUS, SHADOW_CARD_OFFSET_Y
} from '../common/DesignTokens';

/**
 * 音乐库页(issue-03/04 + issue-12/13):
 * 歌曲/专辑/艺术家三视图;专辑/艺术家可点开详情子视图(issue-13 闭环 PRD story 14/15);
 * 顶部无实色块(tab 用圆点指示,按钮用浅色 tint);文件夹导入移除(手机不支持);
 * 点歌/播放失败有状态反馈。
 */
@Component
export struct MusicLibraryPage {
  backDispatcher: BackDispatcher = new BackDispatcher();
  @State theme: ThemeService = ThemeService.getInstance();
  /** 跳转设置 tab(登录/绑定引导,阶段 v2.1) */
  onGoSettings: () => void = () => {
  };
  /** 在线功能触发登录盖层(阶段 v2.2:本地歌不登录可听) */
  onGoLogin: () => void = () => {
  };
  @State vm: LibraryViewModel = new LibraryViewModel();
  @State qvm: QueueViewModel = queueViewModel;
  @State pvm: PlayerViewModel = playerViewModel;
  @State tab: number = 0;
  @State importStatus: string = '';
  /** 统一底部弹层:0=关 1=歌曲操作 2=添加到歌单 3=编辑信息(阶段 v2/v2.2) */
  @State sheetMode: number = 0;
  /** 弹层显隐独立状态:拖拽关闭时 onDisappear 复位,避免"大框常驻"(v2.2 修复) */
  @State showSheet: boolean = false;
  @State sheetTarget: Track | null = null;
  @State editTitle: string = '';
  @State editArtist: string = '';
  /** 网易云来源信息展开(弹层内展示,不再关闭弹层导致"无法操作"状态) */
  @State showSourceInfo: boolean = false;
  @State showSearch: boolean = false;
  // 专辑/艺术家详情子视图(issue-13)
  @State detailAlbum: Album | null = null;
  @State detailArtist: Artist | null = null;
  @State detailTracks: Track[] = [];

  @Builder
  addPanel() {
    Column({ space: 10 }) {
      Text('添加到歌单')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .width('100%')
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
            if (this.sheetTarget !== null) {
              playlistsViewModel.addToPlaylist(p.id, this.sheetTarget.id);
            }
            this.sheetMode = 0;
            this.showSheet = false;
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
    .backgroundColor(this.theme.bg)
  }

  aboutToAppear(): void {
    this.backDispatcher.register('library', 20, () => this.handleBack());
    this.vm.load();
  }

  aboutToDisappear(): void {
    this.backDispatcher.unregister('library');
  }

  private handleBack(): boolean {
    if (this.showSheet) {
      this.showSheet = false;
      this.sheetMode = 0;
      return true;
    }
    if (this.detailAlbum !== null || this.detailArtist !== null) {
      this.closeDetail();
      return true;
    }
    if (this.showSearch) {
      this.showSearch = false;
      this.vm.load();
      return true;
    }
    return false;
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private coverUri(t: Track): string {
    return t.coverPath !== '' ? 'file://' + this.ctx().filesDir + '/' + t.coverPath : '';
  }

  /** 播放反馈:状态栏显示正在播放/错误(issue-12 修复:播放失败不再静默) */
  private async playTracks(tracks: Track[], index: number): Promise<void> {
    const t = tracks[index];
    if (t === undefined) {
      return;
    }
    this.importStatus = '正在加载音乐…';
    const playback = queueViewModel.playFromList(tracks, index, this.ctx());
    const request = this.pvm.requestId;
    await playback;
    if (!this.pvm.isCurrentRequest(request)) { return; }
    this.importStatus = this.pvm.statusText;
  }

  private openAlbum(a: Album): void {
    this.detailArtist = null;
    this.detailAlbum = a;
    this.detailTracks = this.vm.tracks.filter((t: Track) => (a.name === '' ? t.album === '' : t.album === a.name));
  }

  private openArtist(a: Artist): void {
    this.detailAlbum = null;
    this.detailArtist = a;
    this.detailTracks = this.vm.tracks.filter((t: Track) => (a.name === '' ? t.artist === '' : t.artist === a.name));
  }

  private closeDetail(): void {
    this.detailAlbum = null;
    this.detailArtist = null;
    this.detailTracks = [];
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
  TrackRowItem(t: Track, index: number, source: Track[]) {
    Row({ space: 12 }) {
      CoverThumb({ uri: this.coverUri(t), thumbSize: 44 })
      Column({ space: 3 }) {
        Text(t.title !== '' ? t.title : t.path)
          .fontSize(FONT_BODY)
          .fontWeight(this.qvm.currentId === t.id ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${t.artist}${t.album !== '' ? ' · ' + t.album : ''}${t.missing ? ' · 文件缺失' : ''}`)
          .fontSize(FONT_LABEL)
          .fontColor(t.missing ? this.theme.secondaryText : this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph(this.vm.favoriteIds.has(t.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(20)
        .fontColor([this.vm.favoriteIds.has(t.id) ? this.theme.primaryText : this.theme.muted])
        .padding(4)
        .onClick(() => {
          this.vm.toggleFavorite(t.id);
        })
      // 阶段 v2 行操作重设计:爱心高频留行内,加歌单/移除收进"⋯"底部弹层
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(20)
        .fontColor([this.theme.muted])
        .padding(4)
        .onClick(() => {
          this.sheetTarget = t;
          this.sheetMode = 1;
          this.showSheet = true;
          this.showSourceInfo = false;
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
    .border({
      width: this.qvm.currentId === t.id && !t.missing ? 1 : 0,
      color: ThemeService.alpha(this.theme.primary, 0.5)
    })
    .shadow({ radius: SHADOW_CARD_RADIUS, color: this.theme.shadowColor, offsetX: 0, offsetY: SHADOW_CARD_OFFSET_Y })
    .stateStyles({
      pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
    })
    .onClick(() => {
      if (!t.missing) {
        this.playTracks(source, index);
      }
    })
  }

  @Builder
  TrackList() {
    List({ space: 10 }) {
      ForEach(this.vm.tracks, (t: Track, index: number) => {
        ListItem() {
          this.TrackRowItem(t, index, this.vm.tracks)
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
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(15)
              .fontColor([this.theme.muted])
          }
          .width('100%')
          .padding(12)
          .borderRadius(RADIUS_CARD)
          .backgroundColor(this.theme.card)
          .shadow({ radius: SHADOW_CARD_RADIUS, color: this.theme.shadowColor, offsetX: 0, offsetY: SHADOW_CARD_OFFSET_Y })
          .stateStyles({
            pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
          })
          .onClick(() => {
            this.openAlbum(a);
          })
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
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${a.trackCount} 首`)
                .fontSize(FONT_LABEL)
                .fontColor(this.theme.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(15)
              .fontColor([this.theme.muted])
          }
          .width('100%')
          .padding(12)
          .borderRadius(RADIUS_CARD)
          .backgroundColor(this.theme.card)
          .shadow({ radius: SHADOW_CARD_RADIUS, color: this.theme.shadowColor, offsetX: 0, offsetY: SHADOW_CARD_OFFSET_Y })
          .stateStyles({
            pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
          })
          .onClick(() => {
            this.openArtist(a);
          })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  DetailView() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(16)
            .fontColor([this.theme.primaryText])
          Text('返回')
            .fontSize(14)
            .fontColor(this.theme.primaryText)
        }
        .padding(6)
        .onClick(() => {
          this.closeDetail();
        })
        Text(this.detailAlbum !== null
          ? (this.detailAlbum.name !== '' ? this.detailAlbum.name : '未知专辑')
          : (this.detailArtist !== null ? (this.detailArtist.name !== '' ? this.detailArtist.name : '未知艺术家') : ''))
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.detailTracks.length} 首`)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
      }
      .width('100%')

      if (this.detailTracks.length === 0) {
        EmptyState({
          symbol: $r('sys.symbol.music_note_list'),
          title: '这里没有音轨',
          hint: '该聚合下暂无歌曲'
        })
      } else {
        List({ space: 10 }) {
          ForEach(this.detailTracks, (t: Track, index: number) => {
            ListItem() {
              this.TrackRowItem(t, index, this.detailTracks)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SheetActionRow(icon: Resource, text: string, danger: boolean, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([danger ? this.theme.secondaryText : this.theme.muted])
      Text(text)
        .fontSize(FONT_BODY)
        .fontColor(danger ? this.theme.secondaryText : this.theme.ink)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 14 })
    .borderRadius(RADIUS_CONTROL)
    .backgroundColor(this.theme.card)
    .stateStyles({
      pressed: { .opacity(0.6) }
    })
    .onClick(() => {
      action();
    })
  }

  @Builder
  SheetContent() {
    if (this.sheetMode === 1 && this.sheetTarget !== null) {
      Column({ space: 10 }) {
        Text('歌曲操作')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .width('100%')
        Text(this.sheetTarget.title !== '' ? this.sheetTarget.title : this.sheetTarget.path)
          .fontSize(FONT_BODY)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.SheetActionRow($r('sys.symbol.plus'), '添加到歌单', false, () => {
          this.sheetMode = 2;
        })
        this.SheetActionRow($r('sys.symbol.square_and_pencil'), '编辑信息', false, () => {
          if (this.sheetTarget !== null) {
            this.editTitle = this.sheetTarget.title;
            this.editArtist = this.sheetTarget.artist;
          }
          this.sheetMode = 3;
        })
        if (this.sheetTarget.neteaseId > 0) {
          this.SheetActionRow($r('sys.symbol.music_note_list'), '网易云来源歌曲', false, () => {
            this.showSourceInfo = !this.showSourceInfo;
          })
          if (this.showSourceInfo) {
            Text('该歌曲来自网易云音乐,经 DreamMusic 中间层下载入库,可离线播放')
              .fontSize(FONT_LABEL)
              .fontColor(this.theme.muted)
              .width('100%')
              .padding({ left: 20, right: 20 })
          }
        }
        this.SheetActionRow($r('sys.symbol.trash'), '从音乐库移除', true, () => {
          if (this.sheetTarget !== null) {
            const t: Track = this.sheetTarget;
            this.sheetMode = 0;
            this.showSheet = false;
            this.confirmRemove(t);
          }
        })
      }
      .width('100%')
      .padding({ top: 8, bottom: 16 })
      .backgroundColor(this.theme.bg)
    } else if (this.sheetMode === 2) {
      this.addPanel()
    } else if (this.sheetMode === 3 && this.sheetTarget !== null) {
      Column({ space: 12 }) {
        Text('编辑信息')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .width('100%')
        TextInput({ placeholder: '歌名', text: this.editTitle })
          .fontSize(14)
          .fontColor(this.theme.ink)
          .placeholderColor(this.theme.muted)
          .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
          .borderRadius(12)
          .height(40)
          .width('100%')
          .onChange((v: string) => {
            this.editTitle = v;
          })
        TextInput({ placeholder: '作者', text: this.editArtist })
          .fontSize(14)
          .fontColor(this.theme.ink)
          .placeholderColor(this.theme.muted)
          .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
          .borderRadius(12)
          .height(40)
          .width('100%')
          .onChange((v: string) => {
            this.editArtist = v;
          })
        Text('保存')
          .fontSize(14)
          .fontColor(this.theme.primaryText)
          .padding({ left: 28, right: 28, top: 10, bottom: 10 })
          .borderRadius(RADIUS_CAPSULE)
          .backgroundColor(ThemeService.alpha(this.theme.primary, 0.14))
          .onClick(() => {
            if (this.sheetTarget !== null) {
              const t: Track = this.sheetTarget;
              this.vm.editTrackMeta(t, this.editTitle, this.editArtist);
            }
            this.sheetMode = 0;
            this.showSheet = false;
          })
      }
      .width('100%')
      .padding({ top: 8, bottom: 16 })
      .backgroundColor(this.theme.bg)
    }
  }

  build() {
    Column({ space: 14 }) {
      // 页头:标题 + 搜索 + 扫描(无底色;阶段 v2 在线搜索入口)
      Row() {
        Text('音乐库')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
        Row({ space: 4 }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(14)
              .fontColor([this.theme.primaryText])
            Text('搜索')
              .fontSize(13)
              .fontColor(this.theme.primaryText)
          }
          .padding(8)
          .borderRadius(RADIUS_CAPSULE)
          .onClick(() => {
            this.showSearch = true;
          })
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(14)
              .fontColor([this.theme.primaryText])
            Text('扫描')
              .fontSize(13)
              .fontColor(this.theme.primaryText)
          }
          .padding(8)
          .borderRadius(RADIUS_CAPSULE)
          .onClick(() => {
            this.vm.rescan(this.ctx());
          })
        }
      }
      .width('100%')

      // 视图切换:文字 + 圆点指示(无实色块)
      Row({ space: 20 }) {
        ForEach(['歌曲', '专辑', '艺术家'], (item: string, index: number) => {
          Column({ space: 3 }) {
            Text(item)
              .fontSize(14)
              .fontWeight(index === this.tab ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(index === this.tab ? this.theme.primaryText : this.theme.muted)
            Circle()
              .width(4)
              .height(4)
              .fill(index === this.tab ? this.theme.primary : this.theme.transparent)
          }
          .padding({ top: 4, bottom: 2 })
          .onClick(() => {
            this.tab = index;
            this.closeDetail();
          })
        })
        Blank()
      }
      .width('100%')

      if (this.detailAlbum !== null || this.detailArtist !== null) {
        this.DetailView()
      } else if (this.showSearch) {
        OnlineSearchView({
          onBack: () => {
            this.showSearch = false;
            this.vm.load();
          },
          onGoSettings: () => {
            this.onGoSettings();
          },
          onGoLogin: () => {
            this.onGoLogin();
          }
        })
      } else {
        // 导入入口(仅文件;文件夹选择手机不支持,已移除)
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(15)
              .fontColor([this.theme.primaryText])
            Text('导入文件')
              .fontSize(13)
              .fontColor(this.theme.primaryText)
          }
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .borderRadius(RADIUS_CAPSULE)
          .backgroundColor(ThemeService.alpha(this.theme.primary, 0.12))
          .stateStyles({
            pressed: { .opacity(0.6) }
          })
          .onClick(() => {
            this.importFiles();
          })
          Blank()
        }
        .width('100%')

        Text(this.importStatus !== '' ? this.importStatus : this.vm.statusText)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.vm.loading) {
          Text('正在读取本机音乐库…').fontSize(FONT_LABEL).fontColor(this.theme.muted)
        } else if (this.vm.loadError !== '') {
          Text(this.vm.loadError + ' · 点击重试').fontSize(FONT_LABEL).fontColor(this.theme.errorColor)
            .onClick(() => { this.vm.load(); })
        } else if (this.tab === 0) {
          if (this.vm.tracks.length === 0) {
            EmptyState({
              symbol: $r('sys.symbol.music_note_list'),
              title: '这里还是空的',
              hint: '点击上方「导入文件」添加 MP3/AAC(M4A)/FLAC/WAV'
            })
          } else {
            this.TrackList()
          }
        } else if (this.tab === 1) {
          if (this.vm.albums.length === 0) {
            EmptyState({
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
              symbol: $r('sys.symbol.person'),
              title: '还没有艺术家',
              hint: '导入带艺术家信息的音乐后会按艺术家聚合'
            })
          } else {
            this.ArtistList()
          }
        }
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .bindSheet(this.showSheet, this.SheetContent(), {
      height: this.sheetMode === 3 ? 300 : this.sheetMode === 1 ? 340 : 420,
      backgroundColor: this.theme.bg,
      onDisappear: () => {
        this.showSheet = false;
        this.sheetMode = 0;
      }
    })
  }
}
