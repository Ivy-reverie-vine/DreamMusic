import { ThemeService } from '../service/theme/ThemeService';
import { playlistsViewModel, PlaylistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { Playlist, Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { EmptyState } from '../components/EmptyState';
import { RADIUS_CARD, RADIUS_CAPSULE, FONT_BODY, FONT_LABEL, FONT_TITLE } from '../common/DesignTokens';

/**
 * 歌单页(issue-09 + issue-13 视觉):
 * 自建歌单增删改、歌单详情加歌/移歌、我喜欢的音乐、最近播放;
 * 全部 SymbolGlyph,行带封面/阴影/按压反馈。
 */
@Component
export struct PlaylistsPage {
  @Prop theme: ThemeService;
  @State vm: PlaylistsViewModel = playlistsViewModel;
  @State newName: string = '';
  @State showRename: boolean = false;
  @State renameText: string = '';
  @State renameTargetId: number = -1;

  aboutToAppear(): void {
    this.vm.load();
    this.vm.loadHistory();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private coverUri(t: Track): string {
    return t.coverPath !== '' ? 'file://' + this.ctx().filesDir + '/' + t.coverPath : '';
  }

  @Builder
  TrackRow(t: Track, index: number) {
    Row({ space: 12 }) {
      CoverThumb({ theme: this.theme, uri: this.coverUri(t), thumbSize: 40 })
      Column({ space: 3 }) {
        Text(t.title !== '' ? t.title : t.path)
          .fontSize(FONT_BODY)
          .fontColor(this.theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(t.artist)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.minus'))
        .fontSize(18)
        .fontColor([this.theme.muted])
        .padding(5)
        .onClick(() => {
          this.vm.removeTrackFromSelected(t.id);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
    .stateStyles({
      pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
    })
    .onClick(() => {
      if (!t.missing) {
        queueViewModel.playFromList(this.vm.selectedTracks, index, this.ctx());
      }
    })
  }

  @Builder
  PlaylistList() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '新歌单名字', text: this.newName })
          .fontSize(14)
          .fontColor(this.theme.ink)
          .placeholderColor(this.theme.muted)
          .backgroundColor(this.theme.card)
          .borderRadius(12)
          .height(40)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.newName = v;
          })
        Text('新建')
          .fontSize(13)
          .fontColor(this.theme.primaryText)
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .borderRadius(RADIUS_CAPSULE)
          .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.4) })
          .onClick(() => {
            this.vm.create(this.newName);
            this.newName = '';
          })
      }
      .width('100%')

      if (this.vm.statusText !== '') {
        Text(this.vm.statusText)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
      }

      List({ space: 10 }) {
        ForEach(this.vm.playlists, (p: Playlist) => {
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph(p.systemReserved ? $r('sys.symbol.heart_fill') : $r('sys.symbol.rectangle_stack'))
                .fontSize(18)
                .fontColor([p.systemReserved ? this.theme.primary : this.theme.muted])
              Text(p.name)
                .fontSize(FONT_BODY)
                .fontColor(this.theme.ink)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (!p.systemReserved) {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(17)
                  .fontColor([this.theme.muted])
                  .padding(4)
                  .onClick(() => {
                    this.renameTargetId = p.id;
                    this.renameText = p.name;
                    this.showRename = true;
                  })
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(16)
                  .fontColor([this.theme.muted])
                  .padding(4)
                  .onClick(() => {
                    this.vm.remove(p);
                  })
              }
            }
            .width('100%')
            .padding(12)
            .borderRadius(RADIUS_CARD)
            .backgroundColor(this.theme.card)
            .stateStyles({
              pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
            })
            .onClick(() => {
              this.vm.openPlaylist(p);
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)

      // 最近播放(清空入口保留于此,设置页已移除)
      Column({ space: 8 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.clock_fill'))
            .fontSize(15)
            .fontColor([this.theme.muted])
          Text('最近播放')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.ink)
            .layoutWeight(1)
            .margin({ left: 6 })
          Text('清空')
            .fontSize(12)
            .fontColor(this.theme.primaryText)
            .onClick(() => {
              this.vm.clearHistory();
            })
        }
        .width('100%')

        if (this.vm.historyTracks.length === 0) {
          Text('还没有播放记录')
            .fontSize(13)
            .fontColor(this.theme.muted)
        } else {
          List({ space: 6 }) {
            ForEach(this.vm.historyTracks, (t: Track) => {
              ListItem() {
                Text(`${t.title !== '' ? t.title : t.path} — ${t.artist}`)
                  .fontSize(13)
                  .fontColor(this.theme.muted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            })
          }
          .width('100%')
          .height(160)
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius(RADIUS_CARD)
      .backgroundColor(this.theme.card)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PlaylistDetail() {
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
          this.vm.selected = null;
          this.vm.selectedTracks = [];
        })
        Text(this.vm.selected !== null ? this.vm.selected.name : '')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (this.vm.selected !== null && this.vm.selectedTracks.length === 0) {
        EmptyState({
          theme: this.theme,
          symbol: $r('sys.symbol.heart'),
          title: this.vm.selected.systemReserved ? '还没有收藏的歌' : '歌单是空的',
          hint: this.vm.selected.systemReserved ? '在音乐库点爱心收藏' : '去音乐库点加号加歌'
        })
      }

      List({ space: 10 }) {
        ForEach(this.vm.selectedTracks, (t: Track, index: number) => {
          ListItem() {
            this.TrackRow(t, index)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 16 }) {
        Text('歌单')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .width('100%')

        if (this.vm.selected === null) {
          this.PlaylistList()
        } else {
          this.PlaylistDetail()
        }
      }
      .padding(20)
      .width('100%')
      .height('100%')

      if (this.showRename) {
        Column({ space: 12 }) {
          Text('重命名歌单')
            .fontSize(16)
            .fontColor(this.theme.ink)
          TextInput({ text: this.renameText })
            .fontSize(14)
            .fontColor(this.theme.ink)
            .backgroundColor(this.theme.card)
            .borderRadius(12)
            .width('80%')
            .onChange((v: string) => {
              this.renameText = v;
            })
          Row({ space: 16 }) {
            Text('取消')
              .fontSize(13)
              .fontColor(this.theme.muted)
              .padding({ left: 20, right: 20, top: 9, bottom: 9 })
              .borderRadius(RADIUS_CAPSULE)
              .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.3) })
              .onClick(() => {
                this.showRename = false;
              })
            Text('确定')
              .fontSize(13)
              .fontColor(this.theme.primaryText)
              .padding({ left: 20, right: 20, top: 9, bottom: 9 })
              .borderRadius(RADIUS_CAPSULE)
              .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.4) })
              .onClick(() => {
                this.vm.rename(this.renameTargetId, this.renameText);
                this.showRename = false;
              })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.theme.overlayDim)
      }
    }
    .width('100%')
    .height('100%')
  }
}
