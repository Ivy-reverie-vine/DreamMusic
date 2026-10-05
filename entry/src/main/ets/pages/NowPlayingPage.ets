import { ThemeService } from '../service/theme/ThemeService';
import { CoverArtService } from '../service/cover/CoverArtService';
import { CoverThumb } from '../components/CoverThumb';
import { BubblePauseButton } from '../components/BubblePauseButton';
import { PlaybackStatus } from '../components/PlaybackStatus';
import { SourceSelection } from '../components/SourceSelection';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { playbackControlGate, PlaybackControlGate } from '../viewmodel/PlaybackControlGate';
import { lyricsViewModel, LyricsViewModel, LyricsLoadState } from '../viewmodel/LyricsViewModel';
import { PlayerState } from '../model/Playback';
import { Track } from '../model/Entities';
import { LyricLine, findActiveLine } from '../service/lyrics/LrcParser';
import { LyricFollowState } from '../service/lyrics/LyricFollowState';
import { common } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import {
  FONT_DISPLAY, FONT_LABEL, FONT_BODY, FONT_CAPTION, MOTION_VINYL_MS, SHADOW_GLOW_RADIUS,
  CONTROL_HIT_SIZE
} from '../common/DesignTokens';

function fmt(ms: number): string {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ':' + (s < 10 ? '0' + s : s.toString());
}

/**
 * 正在播放页(issue-05/08 + issue-12 视觉):
 * 黑胶盘芯造型(盘体/同心纹/轴孔)+ 切歌"翻开"过渡(温和版,减弱动效降级淡入);
 * 背景弥散光影(封面主色径向渐变);控制按钮全部 SymbolGlyph;进度为胶囊灯带。
 */
@Component
export struct NowPlayingPage {
  onGoLibrary: () => void = () => {};
  onGoSettings: () => void = () => {};
  @State theme: ThemeService = ThemeService.getInstance();
  @State @Watch('onPlaybackChanged') vm: PlayerViewModel = playerViewModel;
  @State controls: PlaybackControlGate = playbackControlGate;
  @State lrc: LyricsViewModel = lyricsViewModel;
  /** 黑胶翻开动画相位:false=合上(初始帧),true=展开 */
  @State flip: boolean = false;
  /** 歌词滚动控制器 + 自动跟随(用户手动滑动时暂停跟随) */
  private lrcScroller: Scroller = new Scroller();
  private lyricFollow: LyricFollowState = new LyricFollowState();
  private followTimer: number = -1;
  private followResetTimer: number = -1;
  private flipTimer: number = -1;
  private visible: boolean = false;
  private displayedTrack: Track | null = null;
  @State contentWidth: number = 320;
  @State contentHeight: number = 400;

  aboutToAppear(): void {
    this.visible = true;
    this.lrc.setContext(this.ctx());
    this.displayedTrack = this.vm.currentTrack;
    // 切歌/进入页 → 黑胶翻开(温和版)
    if (this.vm.currentTrack !== null) {
      this.flipCover();
    }
    this.startLyricFollow();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.stopLyricFollow();
    if (this.flipTimer >= 0) {
      clearTimeout(this.flipTimer);
      this.flipTimer = -1;
    }
  }

  /** 当前高亮行:直接由播放进度实时计算(不依赖间接状态,保证逐句切换) */
  private activeLineIndex(): number {
    return findActiveLine(this.lrc.lines, this.vm.positionMs);
  }

  private startLyricFollow(): void {
    this.stopLyricFollow();
    this.lyricFollow.reset(this.lrc.revision);
    this.followTimer = setInterval(() => {
      this.followActiveLine();
    }, 800);
  }

  private followActiveLine(): void {
    if (this.lrc.lines.length === 0) {
      return;
    }
    const index = this.lyricFollow.nextIndex(this.activeLineIndex(), this.lrc.revision);
    if (index !== null) {
      if (this.followResetTimer >= 0) {
        clearTimeout(this.followResetTimer);
        this.followResetTimer = -1;
      }
      this.lrcScroller.scrollToIndex(index, !this.reduceMotion(), ScrollAlign.CENTER);
    }
  }

