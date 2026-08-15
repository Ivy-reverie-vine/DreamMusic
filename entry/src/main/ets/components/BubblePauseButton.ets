import { ThemeService } from '../service/theme/ThemeService';

/**
 * 不规则椭圆泡泡暂停/播放按钮(IDEA.md、DESIGN.md Shapes,issue-14 重做):
 * 椭圆 = borderRadius(高一半)实现,绕开 Path 坐标系渲染问题;
 * 渐变填充 + 顶部高光(液体玻璃感)+ primary 弥散光晕;符号用 SymbolGlyph。
 */
@Component
export struct BubblePauseButton {
  @Prop theme: ThemeService;
  @Prop isPlaying: boolean;
  onToggle: () => void = () => {
  };

  build() {
    Stack() {
      // 泡泡本体:水平略长的椭圆(有机感),渐变填充
      Column()
        .width(92)
        .height(60)
        .borderRadius(30)
        .linearGradient({
          angle: 160,
          colors: [
            [ThemeService.alpha(this.theme.primary, 1.0), 0.0],
            [ThemeService.alpha(this.theme.primary, 0.72), 1.0]
          ]
        })

      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(26)
        .fontColor([this.theme.ink])
        .offset({ x: this.isPlaying ? 0 : 2, y: 0 })
    }
    .width(96)
    .height(64)
    .rotate({ angle: -5 })
    .shadow({ radius: 28, color: ThemeService.alpha(this.theme.primary, 0.55), offsetX: 0, offsetY: 0 })
    .onClick(() => {
      this.onToggle();
    })
  }
}
