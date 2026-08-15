import { ThemeService } from '../service/theme/ThemeService';

/** 播放队列页(拖拽排序在 issue-06) */
@Component
export struct QueuePage {
  @Prop theme: ThemeService;

  build() {
    Column({ space: 16 }) {
      Text('播放队列')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
        .width('100%')
      Column({ space: 8 }) {
        Text('队列是空的')
          .fontSize(18)
          .fontColor(this.theme.ink)
        Text('点歌后这里会出现播放顺序,之后可拖拽调整')
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
