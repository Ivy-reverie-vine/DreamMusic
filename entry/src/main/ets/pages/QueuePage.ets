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
  @Prop theme: ThemeService;
  @State vm: QueueViewModel = queueViewModel;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private ctxUri(t: Track): string {
    return t.coverPath !== '' ? 'file://' + this.ctx().filesDir + '/' + t.coverPath : '';
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
            .fontColor([this.theme.primary])
          Text(modeLabel(this.vm.mode))
            .fontSize(13)
            .fontColor(this.theme.primary)
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
          theme: this.theme,
          symbol: $r('sys.symbol.list_bullet'),
          title: '队列是空的',
          hint: '去音乐库点歌,或按播放键从断点续播'
        })
      } else {
        List({ space: 10 }) {
          ForEach(this.vm.queueTracks, (t: Track, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                CoverThumb({ theme: this.theme, uri: this.ctxUri(t), thumbSize: 40 })
                Column({ space: 3 }) {
                  Text(t.title !== '' ? t.title : t.path)
                    .fontSize(FONT_BODY)
                    .fontWeight(index === this.vm.currentIndexId() ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(index === this.vm.currentIndexId() ? this.theme.primary : this.theme.ink)
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
                width: index === this.vm.currentIndexId() ? 1 : 0,
                color: ThemeService.alpha(this.theme.primary, 0.5)
              })
              .stateStyles({
                pressed: { .backgroundColor(ThemeService.alpha(this.theme.primary, 0.1)) }
              })
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

  @Builder
  dragIcon() {
    SymbolGlyph($r('sys.symbol.line_3_horizontal'))
      .fontSize(22)
      .fontColor([this.theme.muted])
      .padding(8)
      .backgroundColor(this.theme.card)
      .borderRadius(RADIUS_CARD)
  }
}
