import { ThemeService } from '../service/theme/ThemeService';

/**
 * 不规则椭圆泡泡暂停/播放按钮(IDEA.md、DESIGN.md Shapes)。
 * 形状:水平略长的椭圆泡泡,非方正矩形;颜色取自主题服务。
 */
@Component
export struct BubblePauseButton {
  @Prop theme: ThemeService;
  @Prop isPlaying: boolean;
  onToggle: () => void = () => {
  };

  build() {
    Stack() {
      // 泡泡本体:不规则椭圆(两轴半径不同,略倾斜营造"泡泡"感)
      Shape() {
        Path()
          .commands('M0 30 Q0 8 26 4 Q58 0 74 14 Q92 30 76 46 Q58 62 30 58 Q6 54 0 30 Z')
          .fill(this.theme.primary)
          .stroke(this.theme.ink)
          .strokeWidth(2)
      }
      .width(96)
      .height(64)
      .rotate({ angle: -6 })

      Text(this.isPlaying ? '❚❚' : '▶')
        .fontSize(22)
        .fontColor(this.theme.ink)
        .fontWeight(FontWeight.Bold)
    }
    .width(96)
    .height(64)
    .onClick(() => {
      this.onToggle();
    })
  }
}
