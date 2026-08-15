import { ThemeService } from '../service/theme/ThemeService';

/**
 * 不规则椭圆泡泡暂停/播放按钮(IDEA.md、DESIGN.md Shapes,issue-12 视觉升级):
 * 形状保持有机泡泡(两轴半径不同 + 微倾斜),填充主色 + 弥散光晕;
 * 符号用官方 SymbolGlyph(play_fill/pause_fill),不再用文本字形。
 */
@Component
export struct BubblePauseButton {
  @Prop theme: ThemeService;
  @Prop isPlaying: boolean;
  onToggle: () => void = () => {
  };

  build() {
    Stack() {
      // 泡泡本体:不规则椭圆(Path 曲线,微倾斜营造"泡泡"感)
      Shape() {
        Path()
          .commands('M0 30 Q0 8 26 4 Q58 0 74 14 Q92 30 76 46 Q58 62 30 58 Q6 54 0 30 Z')
          .fill(this.theme.primary)
          .stroke(ThemeService.alpha(this.theme.ink, 0.85))
          .strokeWidth(2)
      }
      .width(96)
      .height(64)
      .rotate({ angle: -6 })

      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(26)
        .fontColor([this.theme.ink])
        .offset({ x: this.isPlaying ? 0 : 2, y: 0 })
    }
    .width(96)
    .height(64)
    .shadow({ radius: 28, color: ThemeService.alpha(this.theme.primary, 0.55), offsetX: 0, offsetY: 0 })
    .onClick(() => {
      this.onToggle();
    })
  }
}
