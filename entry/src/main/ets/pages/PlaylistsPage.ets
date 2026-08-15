import { ThemeService } from '../service/theme/ThemeService';

/** 歌单页(issue-09 填充) */
@Component
export struct PlaylistsPage {
  @Prop theme: ThemeService;

  build() {
    Column({ space: 16 }) {
      Text('歌单')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
        .width('100%')
      Column({ space: 8 }) {
        Text('还没有歌单')
          .fontSize(18)
          .fontColor(this.theme.ink)
        Text('收藏的歌会聚合进「我喜欢的音乐」')
          .fontSize(14)
          .fontColor(this.theme.muted)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }
}
