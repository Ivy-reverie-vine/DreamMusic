import { playbackRuntime } from '../viewmodel/PlaybackRuntime';
import { ThemeService } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { lyricsViewModel } from '../viewmodel/LyricsViewModel';
import { common } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { MusicLibraryPage } from './MusicLibraryPage';
import { NowPlayingPage } from './NowPlayingPage';
import { QueuePage } from './QueuePage';
import { MyPageV2 } from './MyPageV2';
import { LoginView } from '../components/LoginView';
import { QrBindView } from '../components/QrBindView';
import { BackgroundLayer } from '../components/BackgroundLayer';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { ApiError } from '../service/network/ApiClient';
import { OnlineMusicService } from '../service/network/OnlineMusicService';
import { MiniPlayerBar } from '../components/MiniPlayerBar';
import { PlayerState } from '../model/Playback';
import { accountViewModel } from '../viewmodel/AccountViewModel';
import { MOTION_THEME_FADE_MS } from '../common/DesignTokens';
import { playbackStatsViewModel } from '../viewmodel/PlaybackStatsViewModel';
import { playbackLaunch, ExternalDestination, PLAYLIST_DESTINATION } from '../model/PlaybackLaunch';
import {
  BackAction, BackDispatcher, MySubpage, RootTab, NavigationState, openMyPage, resolveBack, selectRoot
} from '../model/Navigation';

const RIPPLE_DIAMETER = 64;

interface NavTab {
  label: string;
  icon: Resource;
}

/** 应用主壳：四个稳定根入口、常驻播放器和唯一的鸿蒙返回策略。 */
@Entry
@Component
struct IndexV2 {
  @State theme: ThemeService = ThemeService.getInstance();
  @State current: RootTab = RootTab.LIBRARY;
  @State myPage: MySubpage = MySubpage.HOME;
  @State sourceRoot: RootTab = RootTab.MY;
  @State playlistRequest: string = '';
  private externalSequence: number = 0;
  @State player: PlayerViewModel = playerViewModel;
  @State booting: boolean = true;
  @State loggedIn: boolean = false;
  @State loginPromptVisible: boolean = false;
  @State showLoginOverlay: boolean = false;
  @State showBindAtStart: boolean = false;
  @State rippleVisible: boolean = false;
  @State rippleX: number = 0;
  @State rippleY: number = 0;
  @State rippleRelease: boolean = false;
  private rippleHideTimer: number = -1;
  private playbackEntry: boolean = false;
  private childBack: BackDispatcher = new BackDispatcher();
  private tabs: NavTab[] = [
    { label: '音乐库', icon: $r('sys.symbol.music_note_list') },
    { label: '正在播放', icon: $r('sys.symbol.play_circle') },
    { label: '队列', icon: $r('sys.symbol.list_bullet') },
    { label: '我的', icon: $r('sys.symbol.person_crop_circle_fill') }
  ];

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private navigation(): NavigationState {
    return { root: this.current, myPage: this.myPage, sourceRoot: this.sourceRoot };
  }

