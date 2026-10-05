import { ThemeService } from '../service/theme/ThemeService';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { searchSourceName } from '../viewmodel/OnlineSearchViewModel';
import { BilibiliFallbackCandidate, OnlineSong } from '../model/Entities';
import { PlayerState } from '../model/Playback';
import { CONTROL_HIT_SIZE, FONT_BODY, FONT_LABEL, SPACE_SM } from '../common/DesignTokens';

/** 搜索分组快照只属于当前队列条目；完整性由统一解析重新判断。 */
@Component
export struct SourceSelection {
  @State theme: ThemeService = ThemeService.getInstance();
  @State vm: PlayerViewModel = playerViewModel;
  @State expandedTrackId: number = -1;
  @State expandedOtherId: number = -1;
  @State pendingOtherRef: string = '';
  @State pendingOtherTrackId: number = -1;

  private candidateInfo(candidate: BilibiliFallbackCandidate): string {
    const resource = candidate.resource;
    const text = (resource?.title ?? '') + ' ' + (resource?.partTitle ?? '');
    const version = /翻唱|cover/i.test(text) ? '翻唱' : /现场|演唱会|live/i.test(text) ? '现场' :
      /\bmv\b|music video/i.test(text) ? 'MV' : '录音版本未确认';
    const reason = candidate.reason === 'different_recording_or_extra_segments' ? '不同录音或可能含对白、前后奏、剪辑' :
      candidate.reason === 'recording_provenance_missing' ? '缺少原录音来源证据' :
      candidate.reason === 'audio_content_uncertain' ? '音频内容未确认' :
      candidate.reason === 'recording_credits_or_duration_mismatch' ? '署名或时长与原录音不一致' :
      candidate.reason === 'part_recording_uncertain' ? '分 P 与原录音不确定' : '未通过自动替换检查（' + candidate.reason + '）';
    const integrity = candidate.audioIntegrity?.status === 'preview' ? '试听，不能作为完整版播放' :
      candidate.audioIntegrity?.status === 'full' ? '仍需重新检查音频完整性' : '音频完整性待解析确认';
    return searchSourceName(candidate.source) + ' · ' + version + ' · P' + (resource?.page ?? 0) +
      '\n' + (resource?.title ?? candidate.title) + '\n' + reason + '\n' + integrity;
  }

  private choose(song: OnlineSong): void {
    if (song.mediaRef !== undefined) { this.vm.selectSource(song.mediaRef); }
  }

  build() {
    Column({ space: SPACE_SM }) {
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
      if (this.vm.otherRecordingOptions.length > 0) {
        Column({ space: SPACE_SM }) {
          Button(this.expandedOtherId === this.vm.currentTrack?.id ? '收起其他录音候选' : '查看其他录音候选')
            .constraintSize({ minHeight: CONTROL_HIT_SIZE }).fontSize(FONT_BODY)
            .fontColor(this.theme.primaryText).backgroundColor(this.theme.transparent)
            .accessibilityText('查看自动拒绝的其他录音与额外片段候选')
            .onClick(() => {
              this.expandedOtherId = this.expandedOtherId === this.vm.currentTrack?.id ? -1 : this.vm.currentTrack?.id ?? -1;
              this.pendingOtherRef = '';
            })
          if (this.expandedOtherId === this.vm.currentTrack?.id) {
            Text('选择后成为独立曲目，仅替换当前队列条目；不会沿用原曲收藏或同步歌词')
              .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
            if (this.vm.state === PlayerState.ERROR && this.vm.currentTrack?.otherRecordingOrigin !== undefined) {
              Text(this.vm.errorText).fontSize(FONT_LABEL).fontColor(this.theme.errorColor).width('100%')
              Button('重试所选候选').constraintSize({ minHeight: CONTROL_HIT_SIZE })
                .fontColor(this.theme.primaryText).backgroundColor(this.theme.transparent)
                .onClick(() => { this.vm.retry(); })
            }
            ForEach(this.vm.otherRecordingOptions, (candidate: BilibiliFallbackCandidate) => {
              Column({ space: SPACE_SM }) {
                Text(candidate.title).fontSize(FONT_BODY).fontColor(this.theme.ink).width('100%')
                Text(this.candidateInfo(candidate)).fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
                Button('选择候选：' + candidate.title)
                  .constraintSize({ minHeight: CONTROL_HIT_SIZE }).width('100%').fontSize(FONT_BODY)
                  .fontColor(this.theme.primaryText).backgroundColor(this.theme.transparent)
                  .enabled(this.vm.state !== PlayerState.PREPARING)
                  .accessibilityText('选择' + candidate.title + '，作为独立曲目播放')
                  .onClick(() => {
                    this.pendingOtherRef = candidate.mediaRef ?? '';
                    this.pendingOtherTrackId = this.vm.currentTrack?.id ?? -1;
                  })
                if (this.pendingOtherRef === candidate.mediaRef && this.pendingOtherTrackId === this.vm.currentTrack?.id) {
                  Text('接受不同或不确定版本；若只提供试听或完整性未知，仍无法播放')
                    .fontSize(FONT_LABEL).fontColor(this.theme.muted).width('100%')
                  Button('确认播放此独立曲目').constraintSize({ minHeight: CONTROL_HIT_SIZE })
                    .fontColor(this.theme.primaryText).backgroundColor(this.theme.transparent)
                    .enabled(this.vm.state !== PlayerState.PREPARING)
                    .onClick(() => {
                      const ref = this.pendingOtherRef;
                      this.pendingOtherRef = '';
                      this.vm.selectOtherRecording(ref);
                    })
                  Button('取消选择').constraintSize({ minHeight: CONTROL_HIT_SIZE })
                    .fontColor(this.theme.primaryText).backgroundColor(this.theme.transparent)
                    .onClick(() => { this.pendingOtherRef = ''; })
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (candidate: BilibiliFallbackCandidate) => candidate.mediaRef ?? '')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
