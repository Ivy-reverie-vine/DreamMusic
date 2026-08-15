import { ThemeService } from '../service/theme/ThemeService';
import { queueViewModel, QueueViewModel } from '../viewmodel/QueueViewModel';
import { Track } from '../model/Entities';

function modeLabel(mode: string): string {
  switch (mode) {
    case 'REPEAT_ONE':
      return '单曲循环';
    case 'REPEAT_ALL':
      return '列表循环';
    case 'SHUFFLE':
      return '随机';
    default:
      return '顺序';
  }
}

/** 播放队列页(issue-06):拖拽排序、移除、播放模式切换 */
@Component
export struct QueuePage {
  @Prop theme: ThemeService;
  @State vm: QueueViewModel = queueViewModel;

  @Builder
  dragIcon() {
    Text('≡')
      .fontSize(18)
      .fontColor(this.theme.muted)
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('播放队列')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
        Text(modeLabel(this.vm.mode))
          .fontSize(13)
          .fontColor(this.theme.ink)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.theme.primary)
          .onClick(() => {
            this.vm.cycleMode();
          })
      }
      .width('100%')

      if (this.vm.queueTracks.length === 0) {
        Column({ space: 8 }) {
          Text('队列是空的')
            .fontSize(18)
            .fontColor(this.theme.ink)
          Text('去音乐库点歌,或按 ▶ 从断点续播')
            .fontSize(14)
            .fontColor(this.theme.muted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.vm.queueTracks, (t: Track, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(t.title !== '' ? t.title : t.path)
                    .fontSize(16)
                    .fontColor(index === this.vm.currentIndexId() ? this.theme.primary : this.theme.ink)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(t.artist)
                    .fontSize(12)
                    .fontColor(this.theme.muted)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('✕')
                  .fontSize(15)
                  .fontColor(this.theme.muted)
                  .padding(6)
                  .onClick(() => {
                    this.vm.removeAt(index);
                  })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(14)
              .backgroundColor(this.theme.bg)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .onItemDragStart((_event: ItemDragInfo, _itemIndex: number): CustomBuilder => {
          return this.dragIcon();
        })
        .onItemMove((from: number, to: number): boolean => {
          this.vm.move(from, to);
          return true;
        })
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }
}