  private pauseLyricFollow(): void {
    this.lyricFollow.pause(this.lrc.revision);
    if (this.followResetTimer >= 0) {
      clearTimeout(this.followResetTimer);
      this.followResetTimer = -1;
    }
  }

  /** 手指离开/惯性滚动结束后 2.5 秒恢复，不在持续拖动时抢回位置。 */
  private scheduleLyricFollow(): void {
    if (!this.lyricFollow.paused) {
      return;
    }
    if (this.followResetTimer >= 0) {
      clearTimeout(this.followResetTimer);
    }
    this.followResetTimer = setTimeout(() => {
      this.followResetTimer = -1;
      this.lyricFollow.resume();
      this.followActiveLine();
    }, 2500);
  }

  private discSize(): number {
    return Math.max(64, Math.min(236, this.contentWidth - 40, this.contentHeight * 0.4));
  }

  private lyricHeight(): number {
    return Math.max(96, Math.min(280, this.contentHeight * 0.36));
  }

  private stopLyricFollow(): void {
    if (this.followTimer >= 0) {
      clearInterval(this.followTimer);
      this.followTimer = -1;
    }
    if (this.followResetTimer >= 0) {
      clearTimeout(this.followResetTimer);
      this.followResetTimer = -1;
    }
  }

  private reduceMotion(): boolean {
    try {
      return accessibility.isAnimationReduceEnabledSync();
    } catch (err) {
      return false;
    }
  }

  private onPlaybackChanged(): void {
    if (this.visible && this.vm.currentTrack !== this.displayedTrack) {
      this.displayedTrack = this.vm.currentTrack;
      this.flipCover();
    }
  }

