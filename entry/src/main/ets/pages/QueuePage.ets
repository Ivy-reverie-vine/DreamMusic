import { ThemeService } from '../service/theme/ThemeService';
import { queueViewModel, QueueViewModel } from '../viewmodel/QueueViewModel';
import { Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { EmptyState } from '../components/EmptyState';
import { RADIUS_CARD, RADIUS_CAPSULE, FONT_BODY, FONT_LABEL, FONT_TITLE } from '../common/DesignTokens';
import { PlayMode } from '../service/playback/QueueEngine';

function modeLabel(mode: PlayMode): string {
  switch (mode) {
    case PlayMode.REPEAT_ONE:
      return '单曲循环';
    case PlayMode.REPEAT_ALL:
      return '列表循环';
    case PlayMode.SHUFFLE:
      return '随机';
    default:
      return '顺序';
  }
}

function modeIcon(mode: PlayMode): Resource {
  switch (mode) {
    case PlayMode.REPEAT_ONE:
      return $r('sys.symbol.repeat_1');
    case PlayMode.REPEAT_ALL:
      return $r('sys.symbol.repeat');
    case PlayMode.SHUFFLE:
      return $r('sys.symbol.shuffle');
    default:
      return $r('sys.symbol.play_circle');
  }
}

/** 播放队列页(issue-06 + issue-13 视觉):封面缩略图、阴影卡片、SymbolGlyph、模式软色胶囊 */
@Component
export struct QueuePage {
  @State theme: ThemeService = ThemeService.getInstance();
  @State vm: QueueViewModel = queueViewModel;
  /** 拖拽用本地镜像数组:拖拽中原地 splice 保证 List 强制重排,松手回写引擎 */
  @State localQueue: Track[] = [];
  /** 自定义拖拽(8/16 修复:内建 List 拖拽需长按 170ms,改为整行 PanGesture 即拖即动) */
  @State dragIndex: number = -1;
  @State dragStartIndex: number = -1;
  private readonly ROW_H: number = 70;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private ctxUri(t: Track): string {
    return t.coverPath !== '' ? 'file://' + this.ctx().filesDir + '/' + t.coverPath : '';
  }

  aboutToAppear(): void {
    this.localQueue = this.vm.queueTracks.slice();
  }

  private syncLocal(): void {
    this.localQueue = this.vm.queueTracks.slice();
  }

  /** 整行拖动:手指一动(约 6vp)即触发,实时把行让位,松手回写引擎 */
  private rowPanGesture(index: number) {
    return PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 6 })
      .onActionStart(() => {
        this.dragStartIndex = index;
        this.dragIndex = index;
      })
      .onActionUpdate((event: GestureEvent) => {
        if (this.dragIndex < 0) {
          return;
        }
        const desired = this.dragStartIndex + Math.round(event.offsetY / this.ROW_H);
        let cur = this.dragIndex;
        while (cur < desired && cur < this.localQueue.length - 1) {
          this.swapRows(cur, cur + 1);
          cur++;
        }
        while (cur > desired && cur > 0) {
          this.swapRows(cur, cur - 1);
          cur--;
        }
        this.dragIndex = cur;
      })
      .onActionEnd(() => {
        this.finishDrag();
      })
      .onActionCancel(() => {
        this.finishDrag();
      });
  }

  private swapRows(a: number, b: number): void {
    const moved = this.localQueue.splice(a, 1)[0];
    if (moved !== undefined) {
      this.localQueue.splice(b, 0, moved);
    }
  }

  private finishDrag(): void {
    if (this.dragIndex >= 0) {
      const ids: number[] = [];
      this.localQueue.forEach((t: Track) => {
        ids.push(t.id);
      });
      this.vm.reorder(ids);
    }
    this.dragIndex = -1;
    this.dragStartIndex = -1;
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('播放队列')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .layoutWeight(1)
        Row({ space: 6 }) {
          SymbolGlyph(modeIcon(this.vm.mode))
            .fontSize(14)
            .fontColor([this.theme.primaryText])
          Text(modeLabel(this.vm.mode))
            .fontSize(13)
            .fontColor(this.theme.primaryText)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(RADIUS_CAPSULE)
        .backgroundColor(ThemeService.alpha(this.theme.primary, 0.12))
        .stateStyles({
          pressed: { .opacity(0.6) }
        })
        .onClick(() => {
          this.vm.cycleMode();
        })
      }
      .width('100%')

      if (this.vm.queueTracks.length === 0) {
        EmptyState({
          symbol: $r('sys.symbol.list_bullet'),
          title: '队列是空的',
          hint: '去音乐库点歌,或按播放键从断点续播'
        })
      } else {
        Text('按住歌曲上下拖动调整顺序')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
        List({ space: 10 }) {
          ForEach(this.localQueue, (t: Track, index: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  CoverThumb({ uri: this.ctxUri(t), thumbSize: 40 })
                  Column({ space: 3 }) {
                    Text(t.title !== '' ? t.title : t.path)
                      .fontSize(FONT_BODY)
                      .fontWeight(t.id === this.vm.currentId ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(t.id === this.vm.currentId ? this.theme.primary : this.theme.ink)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(t.artist)
                      .fontSize(FONT_LABEL)
                      .fontColor(this.theme.muted)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(16)
                    .fontColor([this.theme.muted])
                    .padding(5)
                    .onClick(() => {
                      this.vm.removeAt(index);
                      this.syncLocal();
                    })
                  SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                    .fontSize(18)
                    .fontColor([this.theme.muted])
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(RADIUS_CARD)
                .backgroundColor(this.theme.card)
                .border({
                  width: t.id === this.vm.currentId ? 1 : 0,
                  color: ThemeService.alpha(this.theme.primary, 0.5)
                })
                .stateStyles({
                  pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
                })
                .gesture(this.rowPanGesture(index))
              }
            },
            // 稳定键:拖拽重排时 ForEach 按 id 识别元素,避免按索引重建导致拖拽错位
            (t: Track) => t.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

}
