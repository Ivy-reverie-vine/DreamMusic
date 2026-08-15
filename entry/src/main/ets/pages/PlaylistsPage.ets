import { ThemeService } from '../service/theme/ThemeService';
import { playlistsViewModel, PlaylistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { Playlist, Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';

/** 歌单页(issue-09):自建歌单增删改、歌单详情加歌/移歌、我喜欢的音乐、最近播放 */
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

  @Builder
  TrackRow(t: Track, index: number) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(t.title !== '' ? t.title : t.path)
          .fontSize(15)
          .fontColor(this.theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(t.artist)
          .fontSize(12)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('✕')
        .fontSize(15)
        .fontColor(this.theme.muted)
        .padding(6)
        .onClick(() => {
          this.vm.removeTrackFromSelected(t.id);
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(this.theme.bg)
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
          .backgroundColor(this.theme.bg)
          .borderRadius(14)
          .height(40)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.newName = v;
          })
        Button('新建')
          .fontSize(14)
          .fontColor(this.theme.ink)
          .backgroundColor(this.theme.primary)
          .borderRadius(18)
          .onClick(() => {
            this.vm.create(this.newName);
            this.newName = '';
          })
      }
      .width('100%')

      if (this.vm.statusText !== '') {
        Text(this.vm.statusText)
          .fontSize(12)
          .fontColor(this.theme.muted)
      }

      List({ space: 8 }) {
        ForEach(this.vm.playlists, (p: Playlist) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(p.systemReserved ? '♥' : '≡')
                .fontSize(16)
                .fontColor(this.theme.primary)
              Text(p.name)
                .fontSize(16)
                .fontColor(this.theme.ink)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (!p.systemReserved) {
                Text('✎')
                  .fontSize(15)
                  .fontColor(this.theme.muted)
                  .padding(4)
                  .onClick(() => {
                    this.renameTargetId = p.id;
                    this.renameText = p.name;
                    this.showRename = true;
                  })
                Text('🗑')
                  .fontSize(15)
                  .fontColor(this.theme.muted)
                  .padding(4)
                  .onClick(() => {
                    this.vm.remove(p);
                  })
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .backgroundColor(this.theme.bg)
            .onClick(() => {
              this.vm.openPlaylist(p);
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)

      // 最近播放
      Column({ space: 8 }) {
        Row() {
          Text('最近播放')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.ink)
            .layoutWeight(1)
          Text('清空')
            .fontSize(13)
            .fontColor(this.theme.primary)
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
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PlaylistDetail() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text('← 返回')
          .fontSize(15)
          .fontColor(this.theme.primary)
          .onClick(() => {
            this.vm.selected = null;
            this.vm.selectedTracks = [];
          })
        Text(this.vm.selected !== null ? this.vm.selected.name : '')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (this.vm.selected !== null && this.vm.selectedTracks.length === 0) {
        Text(this.vm.selected.systemReserved ? '还没有收藏的歌' : '歌单是空的,去音乐库点 ＋ 加歌')
          .fontSize(14)
          .fontColor(this.theme.muted)
      }

      List({ space: 8 }) {
        ForEach(this.vm.selectedTracks, (t: Track, index: number) => {
          ListItem() {
            this.TrackRow(t, index)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 16 }) {
        Text('歌单')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
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
            .backgroundColor(this.theme.bg)
            .borderRadius(12)
            .width('80%')
            .onChange((v: string) => {
              this.renameText = v;
            })
          Row({ space: 16 }) {
            Button('取消')
              .fontSize(14)
              .fontColor(this.theme.ink)
              .backgroundColor(this.theme.secondary)
              .borderRadius(16)
              .onClick(() => {
                this.showRename = false;
              })
            Button('确定')
              .fontSize(14)
              .fontColor(this.theme.ink)
              .backgroundColor(this.theme.primary)
              .borderRadius(16)
              .onClick(() => {
                this.vm.rename(this.renameTargetId, this.renameText);
                this.showRename = false;
              })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#B0000000')
      }
    }
    .width('100%')
    .height('100%')
  }
}
