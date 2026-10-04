import { ThemeService } from '../service/theme/ThemeService';
import { queueViewModel, QueueViewModel } from '../viewmodel/QueueViewModel';
import { Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { CoverArtService } from '../service/cover/CoverArtService';
import { EmptyState } from '../components/EmptyState';
import {
  RADIUS_CARD, RADIUS_CAPSULE, FONT_BODY, FONT_LABEL, FONT_TITLE, CONTROL_HIT_SIZE,
  QUEUE_DRAG_EDGE, QUEUE_DRAG_SCROLL_STEP, QUEUE_DRAG_SCROLL_MS
} from '../common/DesignTokens';
import { PlayMode } from '../service/playback/QueueEngine';
import { QueueDragState, QueueRowBounds, nearestQueueRow } from '../service/playback/QueueDragState';

interface MeasuredQueueRow {
  top: number;
  height: number;
  scrollOffset: number;
}

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
  @State @Watch('onQueueChanged') vm: QueueViewModel = queueViewModel;
  /** 手势期间保持行节点稳定，只预览目标位置，松手后一次性提交。 */
  @State localQueue: Track[] = [];
  @State dragId: number | null = null;
  @State targetId: number | null = null;
  @State pressedId: number | null = null;
  @State landedId: number | null = null;
  @State statusText: string = '上下滑动浏览，拖动右侧手柄排序';
  private drag: QueueDragState = new QueueDragState();
  private scroller: Scroller = new Scroller();
  private rowBounds: Map<number, MeasuredQueueRow> = new Map<number, MeasuredQueueRow>();
  private listTop: number = 0;
  private listLeft: number = 0;
  private listWidth: number = 0;
  private listHeight: number = 0;
  private pointerX: number = 0;
  private pointerY: number = 0;
  private scrollTimer: number = -1;
  private landedTimer: number = -1;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private ctxUri(t: Track): string {
    return CoverArtService.resolve(this.ctx(), t);
  }

  aboutToAppear(): void {
    this.localQueue = this.vm.queueTracks.slice();
  }

  aboutToDisappear(): void {
    this.cancelDrag();
    if (this.landedTimer >= 0) {
      clearTimeout(this.landedTimer);
      this.landedTimer = -1;
    }
  }

  private onQueueChanged(): void {
    const same = this.vm.queueTracks.length === this.localQueue.length &&
      this.vm.queueTracks.every((t: Track, i: number) => t.id === this.localQueue[i].id);
    if (!same) {
      this.cancelDrag();
      this.syncLocal();
    }
  }

  private syncLocal(): void {
    this.localQueue = this.vm.queueTracks.slice();
    this.rowBounds.forEach((_bounds: MeasuredQueueRow, id: number) => {
      if (!this.localQueue.some((t: Track) => t.id === id)) {
        this.rowBounds.delete(id);
      }
    });
  }

  private queueIds(): number[] {
    return this.vm.queueTracks.map((t: Track) => t.id);
  }

  /** 只有右侧手柄抢占竖向手势，歌曲内容区仍由 List 正常滚动。 */
  private beginDrag(id: number, event: GestureEvent): void {
    if (this.dragId !== null || !this.drag.begin(this.queueIds(), id)) {
      return;
    }
    this.dragId = id;
    this.landedId = null;
    this.updatePointer(event);
    this.scrollTimer = setInterval(() => { this.scrollWhileDragging(); }, QUEUE_DRAG_SCROLL_MS);
  }

  private updatePointer(event: GestureEvent): void {
    if (this.dragId === null || event.fingerList.length === 0) {
      return;
    }
    this.pointerX = event.fingerList[0].globalX;
    this.pointerY = event.fingerList[0].globalY;
    this.updateTarget();
  }

  private insideList(): boolean {
    return this.listHeight > 0 && this.pointerX >= this.listLeft &&
      this.pointerX <= this.listLeft + this.listWidth && this.pointerY >= this.listTop &&
      this.pointerY <= this.listTop + this.listHeight;
  }

  private updateTarget(): void {
    if (!this.insideList()) {
      this.targetId = null;
      this.drag.setTarget(-1);
      this.statusText = '移回队列内可继续，移出后松手取消';
      return;
    }
    const offset = this.scroller.currentOffset().yOffset;
    const rows: QueueRowBounds[] = [];
    this.localQueue.forEach((t: Track) => {
      const bounds = this.rowBounds.get(t.id);
      if (bounds !== undefined) {
        const top = bounds.top + bounds.scrollOffset - offset;
        if (top + bounds.height > this.listTop && top < this.listTop + this.listHeight) {
          rows.push({ id: t.id, top: top, height: bounds.height });
        }
      }
    });
    const id = nearestQueueRow(this.pointerY, rows);
    const index = this.localQueue.findIndex((t: Track) => t.id === id);
    this.targetId = index >= 0 ? id : null;
    this.drag.setTarget(index);
    this.statusText = index >= 0 ? '松手放到第 ' + (index + 1) + ' 项' : '移回队列内可继续排序';
  }

  private scrollWhileDragging(): void {
    if (this.dragId === null || !this.insideList()) {
      return;
    }
    if (this.pointerY < this.listTop + QUEUE_DRAG_EDGE) {
      this.scroller.scrollBy(0, -QUEUE_DRAG_SCROLL_STEP);
    } else if (this.pointerY > this.listTop + this.listHeight - QUEUE_DRAG_EDGE) {
      this.scroller.scrollBy(0, QUEUE_DRAG_SCROLL_STEP);
    }
    this.updateTarget();
  }

  private stopDragScroll(): void {
    if (this.scrollTimer >= 0) {
      clearInterval(this.scrollTimer);
      this.scrollTimer = -1;
    }
    this.dragId = null;
    this.targetId = null;
    this.pressedId = null;
  }

  private cancelDrag(): void {
    if (this.dragId !== null) {
      this.statusText = '已取消排序';
    }
    this.drag.cancel();
    this.stopDragScroll();
  }

  private finishDrag(): void {
    const movedId = this.dragId;
    const ids = this.drag.finish(this.queueIds());
    this.stopDragScroll();
    if (ids !== null && this.vm.reorder(ids)) {
      this.syncLocal();
      this.landedId = movedId;
      this.statusText = '已调整顺序';
      if (this.landedTimer >= 0) {
        clearTimeout(this.landedTimer);
      }
      this.landedTimer = setTimeout(() => { this.landedId = null; this.landedTimer = -1; }, 700);
    } else {
      this.statusText = ids === null && this.insideList() ? '顺序未变' : '已取消排序';
    }
  }

  private removeTrack(id: number): void {
    if (this.dragId !== null) {
      return;
    }
    const index = this.vm.queueTracks.findIndex((t: Track) => t.id === id);
    if (index >= 0) {
      this.vm.removeAt(index);
      this.syncLocal();
      this.statusText = '已从队列移除';
    }
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
        Text(this.statusText)
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .width('100%')
        List({ space: 10, scroller: this.scroller }) {
          ForEach(this.localQueue, (t: Track) => {
              ListItem() {
                Row({ space: 4 }) {
                  CoverThumb({ uri: this.ctxUri(t), identity: CoverArtService.identity(t), thumbSize: 40 })
                  Column({ space: 3 }) {
                    Text(t.title !== '' ? t.title : t.path)
                      .fontSize(FONT_BODY)
                      .fontWeight(t.id === this.vm.currentId ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(t.id === this.vm.currentId ? this.theme.primaryText : this.theme.ink)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(t.artist)
                      .fontSize(FONT_LABEL)
                      .fontColor(this.theme.muted)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 8 })
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.trash'))
                      .fontSize('16vp')
                      .fontColor([this.theme.muted])
                  }
                  .width(CONTROL_HIT_SIZE)
                  .height(CONTROL_HIT_SIZE)
                  .backgroundColor(this.theme.transparent)
                  .enabled(this.dragId === null)
                  .accessibilityText('从队列移除：' + t.title)
                  .onClick(() => { this.removeTrack(t.id); })
                  Stack() {
                    SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                      .fontSize('18vp')
                      .fontColor([this.theme.muted])
                  }
                  .width(CONTROL_HIT_SIZE)
                  .height(CONTROL_HIT_SIZE)
                  .borderRadius(12)
                  .backgroundColor(this.pressedId === t.id || this.dragId === t.id
                    ? ThemeService.alpha(this.theme.primary, 0.2) : this.theme.transparent)
                  .accessibilityText('上下拖动调整顺序：' + t.title)
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.pressedId = t.id;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedId = null;
                    }
                  })
                  .priorityGesture(
                    PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 6 })
                      .onActionStart((event: GestureEvent) => { this.beginDrag(t.id, event); })
                      .onActionUpdate((event: GestureEvent) => { this.updatePointer(event); })
                      .onActionEnd((event: GestureEvent) => {
                        this.updatePointer(event);
                        this.finishDrag();
                      })
                      .onActionCancel(() => { this.cancelDrag(); })
                  )
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(RADIUS_CARD)
                .backgroundColor(this.dragId === t.id
                  ? ThemeService.alpha(this.theme.primary, 0.16) : this.theme.card)
                .opacity(this.dragId === t.id ? 0.7 : 1)
                .border({
                  width: this.targetId === t.id || this.landedId === t.id ? 2 :
                    t.id === this.vm.currentId ? 1 : 0,
                  color: ThemeService.alpha(this.theme.primary, 0.5)
                })
              }
              .onAreaChange((_oldArea: Area, area: Area) => {
                this.rowBounds.set(t.id, {
                  top: Number(area.globalPosition.y), height: Number(area.height),
                  scrollOffset: this.scroller.currentOffset().yOffset
                });
              })
            },
            // 稳定键:拖拽重排时 ForEach 按 id 识别元素,避免按索引重建导致拖拽错位
            (t: Track) => t.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .enableScrollInteraction(this.dragId === null)
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.listTop = Number(area.globalPosition.y);
          this.listLeft = Number(area.globalPosition.x);
          this.listWidth = Number(area.width);
          this.listHeight = Number(area.height);
        })
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

}
