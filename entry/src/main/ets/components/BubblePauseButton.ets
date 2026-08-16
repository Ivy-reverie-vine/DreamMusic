import { ThemeService } from '../service/theme/ThemeService';

/**
 * 播放/暂停按钮(用户真机评审定稿:普通正圆按钮,固定灰色不随取色,issue-14):
 * 64dp 正圆 + controlGray 填充 + 克制光晕,符号用 SymbolGlyph。
 */
@Component
export struct BubblePauseButton {
  @State theme: ThemeService = ThemeService.getInstance();
  @Prop isPlaying: boolean;
  onToggle: () => void = () => {
  };

  build() {
    Stack() {
      Column()
        .width(64)
        .height(64)
        .borderRadius(32)
        .backgroundColor(this.theme.controlGray)

      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(28)
        .fontColor([this.theme.ink])
        .offset({ x: this.isPlaying ? 0 : 2, y: 0 })
    }
    .width(72)
    .height(72)
    .shadow({ radius: 24, color: ThemeService.alpha(this.theme.controlGray, 0.45), offsetX: 0, offsetY: 0 })
    .onClick(() => {
      this.onToggle();
    })
  }
}
