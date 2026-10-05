import { ThemeService } from '../service/theme/ThemeService';
import { common } from '@kit.AbilityKit';
import { OnlineSong, OnlineSearchGroup } from '../model/Entities';
import { OnlineSearchViewModel, searchSourceName } from '../viewmodel/OnlineSearchViewModel';
import { SearchSourcePage } from '../service/network/NetEaseApi';
import { ApiError } from '../service/network/ApiClient';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { onlineMusicViewModel } from '../viewmodel/OnlineMusicViewModel';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { PlayerState } from '../model/Playback';
import { networkViewModel } from '../viewmodel/NetworkViewModel';
import { SourceSelection } from './SourceSelection';
import { FONT_BODY, FONT_LABEL, RADIUS_CARD, CONTROL_HIT_SIZE, SPACE_SM } from '../common/DesignTokens';

function fmt(ms: number): string {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ':' + (s < 10 ? '0' + s : s.toString());
}

/**
 * 在线搜索子视图(阶段 v2,8/16 拍板):
 * 音乐库页头搜索图标进入;300ms 防抖搜索、滚动加载更多;
 * 聚合结果保留来源身份；点播沿用已有路径，只有符合网易音频边界的条目后台入库。
 */
@Component
export struct OnlineSearchView {
  @State player: PlayerViewModel = playerViewModel;
  @State theme: ThemeService = ThemeService.getInstance();
  onBack: () => void = () => {
  };
  onGoSettings: () => void = () => {
  };
  /** 未登录 → 打开登录盖层(阶段 v2.2) */
  onGoLogin: () => void = () => {
  };
  @State search: OnlineSearchViewModel = new OnlineSearchViewModel();
  @State errorText: string = '';
  @State busyId: number = -1;
  @State busyRef: string = '';
  @State progressText: string = '';
  @State errorCode: string = '';

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    // 未登录直接提示,引导去登录(本地歌不登录可听,在线功能需登录)
    if (!DreamMusicAuth.isLoggedIn(this.ctx())) {
      this.errorText = '请先登录,再使用在线搜索';
      this.errorCode = 'NEED_LOGIN';
    }
  }

  aboutToDisappear(): void {
    this.search.cancel();
  }

  private onKeyword(v: string): void {
    this.errorText = '';
    this.errorCode = '';
    this.search.changeKeyword(this.ctx(), v);
  }

  private async streamAndPlay(song: OnlineSong, automatic: boolean = false,
    sourceOptions: OnlineSong[] = []): Promise<void> {
    if (this.busyId !== -1 || this.busyRef !== '') { return; }
    this.busyId = song.id;
    this.busyRef = song.mediaRef !== undefined ? song.mediaRef : '';
    this.progressText = '正在加载音乐…';
    this.errorText = '';
    this.errorCode = '';
    const playback = onlineMusicViewModel.playSong(this.ctx(), song, automatic, sourceOptions);
    const request = playerViewModel.requestId;
    try {
      await playback;
      if (playerViewModel.isCurrentRequest(request)) {
        this.progressText = '播放已开始';
        networkViewModel.markOnline();
      } else {
        this.progressText = '';
      }
    } catch (err) {
      if (playerViewModel.isCurrentRequest(request)) {
        OnlineSearchView.reportConnectivity(err as Error);
        this.progressText = '';
        this.errorText = playerViewModel.errorText;
        this.errorCode = playerViewModel.errorCode;
      }
    } finally {
      this.busyId = -1;
      this.busyRef = '';
    }
  }

  private playEntry(group: OnlineSearchGroup, song: OnlineSong, automatic: boolean = false): void {
    if (this.busyId !== -1 || this.busyRef !== '') { return; }
    if (song.mediaRef !== undefined) { this.search.selectEntry(group.id, song.mediaRef); }
    this.streamAndPlay(song, automatic, group.entries);
  }

  /** 只有网络/上游类错误才算离线;401/403/301 说明中间层可达,保持在线 */
  private static reportConnectivity(err: Error): void {
    if (err instanceof ApiError && (err.code === 'NETWORK' || err.code === 'UPSTREAM_DOWN')) {
      networkViewModel.markOffline();
    } else {
      networkViewModel.markOnline();
    }
  }

  private isBusy(song: OnlineSong): boolean {
    if (song.mediaRef !== undefined && song.mediaRef !== '') {
      return this.busyRef === song.mediaRef;
    }
    return this.busyId === song.id;
  }

  /** 需要用户去设置处理的错误(登录/绑定/绑定失效) */
  private isAuthError(): boolean {
    const code = this.errorCode !== '' ? this.errorCode : this.search.errorCode;
    return code === 'NEED_LOGIN' || code === 'UNAUTHORIZED' || code === 'FORBIDDEN' || code === 'BIND_INVALID';
  }

  @Builder
  Cover(url: string) {
    Stack() {
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
      if (url !== '') {
        Image(url)
          .width(44)
          .height(44)
          .borderRadius(11)
          .objectFit(ImageFit.Cover)
      }
    }
  }

  @Builder
  ResultRow(song: OnlineSong, group: OnlineSearchGroup, automatic: boolean = false) {
    Row({ space: 12 }) {
      this.Cover(song.coverUrl)
      Column({ space: 3 }) {
        Text(song.name + (song.versionTags !== undefined && song.versionTags.length > 0 ? ' · ' + song.versionTags.join(' / ') : ''))
          .fontSize(FONT_BODY)
          .fontColor(this.theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${searchSourceName(song.source !== undefined ? song.source : 'api-enhanced')} · ${song.artist}${song.album !== '' ? ' · ' + song.album : ''}`)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (song.originalTitle !== undefined && song.originalTitle !== '' && song.originalTitle !== song.name) {
          Text(song.originalTitle)
            .fontSize(FONT_LABEL)
            .fontColor(this.theme.muted)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isBusy(song)) {
        Text(this.progressText)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.primaryText)
      } else {
        Text(fmt(song.durationMs))
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
    .constraintSize({ minHeight: CONTROL_HIT_SIZE })
    .stateStyles({
      pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
    })
    .onClick(() => {
      this.playEntry(group, song, automatic);
    })
    if (!automatic && song.mediaRef !== undefined &&
      this.player.sourceOptions.some((entry: OnlineSong): boolean => entry.mediaRef === song.mediaRef)) {
      Button('为当前曲目使用' + searchSourceName(song.source ?? 'api-enhanced'))
        .constraintSize({ minHeight: CONTROL_HIT_SIZE })
        .fontSize(FONT_LABEL)
        .fontColor(this.theme.primaryText)
        .backgroundColor(Color.Transparent)
        .enabled(this.player.state !== PlayerState.PREPARING)
        .onClick(() => { playerViewModel.selectSource(song.mediaRef ?? ''); })
    }
  }

  @Builder
  GroupRow(group: OnlineSearchGroup) {
    Column({ space: SPACE_SM }) {
      this.ResultRow(this.search.groupSong(group), group, true)
      if (group.entries.length > 1) {
        Button((group.expanded ? '收起' : '展开') + group.entries.length + ' 个来源条目')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.primaryText)
          .backgroundColor(Color.Transparent)
          .constraintSize({ minHeight: CONTROL_HIT_SIZE })
          .accessibilityText((group.expanded ? '收起' : '展开') + this.search.groupSong(group).name + '的原平台来源')
          .onClick(() => { this.search.toggleGroup(group.id); })
        if (group.expanded) {
          ForEach(group.entries, (entry: OnlineSong) => {
            this.ResultRow(entry, group)
          }, (entry: OnlineSong) => entry.mediaRef !== undefined ? entry.mediaRef : 'api-enhanced|' + entry.id)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: SPACE_SM })
  }

  @Builder
  Hint(symbol: Resource, title: string, hint: string) {
    Column({ space: 8 }) {
      SymbolGlyph(symbol)
        .fontSize(34)
        .fontColor([this.theme.muted])
      Text(title)
        .fontSize(15)
        .fontColor(this.theme.ink)
      Text(hint)
        .fontSize(FONT_LABEL)
        .fontColor(this.theme.muted)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 60 })
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
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
          this.search.cancel();
          this.onBack();
        })
        TextInput({ placeholder: '搜索网易 / QQ / 酷狗', text: this.search.keyword })
          .fontSize(14)
          .fontColor(this.theme.ink)
          .placeholderColor(this.theme.muted)
          .backgroundColor(this.theme.card)
          .borderRadius(12)
          .height(40)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.onKeyword(v);
          })
      }
      .width('100%')

      if (this.search.loading) {
        Text('搜索中…')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
      }
      if (this.errorText !== '' || this.search.errorText !== '') {
        Column({ space: 6 }) {
          Text(this.errorText !== '' ? this.errorText : this.search.errorText)
            .fontSize(FONT_LABEL)
            .fontColor(this.theme.errorColor)
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.isAuthError()) {
            Row({ space: 4 }) {
              Text(this.errorCode === 'NEED_LOGIN' || this.search.errorCode === 'UNAUTHORIZED' ? '去登录' : '去设置')
                .fontSize(13)
                .fontColor(this.theme.primaryText)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(13)
                .fontColor([this.theme.primaryText])
            }
            .padding(6)
            .borderRadius(999)
            .backgroundColor(ThemeService.alpha(this.theme.primary, 0.12))
            .onClick(() => {
              if (this.errorCode === 'NEED_LOGIN' || this.search.errorCode === 'UNAUTHORIZED') {
                this.onGoLogin();
              } else {
                this.onGoSettings();
              }
            })
          } else if (this.errorText !== '') {
            Button('重试播放')
              .fontSize(FONT_LABEL)
              .fontColor(this.theme.primaryText)
              .backgroundColor(this.theme.card)
              .constraintSize({ minHeight: 48 })
              .onClick(() => {
                playerViewModel.retry().then(() => {
                  this.errorText = playerViewModel.errorText;
                  this.errorCode = playerViewModel.errorCode;
                });
              })
          } else if (this.search.errorText !== '') {
            Button(this.search.errorCode === 'INVALID_SEARCH_SESSION' ? '重新搜索' : '重试搜索')
              .fontSize(FONT_LABEL)
              .fontColor(this.theme.primaryText)
              .backgroundColor(this.theme.card)
              .constraintSize({ minHeight: 48 })
              .enabled(!this.search.loading)
              .onClick(() => {
                this.search.retry(this.ctx());
              })
          }
        }
        .width('100%')
      }
      if (this.player.state === PlayerState.ERROR) {
        SourceSelection()
      }
      if (this.search.status === 'partial_failure' || this.search.status === 'all_failed') {
        Text(this.search.status === 'all_failed' ? '所有来源搜索失败，请重试' : '部分来源搜索失败，已保留可用结果')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
      }
      ForEach(this.search.sources, (source: SearchSourcePage) => {
        if (source.status === 'failed') {
          Button('重试' + searchSourceName(source.source))
            .fontSize(FONT_LABEL)
            .fontColor(this.theme.primaryText)
            .backgroundColor(this.theme.card)
            .constraintSize({ minHeight: 48 })
            .enabled(!this.search.loading)
            .onClick(() => { this.search.retrySource(this.ctx(), source.source); })
        }
      }, (source: SearchSourcePage) => source.source)
      if (this.search.keyword.trim() === '') {
        this.Hint($r('sys.symbol.magnifyingglass'), '搜索在线音乐',
          '同时查询网易、QQ、酷狗，点选歌曲播放')
      } else if (!this.search.loading && this.search.errorText === '' && this.search.status === 'empty') {
        this.Hint($r('sys.symbol.music_note_list'), '没有找到相关歌曲',
          '换个关键词试试')
      }
      if (this.search.results.length > 0) {
        List({ space: 10 }) {
          ForEach(this.search.groups, (group: OnlineSearchGroup) => {
            ListItem() {
              this.GroupRow(group)
            }
          }, (group: OnlineSearchGroup) => group.id)
          if (this.search.hasMore) {
            ListItem() {
              Text('上拉加载更多')
                .fontSize(FONT_LABEL)
                .fontColor(this.theme.muted)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(10)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .onReachEnd(() => {
          if (this.search.hasMore && !this.search.loading && this.search.errorText === '') {
            this.search.loadMore(this.ctx());
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
