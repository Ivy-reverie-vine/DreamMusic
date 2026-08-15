import { ThemeService } from '../service/theme/ThemeService';

/**
 * 封面缩略图(issue-12):有封面显示圆角图,无封面显示主色渐变占位 + 音乐符号。
 * uri 为完整 file:// 路径;为空串视为无封面。
 */
@Component
export struct CoverThumb {
  @Prop theme: ThemeService;
  @Prop uri: string = '';
  @Prop thumbSize: number = 44;

  build() {
    Stack() {
      if (this.uri !== '') {
        Image(this.uri)
          .width(this.thumbSize)
          .height(this.thumbSize)
          .objectFit(ImageFit.Cover)
          .borderRadius(this.thumbSize * 0.25)
      } else {
        // 占位:primary→secondary 渐变 + 音乐符号(DESIGN.md 蒙层保底:只做强调)
        Column()
          .width(this.thumbSize)
          .height(this.thumbSize)
          .borderRadius(this.thumbSize * 0.25)
          .linearGradient({
            angle: 135,
            colors: [
              [ThemeService.alpha(this.theme.primary, 0.5), 0.0],
              [ThemeService.alpha(this.theme.secondary, 0.32), 1.0]
            ]
          })
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(this.thumbSize * 0.38)
          .fontColor([ThemeService.alpha(this.theme.ink, 0.85)])
      }
    }
    .width(this.thumbSize)
    .height(this.thumbSize)
    .shadow({ radius: 10, color: ThemeService.alpha('#000000', 0.28), offsetX: 0, offsetY: 4 })
  }
}