  /** 黑胶翻开:先合上(即时),再 550ms 展开(scale+微倾+淡入);减弱动效 → 即显 */
  private flipCover(): void {
    if (this.flipTimer >= 0) {
      clearTimeout(this.flipTimer);
      this.flipTimer = -1;
    }
    if (this.reduceMotion()) {
      this.flip = true;
      return;
    }
    this.flip = false;
    this.flipTimer = setTimeout(() => {
      this.flipTimer = -1;
      animateTo({ duration: MOTION_VINYL_MS, curve: Curve.EaseOut }, () => {
        this.flip = true;
      });
    }, 40);
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private coverUri(): string {
    return CoverArtService.resolve(this.ctx(), this.vm.currentTrack);
  }

  @Builder
  VinylDisc() {
    Stack() {
      // 盘体:近黑圆盘 + 同心纹(克制的光泽)
      Circle()
        .width(this.discSize())
        .height(this.discSize())
        .fill('#14171B')
      Circle()
        .width(this.discSize())
        .height(this.discSize())
        .fill(this.theme.transparent)
        .stroke(ThemeService.alpha('#FFFFFF', 0.07))
        .strokeWidth(1)
      Circle()
        .width(this.discSize() * 208 / 236)
        .height(this.discSize() * 208 / 236)
        .fill(this.theme.transparent)
        .stroke(ThemeService.alpha('#FFFFFF', 0.05))
        .strokeWidth(1)
      Circle()
        .width(this.discSize() * 180 / 236)
        .height(this.discSize() * 180 / 236)
        .fill(this.theme.transparent)
        .stroke(ThemeService.alpha('#FFFFFF', 0.04))
        .strokeWidth(1)

      // 盘芯标签 = 封面(圆);无封面 → 主色渐变 + 音乐符号
      CoverThumb({ uri: this.coverUri(), identity: CoverArtService.identity(this.vm.currentTrack),
        thumbSize: this.discSize() * 172 / 236,
        decodeSize: 512, circular: true, withShadow: false })

      // 轴孔
      Circle()
        .width(this.discSize() * 12 / 236)
        .height(this.discSize() * 12 / 236)
        .fill('#0B0D0E')
        .stroke(ThemeService.alpha('#FFFFFF', 0.35))
        .strokeWidth(1)
    }
    .width(this.discSize())
    .height(this.discSize())
    // 黑胶翻开过渡(温和版):轻微 scale + rotateY 微倾 + 淡入
    .scale({ x: this.flip ? 1.0 : 0.92, y: this.flip ? 1.0 : 0.92 })
    .rotate({ x: 0, y: 1, z: 0, angle: this.flip ? 0 : 8 })
    .opacity(this.flip ? 1 : 0.55)
    .shadow({ radius: SHADOW_GLOW_RADIUS, color: ThemeService.alpha(this.theme.primary, 0.4), offsetX: 0, offsetY: 0 })
  }

  @Builder
  LyricWindow() {
    // 可滑动歌词列表:当前行实时高亮(按播放进度计算),自动跟随滚动;手动滑动时暂停跟随
    if (this.lrc.lines.length === 0) {
      Text(this.lrc.loadState === LyricsLoadState.LOADING ? '歌词加载中…' :
        this.lrc.loadState === LyricsLoadState.ERROR ? '歌词暂时无法加载' : '这首歌暂无歌词')
        .fontSize(FONT_LABEL)
        .fontColor(this.theme.muted)
        .width('100%')
        .textAlign(TextAlign.Center)
    } else {
      List({ space: 4, scroller: this.lrcScroller }) {
        ForEach(this.lrc.lines, (line: LyricLine, index: number) => {
          ListItem() {
            Text(line.text)
              .fontSize(index === this.activeLineIndex() ? 17 : 14)
              .fontWeight(index === this.activeLineIndex() ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(index === this.activeLineIndex() ? this.theme.primaryText : this.theme.muted)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 5, bottom: 5 })
          }
        }, (line: LyricLine) => String(line.timeMs) + '_' + line.text)
      }
      .width('100%')
      .height(this.lyricHeight())
      .scrollBar(BarState.Off)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .onAppear(() => {
        this.lyricFollow.reset(this.lrc.revision);
      })
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down || e.type === TouchType.Move) {
          this.pauseLyricFollow();
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.scheduleLyricFollow();
        }
      })
      .onDidScroll(() => {
        if (this.lyricFollow.paused) {
          this.pauseLyricFollow();
        }
      })
      .onScrollStop(() => {
        this.scheduleLyricFollow();
      })
    }
  }

  build() {
    Stack() {
      // 弥散光影:封面主色径向渐变(蒙层之上,展品灯光感;scrimNowPlaying 由主壳按页切换)
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [0.5, 0.32],
          radius: 0.9,
          colors: [[ThemeService.alpha(this.theme.primary, this.theme.coverGlowAlpha), 0.0], ['#00000000', 1.0]]
        })

      Column({ space: 8 }) {
        if (this.vm.currentTrack === null) {
          Column({ space: 8 }) {
            Text('还没有在播放')
              .fontSize(18)
              .fontColor(this.theme.ink)
            Text('去音乐库点一首歌')
              .fontSize(14)
              .fontColor(this.theme.muted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 元数据自然换行；大字体/长文本超出时只滚动内容，播控始终可达。
          Scroll() {
            Column({ space: 16 }) {
              this.VinylDisc()

              Column({ space: 6 }) {
                Text(this.vm.currentTrack.title !== '' ? this.vm.currentTrack.title : this.vm.currentTrack.path)
                  .fontSize(FONT_DISPLAY)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.ink)
                  .width('100%')
                  .wordBreak(WordBreak.BREAK_ALL)
                Text(`${this.vm.currentTrack.artist}${this.vm.currentTrack.album !== '' ? ' · ' + this.vm.currentTrack.album : ''}`)
                  .fontSize(FONT_BODY)
                  .fontColor(this.theme.muted)
                  .width('100%')
                  .wordBreak(WordBreak.BREAK_ALL)
                if (this.vm.playbackSourceText !== '') {
                  Text('音频来源：' + this.vm.playbackSourceText)
                    .fontSize(FONT_BODY)
                    .fontColor(this.theme.muted)
                    .width('100%')
                }
              }
              .width('100%')
              .padding(8)
              .borderRadius(12)
              .backgroundColor(ThemeService.alpha(this.theme.bg, 0.95))

              // 局部承托隔离封面阴影，避免其在文字背后突破全局背景范围。
              SourceSelection()

              Column() {
                this.LyricWindow()
              }
              .width('100%')
              .padding(8)
              .borderRadius(12)
              .backgroundColor(ThemeService.alpha(this.theme.bg, 0.95))


            }
            .padding({ top: 12, bottom: 12 })
            .width('100%')
            .constraintSize({ minHeight: this.contentHeight })
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .onAreaChange((_oldArea: Area, area: Area) => {
            this.contentWidth = Number(area.width);
            this.contentHeight = Number(area.height);
          })

          // 时间码放在进度条下方，字体放大不会挤掉可拖动的进度条。
          Column({ space: 4 }) {
            PlaybackStatus({ onGoLibrary: this.onGoLibrary, onGoSettings: this.onGoSettings })
            Slider({
              value: this.vm.positionMs,
              min: 0,
              max: this.vm.durationMs > 0 ? this.vm.durationMs : 1
            })
              .width('100%')
              .height(40)
              .trackThickness(5)
              .selectedColor(this.theme.primary)
              .trackColor(this.theme.trackColor)
              .accessibilityText('播放进度')
              .enabled(this.vm.state === PlayerState.PLAYING || this.vm.state === PlayerState.PAUSED)
              .onChange((value: number) => {
                this.vm.seekTo(value);
              })
            Row() {
              Text(fmt(this.vm.positionMs))
                .fontSize(FONT_CAPTION)
                .fontColor(this.theme.muted)
              Text(fmt(this.vm.durationMs))
                .fontSize(FONT_CAPTION)
                .fontColor(this.theme.muted)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .backgroundColor(ThemeService.alpha(this.theme.bg, 0.95))

            Row({ space: Math.max(8, Math.min(40, (this.contentWidth - 168) / 2)) }) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.backward_end_fill'))
                  .fontSize('30vp')
                  .fontColor([this.theme.muted])
              }
              .width(CONTROL_HIT_SIZE)
              .height(CONTROL_HIT_SIZE)
              .backgroundColor(this.theme.transparent)
              .enabled(!this.controls.busy)
              .accessibilityText('上一首')
              .onClick(() => {
                this.controls.run(() => queueViewModel.playPrev());
              })
              BubblePauseButton({
                isPlaying: this.vm.state === PlayerState.PLAYING,
                loading: this.vm.state === PlayerState.PREPARING,
                onToggle: (): void => {
                  this.controls.run(() => this.vm.togglePause());
                }
              })
                .enabled(!this.controls.busy && this.vm.state !== PlayerState.PREPARING && this.vm.state !== PlayerState.ERROR)
                .accessibilityText(this.vm.state === PlayerState.PREPARING ? '正在加载音乐' :
                  (this.vm.state === PlayerState.PLAYING ? '暂停' : '播放'))
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.forward_end_fill'))
                  .fontSize('30vp')
                  .fontColor([this.theme.muted])
              }
              .width(CONTROL_HIT_SIZE)
              .height(CONTROL_HIT_SIZE)
              .backgroundColor(this.theme.transparent)
              .enabled(!this.controls.busy)
              .accessibilityText('下一首')
              .onClick(() => {
                this.controls.run(() => queueViewModel.playNext());
              })
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
          }
          .width('100%')
        }
      }
      .padding({ left: 20, right: 20, top: 8, bottom: 8 })
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
