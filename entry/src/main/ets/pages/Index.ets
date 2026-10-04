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
import { MOTION_THEME_FADE_MS } from '../common/DesignTokens';

const RIPPLE_DIAMETER = 64;

interface NavTab {
  label: string;
  icon: Resource;
}

/**
 * 应用主壳:底部玻璃导航 + 五页切换(issue-01/12)。
 * issue-12:沉浸光感触点光晕(自绘,触点为中心径向渐变扩散淡出);
 * 导航图标换 SymbolGlyph;启动恢复前先接线歌词上下文与封面取色。
 */
@Entry
@Component
struct Index {
  @State theme: ThemeService = ThemeService.getInstance();
  @State current: number = 0;
  @State player: PlayerViewModel = playerViewModel;
  /** 登录门禁(阶段 v2.2):打开应用先弹登录页,可跳过;本地歌不登录可听,在线功能再提示登录 */
  @State booting: boolean = true;
  @State loggedIn: boolean = false;
  /** 启动时未登录 → 展示可跳过的登录页 */
  @State loginPromptVisible: boolean = false;
  /** 在线功能触发 → 主界面上盖登录页 */
  @State showLoginOverlay: boolean = false;
  /** 启动时已登录但未绑定/绑定失效 → 自动弹 QR 绑定 */
  @State showBindAtStart: boolean = false;
  // 触点光晕状态(issue-12 重做:按下常亮 → 随指移动 → 松手扩散淡出)
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

  aboutToAppear(): void {
    const ctx = this.ctx();
    // issue-12 修复:恢复前先接线,使启动恢复时歌词/封面取色立即生效
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
    // 断点续播恢复(issue-06):还原队列/当前曲/进度为暂停态
    queueViewModel.restore(ctx);
    this.checkGate();
  }

