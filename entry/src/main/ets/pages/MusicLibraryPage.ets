import { ThemeService } from '../service/theme/ThemeService';

/** 音乐库页(歌曲/专辑/艺术家三视图占位,issue-04 填充) */
@Component
export struct MusicLibraryPage {
  @Prop theme: ThemeService;
  @State tab: number = 0;

  build() {
    Column({ space: 16 }) {
      Text('音乐库')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(['歌曲', '专辑', '艺术家'], (item: string, index: number) => {
          Text(item)
            .fontSize(16)
            .fontColor(index === this.tab ? this.theme.primary : this.theme.muted)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(index === this.tab ? this.theme.bg : '#00000000')
            .onClick(() => {
              this.tab = index;
            })
        })
      }
      .width('100%')

      Column({ space: 8 }) {
        Text('音乐库还是空的')
          .fontSize(18)
          .fontColor(this.theme.ink)
        Text('去设置页导入你的音乐,或等待 issue-03 导入管线落地')
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
