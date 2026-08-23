import { ThemeService } from '../service/theme/ThemeService';
import { DreamMusicAuth, DreamPointLog, Announcement } from '../service/network/DreamMusicAuth';
import { accountViewModel, AccountViewModel } from '../viewmodel/AccountViewModel';
import { playbackStatsViewModel, PlaybackStatsViewModel } from '../viewmodel/PlaybackStatsViewModel';
import { playlistsViewModel, PlaylistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { Playlist, Track } from '../model/Entities';
import { MySubpage } from '../model/Navigation';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { EmptyState } from '../components/EmptyState';
import { PlaylistsPage } from './PlaylistsPage';
import { SettingsPage } from './SettingsPage';
import { FONT_BODY, FONT_LABEL, FONT_TITLE, RADIUS_CARD, RADIUS_CAPSULE } from '../common/DesignTokens';

/** “我的”内容中心：账户、统计、歌单、历史、公告消息和设置均为全页状态。 */
@Component
export struct MyPageV2 {
  @Prop page: MySubpage = MySubpage.HOME;
  onNavigate: (page: MySubpage) => void = () => {
  };
  onLogin: () => void = () => {
  };
  @State theme: ThemeService = ThemeService.getInstance();
  @State account: AccountViewModel = accountViewModel;
  @State stats: PlaybackStatsViewModel = playbackStatsViewModel;
  @State playlists: PlaylistsViewModel = playlistsViewModel;
  @State redeemCode: string = '';
  @State msgTitle: string = '';
  @State msgContent: string = '';
  @State messageExpanded: boolean = false;

  aboutToAppear(): void {
    const ctx = this.ctx();
    this.account.refresh(ctx);
    this.account.loadAnnouncements(ctx);
    this.stats.load(ctx);
    this.playlists.load();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private open(page: MySubpage): void {
    this.onNavigate(page);
  }

  private accountLabel(): string {
    if (!this.account.loggedIn) {
      return '未登录 · 本地音乐仍可离线播放';
    }
    if (this.account.bindInvalid) {
      return this.account.username + ' · 网易云绑定失效';
    }
    return this.account.username + (this.account.bound ? ' · 已绑定网易云' : ' · 未绑定网易云');
  }

  private doCheckin(): void {
    if (!this.account.loggedIn) {
      this.onLogin();
      return;
    }
    this.account.checkin(this.ctx());
  }

  @Builder
  Header(title: string) {
    Row({ space: 12 }) {
      if (this.page !== MySubpage.HOME) {
        Text('返回')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.primaryText)
          .padding(6)
          .onClick(() => { this.open(MySubpage.HOME); })
      }
      Text(title)
        .fontSize(FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  AccountSummary() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
          .fontSize(30).fontColor([this.theme.primaryText])
        Column({ space: 3 }) {
          Text(this.account.loggedIn ? 'DreamMusic 账户' : '本地音乐账户')
            .fontSize(FONT_BODY).fontColor(this.theme.ink)
          Text(this.accountLabel())
            .fontSize(FONT_LABEL).fontColor(this.theme.muted)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('详情')
          .fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
          .onClick(() => {
            this.account.loadPointLogs(this.ctx());
            this.open(MySubpage.ACCOUNT);
          })
      }.width('100%')
      if (this.account.loggedIn) {
        Row({ space: 8 }) {
          Text('梦点 ' + this.account.points).fontSize(FONT_LABEL).fontColor(this.theme.muted)
          Text(this.account.checkedIn ? '今日已签' :
            (this.account.action === 'checkin' ? '签到中…' : '签到 +10'))
            .fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(RADIUS_CAPSULE)
            .backgroundColor(ThemeService.alpha(this.theme.primary, 0.14))
            .onClick(() => { this.doCheckin(); })
          Text('消息 ' + this.account.messageUsed + '/3')
            .fontSize(FONT_LABEL).fontColor(this.theme.muted)
        }.width('100%')
      } else {
        Text('登录后可使用签到、消息和在线账户功能')
          .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
      }
      if (this.account.statusText !== '') {
        Text(this.account.statusText).fontSize(FONT_LABEL)
          .fontColor(this.theme.primaryText).width('100%')
      }
      Row({ space: 8 }) {
        Text('公告与消息').fontSize(FONT_LABEL).fontColor(this.theme.ink).layoutWeight(1)
        Text(this.account.announcements.length + ' 条公告')
          .fontSize(FONT_LABEL).fontColor(this.theme.muted)
        Text('查看').fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
      }.width('100%').onClick(() => { this.open(MySubpage.ANNOUNCEMENTS); })
      if (this.account.announcements.length > 0) {
        Text('最新：' + this.account.announcements[0].title)
          .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%').padding(16).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
  }

  @Builder
  StatsSummary() {
    Column({ space: 8 }) {
      Row() {
        Text('播放统计').fontSize(FONT_BODY).fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink).layoutWeight(1)
        Text('详情').fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
      }.width('100%').onClick(() => { this.open(MySubpage.STATS); })
      Row({ space: 8 }) {
        Text('账号 ' + this.stats.account.playedSongCount + ' 首')
          .fontSize(FONT_LABEL).fontColor(this.theme.muted)
        Text('本机记录 ' + this.stats.local.playRecordCount + ' 次')
          .fontSize(FONT_LABEL).fontColor(this.theme.muted)
        Text('歌单 ' + this.stats.local.customPlaylistCount)
          .fontSize(FONT_LABEL).fontColor(this.theme.muted)
      }.width('100%')
      Text(this.stats.accountState === 'unauthenticated' ? '账号统计：登录后同步 · 本机数据独立可用'
        : (this.stats.accountState === 'stale' ? '账号统计：暂时离线，显示上次成功数据' : '账号统计 / 本机统计已分开显示'))
        .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
    }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
  }

  @Builder
  HomePlaylists() {
    Column({ space: 8 }) {
      Row() {
        Text('我的歌单').fontSize(FONT_BODY).fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink).layoutWeight(1)
        Text('全部').fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
      }.width('100%').onClick(() => { this.open(MySubpage.PLAYLISTS); })
      if (this.playlists.playlists.length === 0) {
        Text('还没有本地歌单').fontSize(FONT_LABEL).fontColor(this.theme.muted)
      } else {
        ForEach(this.playlists.playlists.slice(0, 3), (p: Playlist) => {
          Row({ space: 8 }) {
            SymbolGlyph(p.systemReserved ? $r('sys.symbol.heart_fill') : $r('sys.symbol.rectangle_stack'))
              .fontSize(15).fontColor([p.systemReserved ? this.theme.primary : this.theme.muted])
            Text(p.name).fontSize(FONT_LABEL).fontColor(this.theme.ink).layoutWeight(1)
          }.width('100%')
        })
      }
      Text('在线歌单与本地歌单将在同一页分区展示')
        .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
    }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
  }

  @Builder
  HomeHistory() {
    Column({ space: 8 }) {
      Row() {
        Text('最近播放').fontSize(FONT_BODY).fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink).layoutWeight(1)
        Text(this.playlists.historyTracks.length + ' 首 · 查看')
          .fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
      }.width('100%').onClick(() => { this.playlists.loadHistory(); this.open(MySubpage.HISTORY); })
      ForEach(this.playlists.historyTracks.slice(0, 3), (track: Track) => {
        Text((track.title !== '' ? track.title : track.path) + ' · ' + track.artist)
          .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (track: Track) => String(track.id))
      if (this.playlists.historyTracks.length === 0) {
        Text('还没有播放记录').fontSize(FONT_LABEL).fontColor(this.theme.muted)
      }
    }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
  }

  @Builder
  Home() {
    Scroll() {
      Column({ space: 12 }) {
        this.Header('我的')
        this.AccountSummary()
        this.StatsSummary()
        this.HomePlaylists()
        this.HomeHistory()
        Row({ space: 8 }) {
          Text('设置').fontSize(FONT_BODY).fontColor(this.theme.ink).layoutWeight(1)
          Text('账户、绑定、主题、背景、服务器与诊断')
            .fontSize(FONT_LABEL).fontColor(this.theme.muted)
        }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
          .onClick(() => { this.open(MySubpage.SETTINGS); })
      }.width('100%').padding(20)
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }

  @Builder
  History() {
    Scroll() {
      Column({ space: 10 }) {
        this.Header('播放历史')
        if (this.playlists.historyTracks.length === 0) {
          EmptyState({ symbol: $r('sys.symbol.clock_fill'), title: '空空如也', hint: '播放历史' })
        } else {
          ForEach(this.playlists.historyTracks, (track: Track, index: number) => {
            Row({ space: 10 }) {
              CoverThumb({ uri: track.coverPath === '' ? '' : 'file://' + this.ctx().filesDir + '/' + track.coverPath,
                thumbSize: 42 })
              Column({ space: 2 }) {
                Text(track.title !== '' ? track.title : track.path).fontSize(FONT_BODY)
                  .fontColor(this.theme.ink).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(track.artist).fontSize(FONT_LABEL).fontColor(this.theme.muted)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%').padding(10).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
              .onClick(() => { if (!track.missing) { queueViewModel.playFromList(this.playlists.historyTracks, index, this.ctx()); } })
          }, (track: Track, index: number) => String(track.id) + '_' + String(index))
        }
        Text('清空历史').fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
          .onClick(() => { this.playlists.clearHistory(); })
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }

  @Builder
  Stats() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          this.Header('播放统计')
          Text('刷新').fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
            .onClick(() => { this.stats.refresh(this.ctx()); })
        }.width('100%')
        Column({ space: 8 }) {
          Text('DreamMusic 账户').fontSize(FONT_BODY).fontColor(this.theme.ink)
          if (this.stats.accountState === 'unauthenticated') {
            Text('未登录，账户统计不可用；本机统计仍可查看')
              .fontSize(FONT_LABEL).fontColor(this.theme.muted)
          } else if (this.stats.accountState === 'loading') {
            Text('正在同步账户统计…').fontSize(FONT_LABEL).fontColor(this.theme.muted)
          } else {
            Text('累计播放时长 ' + Math.floor(this.stats.account.playSeconds / 60) + ' 分钟')
              .fontSize(FONT_LABEL).fontColor(this.theme.muted)
            Text('播放歌曲 ' + this.stats.account.playedSongCount + ' 首')
              .fontSize(FONT_LABEL).fontColor(this.theme.muted)
            Text('来源：账户 · 同步于 ' + new Date(this.stats.account.syncedAt).toLocaleString())
              .fontSize(FONT_LABEL).fontColor(this.theme.muted)
            if (this.stats.accountState === 'stale' || this.stats.accountState === 'unavailable') {
              Text(this.stats.accountState === 'stale' ? '暂时离线，以上为上次成功数据' : '账户统计暂时不可用')
                .fontSize(FONT_LABEL).fontColor(this.theme.errorColor)
            }
          }
        }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
        Column({ space: 8 }) {
          Text('本机设备').fontSize(FONT_BODY).fontColor(this.theme.ink)
          Text('播放记录 ' + this.stats.local.playRecordCount + ' 次（最多保留 500 条事件）')
            .fontSize(FONT_LABEL).fontColor(this.theme.muted)
          Text('自建歌单 ' + this.stats.local.customPlaylistCount + ' 个（不含我喜欢的音乐）')
            .fontSize(FONT_LABEL).fontColor(this.theme.muted)
          Text('收藏 ' + this.stats.local.favoriteCount + ' 首 · 来源：本机')
            .fontSize(FONT_LABEL).fontColor(this.theme.muted)
        }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }

  @Builder
  Account() {
    Scroll() {
      Column({ space: 12 }) {
        this.Header('账户详情')
        if (!this.account.loggedIn) {
          Text('登录后可查看梦点余额、兑换码和梦点流水').fontSize(FONT_LABEL).fontColor(this.theme.muted)
            .onClick(() => { this.onLogin(); })
        } else {
          Text('梦点余额 ' + this.account.points).fontSize(FONT_BODY).fontColor(this.theme.ink)
          Row({ space: 8 }) {
            TextInput({ placeholder: '兑换码', text: this.redeemCode }).layoutWeight(1)
              .fontSize(FONT_LABEL).fontColor(this.theme.ink).backgroundColor(this.theme.card)
              .onChange((v: string) => { this.redeemCode = v; })
            Text(this.account.action === 'redeem' ? '兑换中…' : '兑换')
              .fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
              .padding(8).onClick(() => { this.account.redeem(this.ctx(), this.redeemCode); })
          }.width('100%')
          Text('最近梦点流水').fontSize(FONT_BODY).fontColor(this.theme.ink)
          if (this.account.pointLogs.length === 0) {
            Text('暂无流水').fontSize(FONT_LABEL).fontColor(this.theme.muted)
          } else {
            ForEach(this.account.pointLogs.slice(0, 10), (log: DreamPointLog) => {
              Row() {
                Text(log.type + (log.note === null ? '' : ' · ' + log.note))
                  .fontSize(FONT_LABEL).fontColor(this.theme.muted).layoutWeight(1)
                Text((log.delta >= 0 ? '+' : '') + log.delta + ' / ' + log.balanceAfter)
                  .fontSize(FONT_LABEL).fontColor(this.theme.ink)
              }.width('100%').padding(10).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
            }, (log: DreamPointLog) => String(log.id))
          }
        }
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }

  @Builder
  Announcements() {
    Scroll() {
      Column({ space: 12 }) {
        this.Header('公告与消息')
        Text('公告').fontSize(FONT_BODY).fontWeight(FontWeight.Medium).fontColor(this.theme.ink)
        if (this.account.announcements.length === 0) {
          Text('暂无公告或暂时无法加载').fontSize(FONT_LABEL).fontColor(this.theme.muted)
        } else {
          ForEach(this.account.announcements, (a: Announcement) => {
            Column({ space: 5 }) {
              Text(a.title).fontSize(FONT_BODY).fontColor(this.theme.ink)
              Text(a.content).fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
            }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
          }, (a: Announcement) => String(a.id))
        }
        Row() {
          Text('发消息').fontSize(FONT_BODY).fontColor(this.theme.ink).layoutWeight(1)
          Text(this.account.loggedIn ? this.account.messageUsed + '/3 · 剩余 ' + this.account.messageRemaining
            : '登录后可用').fontSize(FONT_LABEL).fontColor(this.theme.muted)
        }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
          .onClick(() => {
            if (!this.account.loggedIn) {
              this.onLogin();
            } else {
              this.messageExpanded = !this.messageExpanded;
            }
          })
        if (this.messageExpanded && this.account.loggedIn) {
          Column({ space: 8 }) {
            TextInput({ placeholder: '标题（≤40字）', text: this.msgTitle })
              .fontSize(FONT_LABEL).onChange((v: string) => { this.msgTitle = v; })
            TextInput({ placeholder: '内容（≤200字）', text: this.msgContent })
              .fontSize(FONT_LABEL).onChange((v: string) => { this.msgContent = v; })
            Text(this.account.action === 'message' ? '发送中…' : '发送（消耗 1 梦点）')
              .fontSize(FONT_LABEL).fontColor(this.theme.primaryText).padding(8)
              .onClick(() => { this.account.sendMessage(this.ctx(), this.msgTitle, this.msgContent); })
            Text('失败也扣点；每日最多 3 次，具体结果以服务器记账为准')
              .fontSize(FONT_LABEL).fontColor(this.theme.muted)
          }.width('100%').padding(14).borderRadius(RADIUS_CARD).backgroundColor(this.theme.card)
        }
        if (this.account.statusText !== '') {
          Text(this.account.statusText).fontSize(FONT_LABEL).fontColor(this.theme.primaryText)
        }
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }

  build() {
    if (this.page === MySubpage.HOME) {
      this.Home()
    } else if (this.page === MySubpage.PLAYLISTS) {
      PlaylistsPage({ onBack: () => { this.open(MySubpage.HOME); } })
    } else if (this.page === MySubpage.HISTORY) {
      this.History()
    } else if (this.page === MySubpage.STATS) {
      this.Stats()
    } else if (this.page === MySubpage.ACCOUNT) {
      this.Account()
    } else if (this.page === MySubpage.ANNOUNCEMENTS) {
      this.Announcements()
    } else {
      Column() {
        this.Header('设置')
        SettingsPage({
          onAccountChanged: () => {
            this.account.refresh(this.ctx());
            this.account.loadAnnouncements(this.ctx());
            this.stats.load(this.ctx());
          }
        })
      }.width('100%').height('100%')
    }
  }
}