  /** 登录门禁:无会话 → 可跳过登录页;有会话 → 校验 /auth/me,失效清本地并回登录页 */
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
        // 会话失效 → 清本地回登录页
        await DreamMusicAuth.logout(ctx);
        OnlineMusicService.clearCache(ctx);
        this.loggedIn = false;
        this.loginPromptVisible = true;
      } else {
        // 中间层临时不可达:保留会话进入,功能侧会显示离线
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
      QrBindView({
        onBound: () => {
          this.showBindAtStart = false;
        }
      })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.theme.bg)
  }

  /** 底栏触摸:按下亮起白光圆(跟随手指),松手 260ms 扩散淡出(QQ音乐式沉浸光感) */
  private handleNavTouch(e: TouchEvent): void {
    if (e.touches.length === 0) {
      return;
    }
    const t = e.touches[0];
    // windowX/windowY 相对应用窗口左上;光晕节点在外层全屏 Stack 中,
    // position 坐标与窗口坐标一致,直接使用触点坐标(issue-14 修复:不再减 barY/clamp)
    const x = t.windowX;
    const y = t.windowY;
    if (e.type === TouchType.Down) {
      try {
        if (accessibility.isAnimationReduceEnabledSync()) {
          return;
        }
      } catch (err) {
        // 查询失败按默认处理(照常显示光晕)
      }
      this.rippleX = x;
      this.rippleY = y;
      this.rippleRelease = false;
      this.rippleVisible = true;
    } else if (e.type === TouchType.Move) {
      if (this.rippleVisible) {
        this.rippleX = x;
        this.rippleY = y;
      }
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      if (!this.rippleVisible) {
        return;
      }
      animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.rippleRelease = true;
      });
      if (this.rippleHideTimer >= 0) {
        clearTimeout(this.rippleHideTimer);
      }
      this.rippleHideTimer = setTimeout(() => {
        this.rippleVisible = false;
      }, 320);
    }
  }

  @Builder
  PageContent() {
    if (this.current === 0) {
      MusicLibraryPage({
        onGoSettings: () => {
          this.current = 3;
        },
        onGoLogin: () => {
          this.showLoginOverlay = true;
        }
      })
    } else if (this.current === 1) {
      NowPlayingPage()
    } else if (this.current === 2) {
      QueuePage()
    } else {
      MyPageV2()
    }
  }

  @Builder
  ResidentPlayerBar() {
    if (this.current !== 1 && this.player.currentTrack !== null) {
      Column() {
        MiniPlayerBar({
          track: this.player.currentTrack,
          playing: this.player.state === PlayerState.PLAYING,
          onOpen: (): void => {
            this.current = 1;
          },
          onToggle: (): Promise<void> => {
            return this.player.togglePause();
          },
          onNext: (): Promise<void> => {
            return queueViewModel.playNext();
          }
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
    }
  }

  /** 登录成功统一收口:关闭所有登录层 */
  private login(): void {
    this.loggedIn = true;
    this.loginPromptVisible = false;
    this.showLoginOverlay = false;
  }

  build() {
    if (this.booting) {
      Stack() {
        BackgroundLayer()
        Text('IvyReverie')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.ink)
      }
      .width('100%')
      .height('100%')
    } else if (!this.loggedIn && this.loginPromptVisible) {
      LoginView({
        onLoggedIn: () => {
          this.login();
        },
        onSkip: () => {
          this.loginPromptVisible = false;
        }
      })
    } else {
      Stack() {
        BackgroundLayer({ nowPlaying: this.current === 1 })

        Column() {
          Column() {
            this.PageContent()
          }
          .width('100%')
          .layoutWeight(1)

          this.ResidentPlayerBar()

          // 导航栏必须位于播放条之后的独立布局层，避免播放条的点击区域覆盖导航按钮。
          Row() {
            ForEach(this.tabs, (item: NavTab, index: number) => {
              Column({ space: 2 }) {
                SymbolGlyph(item.icon)
                  .fontSize(20)
                  .fontColor([index === this.current ? this.theme.primaryText : this.theme.muted])
                Text(item.label)
                  .fontSize(11)
                  .fontColor(index === this.current ? this.theme.primaryText : this.theme.muted)
                  .fontWeight(index === this.current ? FontWeight.Medium : FontWeight.Normal)
              }
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .borderRadius(20)
              .backgroundColor(index === this.current
                ? ThemeService.alpha(this.theme.primary, 0.14) : this.theme.transparent)
              .onClick(() => {
                this.current = index;
              })
            })
          }
          .width('100%')
          .padding({ left: 8, right: 8, bottom: 8 })
          .backgroundColor(this.theme.barBg)
          .backgroundBlurStyle(BlurStyle.Thin)
          .borderRadius({ topLeft: 22, topRight: 22 })
          .onTouch((e: TouchEvent) => {
            this.handleNavTouch(e);
          })
        }
        .width('100%')
        .height('100%')
        .bindSheet(this.showBindAtStart, this.StartBindSheet(), {
          height: 420,
          backgroundColor: this.theme.bg,
          onDisappear: () => {
            this.showBindAtStart = false;
          }
        })

        if (this.rippleVisible) {
          Column()
            .width(RIPPLE_DIAMETER)
            .height(RIPPLE_DIAMETER)
            .borderRadius(RIPPLE_DIAMETER / 2)
            .position({
              x: this.rippleX - RIPPLE_DIAMETER / 2,
              y: this.rippleY - RIPPLE_DIAMETER / 2
            })
            .scale({ x: this.rippleRelease ? 1.7 : 1.0, y: this.rippleRelease ? 1.7 : 1.0 })
            .opacity(this.rippleRelease ? 0 : 1)
            .radialGradient({
              center: [0.5, 0.5],
              radius: 0.5,
              colors: this.theme.isDark
                ? [['#80FFFFFF', 0.0], ['#00FFFFFF', 1.0]]
                : [['#26000000', 0.0], ['#00000000', 1.0]]
            })
            .zIndex(20)
        }

        // 在线功能触发的登录盖层(本地功能不受影响)
        if (this.showLoginOverlay) {
          LoginView({
            onLoggedIn: () => {
              this.login();
            },
            onSkip: () => {
              this.showLoginOverlay = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
  }
}
