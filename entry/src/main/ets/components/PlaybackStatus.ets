import { ThemeService } from '../service/theme/ThemeService';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { playbackControlGate, PlaybackControlGate } from '../viewmodel/PlaybackControlGate';
import { PlayerState } from '../model/Playback';
import { CONTROL_HIT_SIZE, FONT_LABEL } from '../common/DesignTokens';

/** 两个播控入口共享状态文字和当前音轨的恢复操作。 */
@Component
export struct PlaybackStatus {
  @State theme: ThemeService = ThemeService.getInstance();
  @State vm: PlayerViewModel = playerViewModel;
  @State controls: PlaybackControlGate = playbackControlGate;
  @Prop compact: boolean = false;
  onGoLibrary: () => void = () => {};
  onGoSettings: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Text(this.vm.statusText)
        .fontSize(FONT_LABEL)
        .fontColor(this.vm.state === PlayerState.ERROR ? this.theme.errorColor : this.theme.muted)
        .width('100%')
        .maxLines(this.compact ? 2 : 8)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.vm.state !== PlayerState.ERROR && this.vm.errorText !== '') {
        Text(this.vm.errorText).fontSize(FONT_LABEL).fontColor(this.theme.errorColor).width('100%')
      }
      if (this.vm.state === PlayerState.ERROR) {
        if (this.vm.recoveryAction !== 'library') {
          Button('重试播放')
            .height(CONTROL_HIT_SIZE)
            .fontColor(this.theme.primaryText)
            .backgroundColor(this.theme.transparent)
            .enabled(!this.controls.busy)
            .onClick(() => { this.controls.run(() => this.vm.retry()); })
        }
        if (this.vm.recoveryAction === 'library') {
          Button('到音乐库重新导入')
            .height(CONTROL_HIT_SIZE)
            .fontColor(this.theme.primaryText)
            .backgroundColor(this.theme.transparent)
            .onClick(() => { this.onGoLibrary(); })
        } else if (this.vm.recoveryAction === 'settings') {
          Button('打开设置')
            .height(CONTROL_HIT_SIZE)
            .fontColor(this.theme.primaryText)
            .backgroundColor(this.theme.transparent)
            .onClick(() => { this.onGoSettings(); })
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
