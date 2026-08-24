import { ThemeService } from '../service/theme/ThemeService';
import { common } from '@kit.AbilityKit';
import { OnlineSong, Track } from '../model/Entities';
import { NetEaseApi } from '../service/network/NetEaseApi';
import { ApiError } from '../service/network/ApiClient';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { OnlineDownloadService } from '../service/network/OnlineDownloadService';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { playerViewModel } from '../viewmodel/PlayerViewModel';
import { networkViewModel } from '../viewmodel/NetworkViewModel';
import { FONT_BODY, FONT_LABEL, RADIUS_CARD } from '../common/DesignTokens';

function fmt(ms: number): string {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ':' + (s < 10 ? '0' + s : s.toString());
}

/**
 * 在线搜索子视图(阶段 v2,8/16 拍板):
 * 音乐库页头搜索图标进入;300ms 防抖搜索、滚动加载更多;
 * 点结果 = 直链流式即播 + 后台下载落盘入库;下载完成后原位替换队列条目。
 */
@Component
export struct OnlineSearchView {
  @State theme: ThemeService = ThemeService.getInstance();
  onBack: () => void = () => {
  };
  onGoSettings: () => void = () => {
  };
  /** 未登录 → 打开登录盖层(阶段 v2.2) */
  onGoLogin: () => void = () => {
  };
  @State keyword: string = '';
  @State results: OnlineSong[] = [];
  @State loading: boolean = false;
  @State errorText: string = '';
  @State hasMore: boolean = false;
  @State busyId: number = -1;
  @State busyRef: string = '';
  @State progressText: string = '';
  @State errorCode: string = '';
  private searchTimer: number = -1;
  private pageOffset: number = 0;
  private inflight: boolean = false;

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

