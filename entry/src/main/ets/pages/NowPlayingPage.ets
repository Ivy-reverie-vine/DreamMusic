import { ThemeService } from '../service/theme/ThemeService';
import { BubblePauseButton } from '../components/BubblePauseButton';

/** 正在播放页(占位,issue-05 填充;封面焦点与黑胶动效在 issue-00 组件库完善) */
@Component
export struct NowPlayingPage {
  @Prop theme: ThemeService;
  @State isPlaying: boolean = false;

  build() {
    Column({ space: 20 }) {
      // 封面占位:圆形,主色光晕
      Circle()
        .width(200)
        .height(200)
        .fill(this.theme.primary)
        .opacity(0.85)
        .shadow({ radius: 60, color: this.theme.primary, offsetX: 0, offsetY: 0 })

      Column({ space: 6 }) {
        Text('曲名占位')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.ink)
        Text('艺术家 · 专辑')
          .fontSize(15)
          .fontColor(this.theme.muted)
      }

      // 进度条占位
      Row() {
        Text('0:00')
          .fontSize(12)
          .fontColor(this.theme.muted)
        Blank()
        Text('--:--')
          .fontSize(12)
          .fontColor(this.theme.muted)
      }
      .width('80%')

      Row({ space: 32 }) {
        Text('⏮')
          .fontSize(26)
          .fontColor(this.theme.ink)
        BubblePauseButton({ theme: this.theme, isPlaying: this.isPlaying, onToggle: (): void => {
          this.isPlaying = !this.isPlaying;
        } })
        Text('⏭')
          .fontSize(26)
          .fontColor(this.theme.ink)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
