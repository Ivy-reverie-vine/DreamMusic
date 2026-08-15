import { ThemeService } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { BubblePauseButton } from '../components/BubblePauseButton';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { lyricsViewModel, LyricsViewModel } from '../viewmodel/LyricsViewModel';
import { PlayerState } from '../model/Playback';
import { Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import {
  FONT_DISPLAY, FONT_LABEL, FONT_BODY, FONT_CAPTION, MOTION_VINYL_MS, MOTION_THEME_FADE_MS, SHADOW_GLOW_RADIUS
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
  @Prop theme: ThemeService;
  @State vm: PlayerViewModel = playerViewModel;
  @State lrc: LyricsViewModel = lyricsViewModel;
  /** 黑胶翻开动画相位:false=合上(初始帧),true=展开 */
  @State flip: boolean = false;

  aboutToAppear(): void {
    this.lrc.setContext(this.ctx());
    // 封面取色(issue-00/PRD story46):切歌 → 从封面提取主题色,500ms 渐变
    playerViewModel.coverColorHandler = (t: Track): void => {
      this.applyCoverColors(t);
    };
    // 切歌/进入页 → 黑胶翻开(温和版)
    if (this.vm.currentTrack !== null) {
      this.flipCover();
    }
  }

  private reduceMotion(): boolean {
    try {
      return accessibility.isAnimationReduceEnabledSync();
    } catch (err) {
      return false;
    }
  }

  private async applyCoverColors(t: Track): Promise<void> {
    if (t.coverPath === '') {
      return;
    }
    try {
      const abs = this.ctx().filesDir + '/' + t.coverPath;
      const colors = await BackgroundAdapter.extractFromFile(abs);
      if (this.reduceMotion()) {
        this.theme.applyExtracted(colors.primary, colors.secondary);
      } else {
        animateTo({ duration: MOTION_THEME_FADE_MS, curve: Curve.EaseOut }, () => {
          this.theme.applyExtracted(colors.primary, colors.secondary);
        });
      }
    } catch (err) {
      // 封面取色失败静默,保持当前主题
    }
    this.flipCover();
  }

  /** 黑胶翻开:先合上(即时),再 550ms 展开(scale+微倾+淡入);减弱动效 → 即显 */
  private flipCover(): void {
    if (this.reduceMotion()) {
      this.flip = true;
      return;
    }
    this.flip = false;
    setTimeout(() => {
      animateTo({ duration: MOTION_VINYL_MS, curve: Curve.EaseOut }, () => {
        this.flip = true;
      });
    }, 40);
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private coverUri(): string {
    const t = this.vm.currentTrack;
    if (t === null || t.coverPath === '') {
      return '';
    }
    return 'file://' + this.ctx().filesDir + '/' + t.coverPath;
  }

  @Builder
  VinylDisc() {
    Stack() {
      // 盘体:近黑圆盘 + 同心纹(克制的光泽)
      Circle()
        .width(236)
        .height(236)
        .fill('#14171B')
      Circle()
        .width(236)
        .height(236)
        .fill(this.theme.transparent)
        .stroke(ThemeService.alpha('#FFFFFF', 0.07))
        .strokeWidth(1)
      Circle()
        .width(208)
        .height(208)
        .fill(this.theme.transparent)
        .stroke(ThemeService.alpha('#FFFFFF', 0.05))
        .strokeWidth(1)
      Circle()
        .width(180)
        .height(180)
        .fill(this.theme.transparent)
        .stroke(ThemeService.alpha('#FFFFFF', 0.04))
        .strokeWidth(1)

      // 盘芯标签 = 封面(圆);无封面 → 主色渐变 + 音乐符号
      if (this.coverUri() !== '') {
        Image(this.coverUri())
          .width(172)
          .height(172)
          .borderRadius(86)
          .objectFit(ImageFit.Cover)
      } else {
        Circle()
          .width(172)
          .height(172)
          .fill(ThemeService.alpha(this.theme.primary, 0.75))
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(52)
          .fontColor([ThemeService.alpha(this.theme.ink, 0.9)])
      }

      // 轴孔
      Circle()
        .width(12)
        .height(12)
        .fill('#0B0D0E')
        .stroke(ThemeService.alpha('#FFFFFF', 0.35))
        .strokeWidth(1)
    }
    .width(236)
    .height(236)
    // 黑胶翻开过渡(温和版):轻微 scale + rotateY 微倾 + 淡入
    .scale({ x: this.flip ? 1.0 : 0.92, y: this.flip ? 1.0 : 0.92 })
    .rotate({ x: 0, y: 1, z: 0, angle: this.flip ? 0 : 8 })
    .opacity(this.flip ? 1 : 0.55)
    .shadow({ radius: SHADOW_GLOW_RADIUS, color: ThemeService.alpha(this.theme.primary, 0.4), offsetX: 0, offsetY: 0 })
  }

  @Builder
  LyricWindow() {
    Column({ space: 6 }) {
      if (this.lrc.lines.length > 0) {
        // 当前行 + 前后各一行;无歌词时整个区域隐藏
        Text(this.lrc.activeIndex > 0 ? this.lrc.lines[this.lrc.activeIndex - 1].text : '')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.lrc.activeIndex >= 0 ? this.lrc.lines[this.lrc.activeIndex].text : '')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.primaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.lrc.activeIndex >= 0 && this.lrc.activeIndex + 1 < this.lrc.lines.length
          ? this.lrc.lines[this.lrc.activeIndex + 1].text : '')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(96)
    .justifyContent(FlexAlign.Center)
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
          colors: [[ThemeService.alpha(this.theme.primary, 0.16), 0.0], ['#00000000', 1.0]]
        })

      Column({ space: 18 }) {
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
          this.VinylDisc()

          Column({ space: 6 }) {
            Text(this.vm.currentTrack.title !== '' ? this.vm.currentTrack.title : this.vm.currentTrack.path)
              .fontSize(FONT_DISPLAY)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.ink)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.vm.currentTrack.artist}${this.vm.currentTrack.album !== '' ? ' · ' + this.vm.currentTrack.album : ''}`)
              .fontSize(FONT_BODY)
              .fontColor(this.theme.muted)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')

          // 歌词窗口(无歌词自动隐藏)
          this.LyricWindow()

          // 进度:胶囊灯带
          Row({ space: 8 }) {
            Text(fmt(this.vm.positionMs))
              .fontSize(FONT_CAPTION)
              .fontColor(this.theme.muted)
            Slider({
              value: this.vm.positionMs,
              min: 0,
              max: this.vm.durationMs > 0 ? this.vm.durationMs : 1
            })
              .layoutWeight(1)
              .trackThickness(5)
              .selectedColor(this.theme.primary)
              .trackColor(this.theme.trackColor)
              .onChange((value: number) => {
                this.vm.seekTo(value);
              })
            Text(fmt(this.vm.durationMs))
              .fontSize(FONT_CAPTION)
              .fontColor(this.theme.muted)
          }
          .width('88%')

          // 音量
          Row({ space: 8 }) {
            SymbolGlyph(this.vm.volume <= 0.01 ? $r('sys.symbol.speaker_slash') : $r('sys.symbol.speaker_fill'))
              .fontSize(16)
              .fontColor([this.theme.muted])
            Slider({ value: this.vm.volume, min: 0, max: 1, step: 0.01 })
              .layoutWeight(1)
              .trackThickness(5)
              .selectedColor(this.theme.secondary)
              .trackColor(this.theme.trackColor)
              .onChange((value: number) => {
                this.vm.setVolume(value);
              })
          }
          .width('70%')

          Row({ space: 40 }) {
            SymbolGlyph($r('sys.symbol.backward_end_fill'))
              .fontSize(30)
              .fontColor([this.theme.muted])
              .onClick(() => {
                queueViewModel.playPrev();
              })
            BubblePauseButton({
              theme: this.theme,
              isPlaying: this.vm.state === PlayerState.PLAYING,
              onToggle: (): void => {
                this.vm.togglePause();
              }
            })
            SymbolGlyph($r('sys.symbol.forward_end_fill'))
              .fontSize(30)
              .fontColor([this.theme.muted])
              .onClick(() => {
                queueViewModel.playNext();
              })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')

          if (this.vm.errorText !== '') {
            Text(this.vm.errorText)
              .fontSize(FONT_LABEL)
              .fontColor(this.theme.secondary)
          }
        }
      }
      .padding(20)
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