  /** 点击返回与屏幕边缘返回统一进入这里。 */
  onBackPress(): boolean {
    const action = resolveBack(this.navigation(),
      this.showLoginOverlay || this.showBindAtStart || this.loginPromptVisible);
    if (action === BackAction.CLOSE_OVERLAY) {
      if (this.showLoginOverlay) {
        this.showLoginOverlay = false;
      } else if (this.showBindAtStart) {
        this.showBindAtStart = false;
      } else {
        this.loginPromptVisible = false;
      }
      return true;
    }
    if (this.childBack.handle()) { return true; }
    if (action === BackAction.MY_HOME) {
      this.myPage = MySubpage.HOME;
      this.sourceRoot = RootTab.MY;
      return true;
    }
    if (action === BackAction.SOURCE_ROOT) {
      this.current = this.sourceRoot;
      this.myPage = MySubpage.HOME;
      this.sourceRoot = this.current;
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    playbackLaunch.attach((target: ExternalDestination) => this.openExternalEntry(target));
    const ctx = this.ctx();
    lyricsViewModel.setContext(ctx);
    playerViewModel.coverColorHandler = (t) => {
      BackgroundAdapter.applyCoverColors(ctx, this.theme, t, () => playerViewModel.currentTrack === t,
        (colors) => {
          if (accessibility.isAnimationReduceEnabledSync()) {
            this.theme.applyExtracted(colors.primary, colors.secondary);
          } else {
            animateTo({ duration: MOTION_THEME_FADE_MS, curve: Curve.EaseOut }, () => {
              this.theme.applyExtracted(colors.primary, colors.secondary);
            });
          }
        });
    };
    playbackRuntime.ensureReady(ctx).then(() => {
      // 卡片可能已在后台恢复/播放，页面挂载只补 UI 派生数据，绝不重新恢复队列。
      lyricsViewModel.setContext(ctx);
      const track = playerViewModel.currentTrack;
      if (track !== null) { playerViewModel.coverColorHandler?.(track); }
    }).catch(() => {});
    this.checkGate();
  }

  aboutToDisappear(): void {
    playbackLaunch.detach();
    if (this.rippleHideTimer >= 0) {
      clearTimeout(this.rippleHideTimer);
      this.rippleHideTimer = -1;
    }
  }

  private async checkGate(): Promise<void> {
    const ctx = this.ctx();
    await DreamMusicAuth.initialize(ctx);
    if (this.playbackEntry) { this.booting = false; return; }
    if (!DreamMusicAuth.isLoggedIn(ctx)) {
      this.booting = false;
      this.loggedIn = false;
      this.loginPromptVisible = true;
      return;
    }
    try {
      const user = await DreamMusicAuth.me(ctx);
      if (this.playbackEntry) { this.booting = false; return; }
      if (user === null) {
        this.booting = false;
        this.loggedIn = false;
        this.loginPromptVisible = true;
        return;
      }
      this.loggedIn = true;
      if (!user.bound || user.bindInvalid) {
        this.showBindAtStart = true;
      } else {
        OnlineMusicService.prefetch(ctx).catch(() => {
        });
      }
    } catch (err) {
      if (this.playbackEntry) { this.booting = false; return; }
      if (err instanceof ApiError && err.code === 'UNAUTHORIZED') {
        await DreamMusicAuth.logout(ctx);
        OnlineMusicService.clearCache(ctx);
        this.loggedIn = false;
        if (this.playbackEntry) { this.booting = false; return; }
        this.loginPromptVisible = true;
      } else {
        this.loggedIn = true;
      }
    }
    this.booting = false;
  }

  @Builder
  StartBindSheet() {
    Column({ space: 12 }) {
      Text('绑定网易云账号')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .width('100%')
      QrBindView({ onBound: () => { this.showBindAtStart = false; } })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.theme.bg)
  }

  private handleNavTouch(e: TouchEvent): void {
    if (e.touches.length === 0) {
      return;
    }
    const t = e.touches[0];
    if (e.type === TouchType.Down) {
      try {
        if (accessibility.isAnimationReduceEnabledSync()) {
          return;
        }
      } catch (err) {
      }
      this.rippleX = t.windowX;
      this.rippleY = t.windowY;
      this.rippleRelease = false;
      this.rippleVisible = true;
    } else if (e.type === TouchType.Move && this.rippleVisible) {
      this.rippleX = t.windowX;
      this.rippleY = t.windowY;
    } else if ((e.type === TouchType.Up || e.type === TouchType.Cancel) && this.rippleVisible) {
      animateTo({ duration: 260, curve: Curve.EaseOut }, () => { this.rippleRelease = true; });
      if (this.rippleHideTimer >= 0) {
        clearTimeout(this.rippleHideTimer);
      }
      this.rippleHideTimer = setTimeout(() => { this.rippleVisible = false; }, 320);
    }
  }

  private openMyPage(page: MySubpage, source: RootTab = RootTab.MY): void {
    const next = openMyPage(this.navigation(), page, source);
    this.current = next.root;
    this.myPage = next.myPage;
    this.sourceRoot = next.sourceRoot;
  }

  private selectTab(index: number): void {
    this.playlistRequest = '';
    const next = selectRoot(this.navigation(), index as RootTab);
    this.current = next.root;
    this.myPage = next.myPage;
    this.sourceRoot = next.sourceRoot;
  }

  private openPlaybackEntry(): void {
    this.playbackEntry = true;
    this.showLoginOverlay = false;
    this.showBindAtStart = false;
    this.loginPromptVisible = false;
    this.booting = false;
    this.selectTab(RootTab.NOW_PLAYING);
  }

  private openExternalEntry(target: ExternalDestination): void {
    this.openPlaybackEntry();
    if (target.destination === PLAYLIST_DESTINATION) {
      this.externalSequence++;
      this.playlistRequest = `${target.playlistId}:${this.externalSequence}`;
      this.current = RootTab.MY;
      this.myPage = MySubpage.PLAYLISTS;
      this.sourceRoot = RootTab.MY;
    }
  }

  @Builder
  PageContent() {
    if (this.current === RootTab.LIBRARY) {
      MusicLibraryPage({
        backDispatcher: this.childBack,
        onGoSettings: () => { this.openMyPage(MySubpage.SETTINGS, RootTab.LIBRARY); },
        onGoLogin: () => { this.showLoginOverlay = true; }
      })
    } else if (this.current === RootTab.NOW_PLAYING) {
      NowPlayingPage({
        onGoLibrary: () => { this.selectTab(RootTab.LIBRARY); },
        onGoSettings: () => { this.openMyPage(MySubpage.SETTINGS, RootTab.NOW_PLAYING); }
      })
    } else if (this.current === RootTab.QUEUE) {
      QueuePage()
    } else {
      MyPageV2({
        page: this.myPage,
        playlistRequest: this.playlistRequest,
        onPlaylistRequestConsumed: () => { this.playlistRequest = ''; },
        backDispatcher: this.childBack,
        onBack: () => { this.onBackPress(); },
        onNavigate: (page: MySubpage) => { this.openMyPage(page, RootTab.MY); },
        onLogin: () => { this.showLoginOverlay = true; }
      })
    }
  }

  @Builder
  ResidentPlayerBar() {
    if (this.current !== RootTab.NOW_PLAYING && this.player.currentTrack !== null) {
      Column() {
        MiniPlayerBar({
          track: this.player.currentTrack,
          onGoLibrary: () => { this.selectTab(RootTab.LIBRARY); },
          onGoSettings: () => { this.openMyPage(MySubpage.SETTINGS, this.current); },
          playing: this.player.state === PlayerState.PLAYING,
          onOpen: (): void => { this.selectTab(RootTab.NOW_PLAYING); },
          onToggle: (): Promise<void> => { return this.player.togglePause(); },
          onNext: (): Promise<void> => { return queueViewModel.playNext(); }
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
    }
  }

  private login(): void {
    this.loggedIn = true;
    this.loginPromptVisible = false;
    this.showLoginOverlay = false;
    accountViewModel.refresh(this.ctx());
    accountViewModel.loadAnnouncements(this.ctx());
    playbackStatsViewModel.load(this.ctx());
  }

  build() {
    if (this.booting) {
      Stack() {
        BackgroundLayer()
        Text('IvyReverie').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.theme.ink)
      }.width('100%').height('100%')
    } else if (!this.loggedIn && this.loginPromptVisible) {
      LoginView({ onLoggedIn: () => { this.login(); }, onSkip: () => { this.loginPromptVisible = false; } })
    } else {
      Stack() {
        BackgroundLayer({ nowPlaying: this.current === RootTab.NOW_PLAYING })
        Column() {
          Column() { this.PageContent() }.width('100%').layoutWeight(1)
          this.ResidentPlayerBar()
          Row() {
            ForEach(this.tabs, (item: NavTab, index: number) => {
              Column({ space: 2 }) {
                SymbolGlyph(item.icon).fontSize(20)
                  .fontColor([index === this.current ? this.theme.primaryText : this.theme.muted])
                Text(item.label).fontSize(11)
                  .fontColor(index === this.current ? this.theme.primaryText : this.theme.muted)
                  .fontWeight(index === this.current ? FontWeight.Medium : FontWeight.Normal)
              }
              .layoutWeight(1).constraintSize({ minHeight: 48 })
              .padding({ top: 10, bottom: 10 }).borderRadius(20)
              .backgroundColor(index === this.current
                ? ThemeService.alpha(this.theme.primary, 0.14) : this.theme.transparent)
              .onClick(() => { this.selectTab(index); })
            })
          }
          .width('100%').padding({ left: 8, right: 8, bottom: 8 })
          .backgroundColor(this.theme.barBg).backgroundBlurStyle(BlurStyle.Thin)
          .borderRadius({ topLeft: 22, topRight: 22 })
          .onTouch((e: TouchEvent) => { this.handleNavTouch(e); })
        }
        .width('100%').height('100%')
        .bindSheet(this.showBindAtStart, this.StartBindSheet(), {
          height: 420, backgroundColor: this.theme.bg,
          onDisappear: () => { this.showBindAtStart = false; }
        })
        if (this.rippleVisible) {
          Column().width(RIPPLE_DIAMETER).height(RIPPLE_DIAMETER)
            .borderRadius(RIPPLE_DIAMETER / 2)
            .position({ x: this.rippleX - RIPPLE_DIAMETER / 2, y: this.rippleY - RIPPLE_DIAMETER / 2 })
            .scale({ x: this.rippleRelease ? 1.7 : 1.0, y: this.rippleRelease ? 1.7 : 1.0 })
            .opacity(this.rippleRelease ? 0 : 1)
            .radialGradient({ center: [0.5, 0.5], radius: 0.5,
              colors: this.theme.isDark
                ? [['#80FFFFFF', 0.0], ['#00FFFFFF', 1.0]]
                : [['#26000000', 0.0], ['#00000000', 1.0]] })
            .zIndex(20).hitTestBehavior(HitTestMode.None)
        }
        if (this.showLoginOverlay) {
          LoginView({ onLoggedIn: () => { this.login(); }, onSkip: () => { this.showLoginOverlay = false; } })
        }
      }.width('100%').height('100%')
    }
  }
}
