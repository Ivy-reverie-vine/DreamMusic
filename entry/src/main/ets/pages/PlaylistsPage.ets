import { ThemeService } from '../service/theme/ThemeService';
import { playlistsViewModel, PlaylistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { Playlist, Track, OnlineSong } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { EmptyState } from '../components/EmptyState';
import { RADIUS_CARD, RADIUS_CAPSULE, FONT_BODY, FONT_LABEL, FONT_TITLE } from '../common/DesignTokens';
import { OnlineMusicViewModel, onlineMusicViewModel } from '../viewmodel/OnlineMusicViewModel';
import { OnlinePlaylistSummary } from '../service/network/OnlineMusicService';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';

/**
 * 歌单页(issue-09 + issue-13 视觉):
 * 自建歌单增删改、歌单详情加歌/移歌、我喜欢的音乐、在线资料;
 * 全部 SymbolGlyph,行带封面/阴影/按压反馈。
 */
@Component
export struct PlaylistsPage {
  @State theme: ThemeService = ThemeService.getInstance();
  @State vm: PlaylistsViewModel = playlistsViewModel;
  @State newName: string = '';
  @State showRename: boolean = false;
  @State renameText: string = '';
  @State renameTargetId: number = -1;
  @State onlineVm: OnlineMusicViewModel = onlineMusicViewModel;
  /** 0=列表, 1=我喜欢, 2=在线歌单详情, 3=全部在线歌单 */
  @State onlineDetailMode: number = 0;
  @State onlineStatus: string = '';

  aboutToAppear(): void {
    this.vm.load();
    this.onlineVm.prefetch(this.ctx());
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  confirmRemovePlaylist(p: Playlist): void {
    this.getUIContext().showAlertDialog({
      title: '删除歌单',
      message: `确定删除「${p.name}」吗?歌单内的歌曲不会被删除。`,
      primaryButton: {
        value: '删除',
        action: () => {
          this.vm.remove(p);
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  private coverUri(t: Track): string {
    return t.coverPath !== '' ? 'file://' + this.ctx().filesDir + '/' + t.coverPath : '';
  }

  private onlineCoverUri(url: string): string {
    return url;
  }

  private closeOnlineDetail(): void {
    this.onlineDetailMode = 0;
    this.onlineVm.selectedPlaylist = null;
    this.onlineVm.selectedSongs = [];
    this.onlineStatus = '';
  }

  @Builder
  TrackRow(t: Track, index: number) {
    Row({ space: 12 }) {
      CoverThumb({ uri: this.coverUri(t), thumbSize: 40 })
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
  OnlineSongRow(song: OnlineSong, index: number) {
    Row({ space: 10 }) {
      CoverThumb({ uri: this.onlineCoverUri(song.coverUrl), thumbSize: 40 })
      Column({ space: 3 }) {
        Text(song.name !== '' ? song.name : '未知歌曲')
          .fontSize(FONT_BODY)
          .fontColor(this.theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${song.artist}${song.album !== '' ? ' · ' + song.album : ''}`)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('播放')
        .fontSize(FONT_LABEL)
        .fontColor(this.theme.primaryText)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
    .stateStyles({
      pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
    })
    .onClick(() => {
      this.onlineStatus = '正在打开「' + song.name + '」…';
      this.onlineVm.playSong(this.ctx(), song)
        .then(() => {
          this.onlineStatus = '正在播放「' + song.name + '」';
        })
        .catch((err: Error) => {
          this.onlineStatus = '播放失败: ' + err.message;
        });
    })
  }

  @Builder
  OnlineLibrarySection() {
    if (DreamMusicAuth.isLoggedIn(this.ctx())) {
      Column({ space: 8 }) {
        Row() {
          Text('在线资料')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.ink)
            .layoutWeight(1)
          Text('刷新')
            .fontSize(12)
            .fontColor(this.theme.primaryText)
            .onClick(() => {
              this.onlineVm.prefetch(this.ctx()).then(() => {
                this.onlineVm.loadCached(this.ctx());
              });
            })
        }
        .width('100%')
        Text('网易云在线歌单 ' + this.onlineVm.playlists.length + ' 个 · 我喜欢的音乐 ' +
          this.onlineVm.likedSongs.length + ' 首')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.heart_fill'))
            .fontSize(15)
            .fontColor([this.theme.primary])
          Text('我喜欢的音乐')
            .fontSize(13)
            .fontColor(this.theme.ink)
            .layoutWeight(1)
          Text(this.onlineVm.likedSongs.length + ' 首')
            .fontSize(11)
            .fontColor(this.theme.muted)
        }
        .width('100%')
        .padding(8)
        .borderRadius(10)
        .backgroundColor(this.theme.card)
        .onClick(() => {
          this.onlineDetailMode = 1;
          this.onlineStatus = '';
          this.onlineVm.loadLikedSongs(this.ctx());
        })
        ForEach(this.onlineVm.playlists.slice(0, 5), (p: OnlinePlaylistSummary) => {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.rectangle_stack'))
              .fontSize(15)
              .fontColor([this.theme.muted])
            Text(p.name)
              .fontSize(13)
              .fontColor(this.theme.ink)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(p.trackCount + ' 首')
              .fontSize(11)
              .fontColor(this.theme.muted)
          }
          .width('100%')
          .padding(8)
          .borderRadius(10)
          .backgroundColor(this.theme.card)
          .onClick(() => {
            this.onlineDetailMode = 2;
            this.onlineStatus = '';
            this.onlineVm.openPlaylist(this.ctx(), p);
          })
        })
        if (this.onlineVm.playlists.length > 5) {
          Row({ space: 6 }) {
            Text('查看全部在线歌单')
              .fontSize(12)
              .fontColor(this.theme.primaryText)
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([this.theme.primaryText])
          }
          .width('100%')
          .padding(8)
          .borderRadius(10)
          .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1))
          .onClick(() => {
            this.onlineDetailMode = 3;
            this.onlineStatus = '';
            this.onlineVm.loadPlaylists(this.ctx());
          })
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius(RADIUS_CARD)
      .backgroundColor(this.theme.card)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  OnlineDetail() {
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
          this.closeOnlineDetail();
        })
        Text(this.onlineDetailMode === 1
          ? '我喜欢的音乐'
          : (this.onlineDetailMode === 3
            ? '全部在线歌单'
            : (this.onlineVm.selectedPlaylist !== null ? this.onlineVm.selectedPlaylist.name : '在线歌单')))
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (this.onlineStatus !== '') {
        Text(this.onlineStatus)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
      }
      if (this.onlineVm.loading) {
        Text('在线资料加载中…')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
      } else if (this.onlineVm.statusText !== '') {
        Text(this.onlineVm.statusText)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.errorColor)
          .width('100%')
      } else if ((this.onlineDetailMode === 1 && this.onlineVm.likedSongs.length === 0) ||
        (this.onlineDetailMode === 2 && this.onlineVm.selectedSongs.length === 0) ||
        (this.onlineDetailMode === 3 && this.onlineVm.playlists.length === 0)) {
        EmptyState({
          symbol: $r('sys.symbol.music_note_list'),
          title: '这里还没有歌曲',
          hint: '在线资料为空或暂时无法读取'
        })
      } else {
        List({ space: 10 }) {
          if (this.onlineDetailMode === 3) {
            ForEach(this.onlineVm.playlists, (playlist: OnlinePlaylistSummary) => {
              ListItem() {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.rectangle_stack'))
                    .fontSize(16)
                    .fontColor([this.theme.muted])
                  Text(playlist.name)
                    .fontSize(FONT_BODY)
                    .fontColor(this.theme.ink)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(playlist.trackCount + ' 首')
                    .fontSize(FONT_LABEL)
                    .fontColor(this.theme.muted)
                }
                .width('100%')
                .padding(12)
                .borderRadius(RADIUS_CARD)
                .backgroundColor(this.theme.card)
                .onClick(() => {
                  this.onlineDetailMode = 2;
                  this.onlineVm.openPlaylist(this.ctx(), playlist);
                })
              }
            }, (playlist: OnlinePlaylistSummary) => String(playlist.id))
          } else {
            ForEach(this.onlineDetailMode === 1 ? this.onlineVm.likedSongs : this.onlineVm.selectedSongs,
              (song: OnlineSong, index: number) => {
                ListItem() {
                  this.OnlineSongRow(song, index)
                }
              }, (song: OnlineSong) => String(song.id))
          }
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
                    this.confirmRemovePlaylist(p);
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

      this.OnlineLibrarySection()

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

        if (this.vm.selected === null && this.onlineDetailMode === 0) {
          this.PlaylistList()
        } else if (this.vm.selected === null) {
          this.OnlineDetail()
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
