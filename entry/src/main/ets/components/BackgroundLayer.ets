import { ThemeService } from '../service/theme/ThemeService';

/**
 * 全局背景层(阶段 v2.2):近黑底 + 背景图(预设/自定义)+ 蒙层保底。
 * 主界面与登录/注册页共用,保证"背景图跟主界面保持一致"。
 */
@Component
export struct BackgroundLayer {
  @State theme: ThemeService = ThemeService.getInstance();
  /** 蒙层强度与 TextContrast 的最终背景范围共用常量。 */
  @Prop nowPlaying: boolean = false;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.bg)

      // 背景图(内置预设或自定义):奇偶双分支强制重建,切换即时生效(issue-14 定稿)
      if (this.theme.bgSrc !== null) {
        if (this.theme.bgStamp % 2 === 0) {
          Image(this.theme.bgSrc)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Image(this.theme.bgSrc)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.theme.isDark ? '#000000' : '#FFFFFF')
          .opacity(this.nowPlaying ? this.theme.scrimNowPlaying : this.theme.scrimList)
      }
    }
    .width('100%')
    .height('100%')
  }
}