  private onKeyword(v: string): void {
    this.keyword = v;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.doSearch(0);
    }, 300);
  }

  private async doSearch(offset: number): Promise<void> {
    const kw = this.keyword.trim();
    if (kw === '' || this.inflight) {
      return;
    }
    this.inflight = true;
    this.loading = true;
    this.errorText = '';
    this.errorCode = '';
    try {
      const page = await NetEaseApi.search(this.ctx(), kw, offset);
      networkViewModel.markOnline();
      if (offset === 0) {
        this.results = page.songs;
      } else {
        this.results = this.results.concat(page.songs);
      }
      this.pageOffset = offset + page.songs.length;
      this.hasMore = page.hasMore;
    } catch (err) {
      OnlineSearchView.reportConnectivity(err as Error);
      this.errorText = (err as Error).message;
      this.errorCode = err instanceof ApiError ? err.code : '';
      if (offset === 0) {
        this.results = [];
      }
    } finally {
      this.loading = false;
      this.inflight = false;
    }
  }

  private async streamAndPlay(song: OnlineSong): Promise<void> {
    if (song.id > 0) {
      const local = await OnlineDownloadService.findLocal(this.ctx(), song.id);
      if (local !== null) {
        this.errorText = '';
        this.errorCode = '';
        await queueViewModel.playFromList([local], 0, this.ctx());
        return;
      }
    }
    if (this.busyId !== -1 || this.busyRef !== '') {
      return;
    }
    this.busyId = song.id;
    this.busyRef = song.mediaRef !== undefined ? song.mediaRef : '';
    this.progressText = '获取播放链接…';
    this.errorText = '';
    this.errorCode = '';
    try {
      const mediaRef = song.mediaRef !== undefined ? song.mediaRef : '';
      const url = await NetEaseApi.resolveUrl(this.ctx(), song.id, mediaRef);
      if (url === '') {
        this.errorText = '无版权或需要会员,无法播放';
        this.busyId = -1;
        this.busyRef = '';
        return;
      }
      // 搜索结果偶尔不带专辑图；用详情接口补齐，避免播放页退化成无封面。
      let coverUrl = song.coverUrl;
      if (coverUrl === '') {
        coverUrl = await NetEaseApi.songDetailCover(this.ctx(), song.id, mediaRef).catch(() => '');
      }
      const transient: Track = {
        id: song.id > 0 ? -song.id : -1,
        path: 'music/online-stream.mp3',
        title: song.name,
        artist: song.artist,
        album: song.album,
        durationMs: song.durationMs,
        coverPath: '',
        importedAt: Date.now(),
        missing: false,
        neteaseId: song.id > 0 ? song.id : 0,
        streamUrl: url,
        streamCoverUrl: coverUrl,
        mediaRef: mediaRef
      };
      // 先在线播放，下载失败不打断当前播放。
      await queueViewModel.playFromList([transient], 0, this.ctx());
      if (playerViewModel.errorText !== '') {
        this.errorText = '播放失败:' + playerViewModel.errorText;
        this.busyId = -1;
        this.busyRef = '';
        return;
      }
      networkViewModel.markOnline();
      if (song.id <= 0) {
        this.progressText = '在线播放中';
        this.busyId = -1;
        this.busyRef = '';
        return;
      }
      this.progressText = '播放中 · 下载中 0%';
      OnlineDownloadService.ensureLocal(this.ctx(), song, (pct: number): void => {
        this.progressText = '播放中 · 下载中 ' + pct + '%';
      }).then((track: Track) => {
        this.progressText = '已下载，可离线播放';
        const current = playerViewModel.currentTrack;
        if (current !== null && current.neteaseId === song.id &&
          current.streamUrl !== undefined && current.streamUrl !== '') {
          queueViewModel.swapCurrentWithLocal(track);
        }
        this.busyId = -1;
        this.busyRef = '';
      }).catch((err: Error) => {
        this.progressText = '在线播放中 · 下载失败:' + err.message;
        this.busyId = -1;
        this.busyRef = '';
      });
    } catch (err) {
      OnlineSearchView.reportConnectivity(err as Error);
      this.errorText = (err as Error).message;
      this.errorCode = err instanceof ApiError ? err.code : '';
      this.busyId = -1;
      this.busyRef = '';
    }
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
    return this.errorCode === 'NEED_LOGIN' || this.errorCode === 'FORBIDDEN' ||
      this.errorCode === 'BIND_INVALID';
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
  ResultRow(song: OnlineSong) {
    Row({ space: 12 }) {
      this.Cover(song.coverUrl)
      Column({ space: 3 }) {
        Text(song.name)
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
    .stateStyles({
      pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
    })
    .onClick(() => {
      this.streamAndPlay(song);
    })
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
          this.onBack();
        })
        TextInput({ placeholder: '搜索网易云音乐', text: this.keyword })
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

      if (this.loading) {
        Text('搜索中…')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
      } else if (this.errorText !== '') {
        Column({ space: 6 }) {
          Text(this.errorText)
            .fontSize(FONT_LABEL)
            .fontColor(this.theme.errorColor)
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.isAuthError()) {
            Row({ space: 4 }) {
              Text(this.errorCode === 'NEED_LOGIN' ? '去登录' : '去设置')
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
              if (this.errorCode === 'NEED_LOGIN') {
                this.onGoLogin();
              } else {
                this.onGoSettings();
              }
            })
          }
        }
        .width('100%')
      } else if (this.keyword.trim() === '') {
        this.Hint($r('sys.symbol.magnifyingglass'), '搜索在线音乐',
          '搜索 DreamMusic 服务，点结果自动下载到音乐库并播放')
      } else if (this.results.length === 0) {
        this.Hint($r('sys.symbol.music_note_list'), '没有找到相关歌曲',
          '换个关键词试试')
      } else {
        List({ space: 10 }) {
          ForEach(this.results, (song: OnlineSong) => {
            ListItem() {
              this.ResultRow(song)
            }
          })
          if (this.hasMore) {
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
          if (this.hasMore && !this.loading) {
            this.doSearch(this.pageOffset);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
