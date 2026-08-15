import { ThemeService } from '../service/theme/ThemeService';
import { ImportService } from '../service/library/ImportService';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { playlistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { Track, Album, Artist, Playlist } from '../model/Entities';
import { common } from '@kit.AbilityKit';

/** 音乐库页:歌曲/专辑/艺术家三视图 + 导入 + 扫描 + 移除(issue-03/04) */
@Component
export struct MusicLibraryPage {
  @Prop theme: ThemeService;
  @State vm: LibraryViewModel = new LibraryViewModel();
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
              .fontSize(15)
              .fontColor(this.theme.ink)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor(this.theme.bg)
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

  async importFiles(): Promise<void> {
    const context = this.ctx();
    this.importStatus = '选择文件中…';
    const sources = await ImportService.pickAudioFiles(context);
    if (sources.length === 0) {
      this.importStatus = '未选择文件';
      return;
    }
    this.importStatus = `导入 0/${sources.length}`;
    const result = await ImportService.importSources(context, sources, (done: number, total: number): void => {
      this.importStatus = `导入 ${done}/${total}`;
    });
    this.importStatus = `完成:导入 ${result.imported},跳过 ${result.skipped},重复 ${result.duplicates}`;
    await this.vm.load();
  }

  async importFolder(): Promise<void> {
    const context = this.ctx();
    this.importStatus = '选择文件夹中…';
    const sources = await ImportService.pickAudioFolder(context);
    if (sources.length === 0) {
      this.importStatus = '文件夹中没有支持的音频';
      return;
    }
    const result = await ImportService.importSources(context, sources, (done: number, total: number): void => {
      this.importStatus = `导入 ${done}/${total}`;
    });
    this.importStatus = `完成:导入 ${result.imported},跳过 ${result.skipped},重复 ${result.duplicates}`;
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
    List({ space: 8 }) {
      ForEach(this.vm.tracks, (t: Track, index: number) => {
        ListItem() {
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text(t.title !== '' ? t.title : t.path)
                .fontSize(16)
                .fontColor(this.theme.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${t.artist}${t.album !== '' ? ' · ' + t.album : ''}${t.missing ? ' · 文件缺失' : ''}`)
                .fontSize(12)
                .fontColor(t.missing ? this.theme.secondary : this.theme.muted)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.vm.favoriteIds.has(t.id) ? '♥' : '♡')
              .fontSize(18)
              .fontColor(this.vm.favoriteIds.has(t.id) ? this.theme.primary : this.theme.muted)
              .padding(4)
              .onClick(() => {
                this.vm.toggleFavorite(t.id);
              })
            Text('＋')
              .fontSize(18)
              .fontColor(this.theme.muted)
              .padding(4)
              .onClick(() => {
                this.addTrack = t;
                this.showAdd = true;
              })
            Text('✕')
              .fontSize(16)
              .fontColor(this.theme.muted)
              .padding(6)
              .onClick(() => {
                this.confirmRemove(t);
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(14)
          .backgroundColor(this.theme.bg)
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
  }

  @Builder
  AlbumList() {
    List({ space: 8 }) {
      ForEach(this.vm.albums, (a: Album) => {
        ListItem() {
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text(a.name !== '' ? a.name : '未知专辑')
                .fontSize(16)
                .fontColor(this.theme.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${a.artist} · ${a.trackCount} 首`)
                .fontSize(12)
                .fontColor(this.theme.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor(this.theme.bg)
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  ArtistList() {
    List({ space: 8 }) {
      ForEach(this.vm.artists, (a: Artist) => {
        ListItem() {
          Row() {
            Text(a.name !== '' ? a.name : '未知艺术家')
              .fontSize(16)
              .fontColor(this.theme.ink)
              .layoutWeight(1)
            Text(`${a.trackCount} 首`)
              .fontSize(12)
              .fontColor(this.theme.muted)
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor(this.theme.bg)
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  EmptyState(hint: string) {
    Column({ space: 8 }) {
      Text('这里还是空的')
        .fontSize(18)
        .fontColor(this.theme.ink)
      Text(hint)
        .fontSize(14)
        .fontColor(this.theme.muted)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column({ space: 16 }) {
      Text('音乐库')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(['歌曲', '专辑', '艺术家'], (item: string, index: number) => {
          Text(item)
            .fontSize(16)
            .fontColor(index === this.tab ? this.theme.primary : this.theme.muted)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(index === this.tab ? this.theme.bg : '#00000000')
            .onClick(() => {
              this.tab = index;
            })
        })
        Blank()
        Text('↻ 扫描')
          .fontSize(13)
          .fontColor(this.theme.primary)
          .onClick(() => {
            this.vm.rescan(this.ctx());
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('导入文件')
          .fontSize(14)
          .fontColor(this.theme.ink)
          .backgroundColor(this.theme.primary)
          .borderRadius(18)
          .onClick(() => {
            this.importFiles();
          })
        Button('导入文件夹')
          .fontSize(14)
          .fontColor(this.theme.ink)
          .backgroundColor(this.theme.secondary)
          .borderRadius(18)
          .onClick(() => {
            this.importFolder();
          })
        Text(this.importStatus !== '' ? this.importStatus : this.vm.statusText)
          .fontSize(12)
          .fontColor(this.theme.muted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (this.tab === 0) {
        if (this.vm.tracks.length === 0) {
          this.EmptyState('用上方按钮导入 MP3/AAC(M4A)/FLAC/WAV')
        } else {
          this.TrackList()
        }
      } else if (this.tab === 1) {
        if (this.vm.albums.length === 0) {
          this.EmptyState('导入带专辑信息的音乐后会按专辑聚合')
        } else {
          this.AlbumList()
        }
      } else {
        if (this.vm.artists.length === 0) {
          this.EmptyState('导入带艺术家信息的音乐后会按艺术家聚合')
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
