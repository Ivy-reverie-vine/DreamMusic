import { ThemeService } from '../service/theme/ThemeService';

/**
 * 统一空状态(issue-12,issue-11 AC 的视觉落地):符号 + 标题 + 提示。
 * 各页空库/空歌单/空队列/无歌词共用,避免手写空状态。
 */
@Component
export struct EmptyState {
  @Prop theme: ThemeService;
  @Prop symbol: Resource = $r('sys.symbol.music_note_list');
  @Prop title: string = '这里还是空的';
  @Prop hint: string = '';

  build() {
    Column({ space: 10 }) {
      SymbolGlyph(this.symbol)
        .fontSize(44)
        .fontColor([ThemeService.alpha(this.theme.primary, 0.55)])
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(13)
          .fontColor(this.theme.muted)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 32, right: 32 })
  }
}
