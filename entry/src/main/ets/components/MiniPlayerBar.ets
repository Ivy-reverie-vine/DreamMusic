import { ThemeService } from '../service/theme/ThemeService';
import { Track } from '../model/Entities';
import { CoverThumb } from './CoverThumb';
import { RADIUS_CARD, FONT_BODY, FONT_LABEL } from '../common/DesignTokens';
import { common } from '@kit.AbilityKit';

@Component
export struct MiniPlayerBar {
  @State theme: ThemeService = ThemeService.getInstance();
  @Prop track: Track;
  @Prop playing: boolean;
  onOpen: () => void = () => {
  };
  onToggle: () => void = () => {
  };
  onNext: () => void = () => {
  };

  private coverUri(): string {
    if (this.track.streamCoverUrl !== undefined && this.track.streamCoverUrl !== '') {
      return this.track.streamCoverUrl;
    }
    if (this.track.coverPath === '') {
      return '';
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return 'file://' + context.filesDir + '/' + this.track.coverPath;
  }

  build() {
    Row({ space: 10 }) {
      CoverThumb({ uri: this.coverUri(), thumbSize: 42 })
      Column({ space: 2 }) {
        Text(this.track.title !== '' ? this.track.title : this.track.path)
          .fontSize(FONT_BODY)
          .fontColor(this.theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.track.artist !== '' ? this.track.artist : '正在播放')
          .fontSize(FONT_LABEL)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(20)
        .fontColor([this.theme.primaryText])
        .padding(7)
        .onClick(() => {
          this.onToggle();
        })
      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(19)
        .fontColor([this.theme.primaryText])
        .padding(7)
        .onClick(() => {
          this.onNext();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
    .shadow({ radius: 18, color: ThemeService.alpha('#000000', 0.32), offsetX: 0, offsetY: 6 })
    .onClick(() => {
      this.onOpen();
    })
  }
}
