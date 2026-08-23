import { ThemeService } from '../service/theme/ThemeService';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { playlistsViewModel, PlaylistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { EmptyState } from '../components/EmptyState';
import { OutlineButton } from '../components/OutlineButton';
import { SettingsPage } from './SettingsPage';
import { RADIUS_CARD, RADIUS_CAPSULE, FONT_BODY, FONT_LABEL, FONT_TITLE } from '../common/DesignTokens';

@Component
export struct MyPage {
  @State theme: ThemeService = ThemeService.getInstance();
  @State vm: PlaylistsViewModel = playlistsViewModel;
  @State historyOpen: boolean = false;
  @State showSettings: boolean = false;

  aboutToAppear(): void {
    this.vm.loadHistory();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: '清空播放历史',
      message: '确定清空吗？此操作不可恢复。',
      primaryButton: {
        value: '清空',
        action: () => {
          this.vm.clearHistory();
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  @Builder
  AccountSummary() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
          .fontSize(30)
          .fontColor([this.theme.primaryText])
        Column({ space: 3 }) {
          Text(DreamMusicAuth.isLoggedIn(this.ctx()) ? 'DreamMusic 账户' : '本地音乐')
            .fontSize(FONT_BODY)
            .fontColor(this.theme.ink)
          Text(DreamMusicAuth.isLoggedIn(this.ctx())
            ? '梦点 ' + DreamMusicAuth.dreamPoints(this.ctx())
            : '登录后可使用搜索功能')
            .fontSize(FONT_LABEL)
            .fontColor(this.theme.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('设置')
          .fontSize(13)
          .fontColor(this.theme.primaryText)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(RADIUS_CAPSULE)
          .backgroundColor(ThemeService.alpha(this.theme.primary, 0.13))
          .onClick(() => {
            this.showSettings = true;
          })
      }
      .width('100%')
      Text(DreamMusicAuth.isLoggedIn(this.ctx())
        ? (DreamMusicAuth.checkedInToday(this.ctx()) ? '已签' : '签到')
        : '占位')
        .fontSize(FONT_LABEL)
        .fontColor(this.theme.muted)
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
  }

  @Builder
  HistorySummary() {
    Column({ space: 8 }) {
      Row() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock_fill'))
            .fontSize(16)
            .fontColor([this.theme.muted])
          Text('播放历史')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.ink)
        }
        .layoutWeight(1)
        Text(this.vm.historyTracks.length + ' 首')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
        Text('查看')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.primaryText)
      }
      .width('100%')
      .onClick(() => {
        this.vm.loadHistory().then(() => {
          this.historyOpen = true;
        });
      })
      if (this.vm.historyTracks.length === 0) {
        Text('还没有播放记录')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
      } else {
        ForEach(this.vm.historyTracks.slice(0, 3), (track: Track) => {
          Text(`${track.title !== '' ? track.title : track.path} · ${track.artist}`)
            .fontSize(FONT_LABEL)
            .fontColor(this.theme.muted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }, (track: Track) => String(track.id))
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
  }

  @Builder
  HistoryDetail() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text('返回')
          .fontSize(14)
          .fontColor(this.theme.primaryText)
          .padding(6)
          .onClick(() => {
            this.historyOpen = false;
          })
        Text('播放历史')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
        Text('清空')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.primaryText)
          .onClick(() => {
            this.confirmClearHistory();
          })
      }
      .width('100%')
      if (this.vm.historyTracks.length === 0) {
        EmptyState({
          symbol: $r('sys.symbol.clock_fill'),
          title: '空空如也',
          hint: '播放历史'
        })
      } else {
        List({ space: 8 }) {
          ForEach(this.vm.historyTracks, (track: Track, index: number) => {
            ListItem() {
              Row({ space: 10 }) {
                CoverThumb({
                  uri: track.coverPath === '' ? '' : 'file://' + this.ctx().filesDir + '/' + track.coverPath,
                  thumbSize: 42
                })
                Column({ space: 2 }) {
                  Text(track.title !== '' ? track.title : track.path)
                    .fontSize(FONT_BODY)
                    .fontColor(this.theme.ink)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(track.artist)
                    .fontSize(FONT_LABEL)
                    .fontColor(this.theme.muted)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(10)
              .borderRadius(RADIUS_CARD)
              .backgroundColor(this.theme.card)
              .onClick(() => {
                if (!track.missing) {
                  queueViewModel.playFromList(this.vm.historyTracks, index, this.ctx());
                }
              })
            }
          }, (track: Track, index: number) => String(track.id) + '_' + String(index))
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SettingsContent() {
    SettingsPage()
  }

  build() {
    if (this.historyOpen) {
      this.HistoryDetail()
    } else {
      Scroll() {
        Column({ space: 12 }) {
          Row() {
            Text('我的')
              .fontSize(FONT_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.ink)
              .layoutWeight(1)
            OutlineButton({
              text: '设置',
              onTap: (): void => {
                this.showSettings = true;
              }
            })
          }
          .width('100%')
          this.AccountSummary()
          this.HistorySummary()
        }
        .padding(20)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .bindSheet(this.showSettings, this.SettingsContent(), {
        height: 700,
        backgroundColor: this.theme.bg,
        onDisappear: () => {
          this.showSettings = false;
        }
      })
    }
  }
}
