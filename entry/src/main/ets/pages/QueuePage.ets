import { ThemeService } from '../service/theme/ThemeService';
import { queueViewModel, QueueViewModel } from '../viewmodel/QueueViewModel';
import { Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { CoverThumb } from '../components/CoverThumb';
import { CoverArtService } from '../service/cover/CoverArtService';
import { EmptyState } from '../components/EmptyState';
import {
  RADIUS_CARD, RADIUS_CAPSULE, FONT_BODY, FONT_LABEL, FONT_TITLE, CONTROL_HIT_SIZE
} from '../common/DesignTokens';
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

/** 播放队列页:原生拖拽重排、封面缩略图、阴影卡片、SymbolGlyph、模式软色胶囊 */
@Component
export struct QueuePage {
  @State theme: ThemeService = ThemeService.getInstance();
  @State @Watch('onQueueChanged') vm: QueueViewModel = queueViewModel;
  @State localQueue: Track[] = [];
  @State statusText: string = '上下滑动浏览，拖动右侧手柄排序';

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private ctxUri(t: Track): string {
    return CoverArtService.resolve(this.ctx(), t);
  }

  aboutToAppear(): void {
    this.syncLocal();
  }

  private onQueueChanged(): void {
    const same = this.vm.queueTracks.length === this.localQueue.length &&
      this.vm.queueTracks.every((t: Track, i: number) => t.id === this.localQueue[i].id);
    if (!same) {
      this.syncLocal();
    }
  }

  private syncLocal(): void {
    this.localQueue = this.vm.queueTracks.slice();
  }

  private onItemMove(from: number, to: number): void {
    if (from < 0 || to < 0 || from >= this.localQueue.length || to >= this.localQueue.length || from === to) {
      return;
    }
    const moved = this.localQueue.splice(from, 1)[0];
    if (moved !== undefined) {
      this.localQueue.splice(to, 0, moved);
    }
    this.vm.reorder(from, to);
    this.statusText = '已调整顺序';
  }

  private removeTrack(id: number): void {
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
        List({ space: 10 }) {
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
                .accessibilityText('从队列移除：' + t.title)
                .onClick(() => { this.removeTrack(t.id); })

                // 拖拽手柄图标 sys.symbol.line_3_horizontal
                Stack() {
                  SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                    .fontSize('18vp')
                    .fontColor([this.theme.muted])
                }
                .width(CONTROL_HIT_SIZE)
                .height(CONTROL_HIT_SIZE)
                .borderRadius(12)
                .accessibilityText('拖动调整顺序：' + t.title)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(RADIUS_CARD)
              .backgroundColor(this.theme.card)
              .border({
                width: t.id === this.vm.currentId ? 1 : 0,
                color: ThemeService.alpha(this.theme.primary, 0.5)
              })
            }
          },
          (t: Track) => t.id.toString())
          .onMove((from: number, to: number) => {
            this.onItemMove(from, to);
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    .width('100%')
    .height('100%')
  }
}
