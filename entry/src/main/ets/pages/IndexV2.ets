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
import { playbackStatsViewModel } from '../viewmodel/PlaybackStatsViewModel';
import {
  BackAction, MySubpage, RootTab, NavigationState, openMyPage, resolveBack, selectRoot
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
    const ctx = this.ctx();
    lyricsViewModel.setContext(ctx);
    playerViewModel.coverColorHandler = (t) => {
      BackgroundAdapter.applyCoverColors(ctx, this.theme, t);
    };
    queueViewModel.restore(ctx);
    this.checkGate();
  }

  private async checkGate(): Promise<void> {
    const ctx = this.ctx();
    await DreamMusicAuth.initialize(ctx);
    if (!DreamMusicAuth.isLoggedIn(ctx)) {
      this.booting = false;
      this.loggedIn = false;
      this.loginPromptVisible = true;
      return;
    }
    try {
      const user = await DreamMusicAuth.me(ctx);
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
      if (err instanceof ApiError && err.code === 'UNAUTHORIZED') {
        await DreamMusicAuth.logout(ctx);
        OnlineMusicService.clearCache(ctx);
        this.loggedIn = false;
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
    const next = selectRoot(this.navigation(), index as RootTab);
    this.current = next.root;
    this.myPage = next.myPage;
    this.sourceRoot = next.sourceRoot;
  }

  @Builder
  PageContent() {
    if (this.current === RootTab.LIBRARY) {
      MusicLibraryPage({
        onGoSettings: () => { this.openMyPage(MySubpage.SETTINGS, RootTab.LIBRARY); },
        onGoLogin: () => { this.showLoginOverlay = true; }
      })
    } else if (this.current === RootTab.NOW_PLAYING) {
      NowPlayingPage()
    } else if (this.current === RootTab.QUEUE) {
      QueuePage()
    } else {
      MyPageV2({
        page: this.myPage,
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
          playing: this.player.state === PlayerState.PLAYING,
          onOpen: (): void => { this.selectTab(RootTab.NOW_PLAYING); },
          onToggle: (): void => { this.player.togglePause(); },
          onNext: (): void => { queueViewModel.playNext(); }
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
              .layoutWeight(1).padding({ top: 10, bottom: 10 }).borderRadius(20)
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
            .zIndex(20)
        }
        if (this.showLoginOverlay) {
          LoginView({ onLoggedIn: () => { this.login(); }, onSkip: () => { this.showLoginOverlay = false; } })
        }
      }.width('100%').height('100%')
    }
  }
}
