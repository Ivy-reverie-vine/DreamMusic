import { ThemeService } from '../service/theme/ThemeService';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { searchSourceName } from '../viewmodel/OnlineSearchViewModel';
import { OnlineSong } from '../model/Entities';
import { PlayerState } from '../model/Playback';
import { CONTROL_HIT_SIZE, FONT_BODY, FONT_LABEL, SPACE_SM } from '../common/DesignTokens';

/** 搜索分组快照只属于当前队列条目；完整性由统一解析重新判断。 */
@Component
export struct SourceSelection {
  @State theme: ThemeService = ThemeService.getInstance();
  @State vm: PlayerViewModel = playerViewModel;
  @State expandedTrackId: number = -1;

  private choose(song: OnlineSong): void {
    if (song.mediaRef !== undefined) { this.vm.selectSource(song.mediaRef); }
  }

  build() {
    if (this.vm.sourceOptions.length > 0) {
      Column({ space: SPACE_SM }) {
        Button(this.expandedTrackId === this.vm.currentTrack?.id ? '收起同录音来源' : '选择同录音来源')
          .constraintSize({ minHeight: CONTROL_HIT_SIZE })
          .fontSize(FONT_BODY)
          .fontColor(this.theme.primaryText)
          .backgroundColor(this.theme.transparent)
          .accessibilityText('为当前队列曲目选择同录音来源')
          .onClick(() => {
            this.expandedTrackId = this.expandedTrackId === this.vm.currentTrack?.id ? -1 : this.vm.currentTrack?.id ?? -1;
          })
        if (this.expandedTrackId === this.vm.currentTrack?.id) {
          Text('仅用于当前队列条目；重新搜索点播后恢复自动选择')
            .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
          if (this.vm.state === PlayerState.ERROR) {
            Text(this.vm.errorText).fontSize(FONT_LABEL).fontColor(this.theme.errorColor).width('100%')
            Button(this.vm.currentTrack?.manualPlaybackRef !== undefined ? '重试所选来源' : '重新寻找完整版')
              .constraintSize({ minHeight: CONTROL_HIT_SIZE })
              .fontColor(this.theme.primaryText).backgroundColor(this.theme.transparent)
              .onClick(() => { this.vm.retry(); })
          }
          ForEach(this.vm.sourceOptions, (song: OnlineSong) => {
            Button(searchSourceName(song.source ?? 'api-enhanced') +
              (song.mediaRef === this.vm.currentTrack?.manualPlaybackRef ? ' · 已选择' : '') +
              (song.mediaRef === this.vm.currentTrack?.playbackRef && this.vm.playbackSourceText !== '' ? ' · 正在使用' : ''))
              .constraintSize({ minHeight: CONTROL_HIT_SIZE })
              .width('100%')
              .fontSize(FONT_BODY)
              .fontColor(this.theme.primaryText)
              .backgroundColor(this.theme.transparent)
              .enabled(this.vm.state !== PlayerState.PREPARING)
              .accessibilityText('使用' + searchSourceName(song.source ?? 'api-enhanced') + '播放当前曲目')
              .onClick(() => { this.choose(song); })
          }, (song: OnlineSong) => song.mediaRef ?? '')
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
}
