import { ThemeService } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { playerViewModel } from '../viewmodel/PlayerViewModel';
import { lyricsViewModel } from '../viewmodel/LyricsViewModel';
import { common } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { MusicLibraryPage } from './MusicLibraryPage';
import { NowPlayingPage } from './NowPlayingPage';
import { QueuePage } from './QueuePage';
import { PlaylistsPage } from './PlaylistsPage';
import { SettingsPage } from './SettingsPage';

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
    { label: '歌单', icon: $r('sys.symbol.rectangle_stack') },
    { label: '设置', icon: $r('sys.symbol.gearshape') }
  ];

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    const ctx = this.ctx();
    // issue-12 修复:恢复前先接线,使启动恢复时歌词/封面取色立即生效
    lyricsViewModel.setContext(ctx);
    playerViewModel.coverColorHandler = (t) => {
      BackgroundAdapter.applyCoverColors(ctx, this.theme, t);
    };
    // 断点续播恢复(issue-06):还原队列/当前曲/进度为暂停态
    queueViewModel.restore(ctx);
    // 背景图重启恢复 + 全局铺满(issue-00 AC,真机验证)
    BackgroundAdapter.restoreIfPresent(ctx, this.theme);
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
      MusicLibraryPage({ theme: this.theme })
    } else if (this.current === 1) {
      NowPlayingPage({ theme: this.theme })
    } else if (this.current === 2) {
      QueuePage({ theme: this.theme })
    } else if (this.current === 3) {
      PlaylistsPage({ theme: this.theme })
    } else {
      SettingsPage({ theme: this.theme })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景:近黑底(有背景图后叠图+蒙层)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.bg)

      // 用户背景图:全局铺满 + 蒙层保底(DESIGN.md 蒙层保底规则)
      if (this.theme.hasBackground && this.theme.bgImagePath !== '') {
        Image('file://' + this.ctx().filesDir + '/' + this.theme.bgImagePath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.theme.isDark ? '#000000' : '#FFFFFF')
          .opacity(this.current === 1 ? this.theme.scrimNowPlaying : this.theme.scrimList)
      }

      Column() {
        this.PageContent()
      }
      .width('100%')
      .height('100%')

      // 触点光晕层(自绘沉浸光感:白色径向渐变圆,按着亮、松手扩散淡出;
      // 不用 Circle,避免默认黑色填充盖住渐变——issue-12 修复)
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
      }

      // 玻璃底栏:半透明模糊,内容透过可见(DESIGN.md 玻璃底栏规则 + 沉浸光感)
      Row() {
        ForEach(this.tabs, (item: NavTab, index: number) => {
          Column({ space: 2 }) {
            SymbolGlyph(item.icon)
              .fontSize(20)
              .fontColor([index === this.current ? this.theme.primary : this.theme.muted])
            Text(item.label)
              .fontSize(11)
              .fontColor(index === this.current ? this.theme.primary : this.theme.muted)
              .fontWeight(index === this.current ? FontWeight.Medium : FontWeight.Normal)
          }
          .layoutWeight(1)
          .padding({ top: 10, bottom: 10 })
          .borderRadius(20)
          .backgroundColor(index === this.current ? ThemeService.alpha(this.theme.primary, 0.14) : this.theme.transparent)
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
  }
}
