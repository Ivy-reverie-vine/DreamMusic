import { ThemeService } from '../service/theme/ThemeService';
import { Track } from '../model/Entities';
import { CoverThumb } from './CoverThumb';
import { RADIUS_CARD, FONT_BODY, FONT_LABEL, CONTROL_HIT_SIZE } from '../common/DesignTokens';
import { playbackControlGate, PlaybackControlGate } from '../viewmodel/PlaybackControlGate';
import { common } from '@kit.AbilityKit';
import { CoverArtService } from '../service/cover/CoverArtService';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { PlayerState } from '../model/Playback';
import { PlaybackStatus } from './PlaybackStatus';

@Component
export struct MiniPlayerBar {
  @State theme: ThemeService = ThemeService.getInstance();
  @State controls: PlaybackControlGate = playbackControlGate;
  @State vm: PlayerViewModel = playerViewModel;
  onGoLibrary: () => void = () => {};
  onGoSettings: () => void = () => {};
  @Prop track: Track;
  @Prop playing: boolean;
  onOpen: () => void = () => {
  };
  onToggle: () => Promise<void> = async () => {
  };
  onNext: () => Promise<void> = async () => {
  };

  private coverUri(): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return CoverArtService.resolve(context, this.track);
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        // 歌曲入口与两个按钮为兄弟节点，外层不绑定打开页面的点击事件。
        Row({ space: 10 }) {
          CoverThumb({ uri: this.coverUri(), identity: CoverArtService.identity(this.track), thumbSize: 42 })
          Column({ space: 2 }) {
            Text(this.track.title !== '' ? this.track.title : this.track.path)
              .fontSize(FONT_BODY)
              .fontColor(this.theme.ink)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.track.artist !== '' ? this.track.artist : '正在播放')
              .fontSize(FONT_LABEL)
              .fontColor(this.theme.muted)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: CONTROL_HIT_SIZE })
        .accessibilityText('打开正在播放：' + this.track.title)
        .onClick(() => { this.onOpen(); })
        Button({ type: ButtonType.Circle }) {
          if (this.vm.state === PlayerState.PREPARING) {
            LoadingProgress().width(22).height(22).color(this.theme.primaryText)
          } else {
            SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize('20vp')
              .fontColor([this.theme.primaryText])
          }
        }
        .width(CONTROL_HIT_SIZE)
        .height(CONTROL_HIT_SIZE)
        .backgroundColor(this.theme.transparent)
        .enabled(!this.controls.busy && this.vm.state !== PlayerState.PREPARING && this.vm.state !== PlayerState.ERROR)
        .accessibilityText(this.vm.state === PlayerState.PREPARING ? '正在加载音乐' : (this.playing ? '暂停' : '播放'))
        .onClick(() => { this.controls.run(this.onToggle); })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize('19vp')
            .fontColor([this.theme.primaryText])
        }
        .width(CONTROL_HIT_SIZE)
        .height(CONTROL_HIT_SIZE)
        .backgroundColor(this.theme.transparent)
        .enabled(!this.controls.busy)
        .accessibilityText('下一首')
        .onClick(() => { this.controls.run(this.onNext); })
      }
      .width('100%')
      PlaybackStatus({ compact: true, onGoLibrary: this.onGoLibrary, onGoSettings: this.onGoSettings })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
    .shadow({ radius: 18, color: this.theme.isDark ? ThemeService.alpha('#000000', 0.32) : this.theme.shadowColor,
      offsetX: 0, offsetY: 6 })
  }
}
