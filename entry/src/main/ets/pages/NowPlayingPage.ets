import { ThemeService } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { BubblePauseButton } from '../components/BubblePauseButton';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { lyricsViewModel, LyricsViewModel } from '../viewmodel/LyricsViewModel';
import { PlayerState } from '../model/Playback';
import { Track } from '../model/Entities';
import { common } from '@kit.AbilityKit';

function fmt(ms: number): string {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ':' + (s < 10 ? '0' + s : s.toString());
}

/** 正在播放页(issue-05/08):封面/曲目信息/歌词/进度/音量/泡泡暂停按钮 */
@Component
export struct NowPlayingPage {
  @Prop theme: ThemeService;
  @State vm: PlayerViewModel = playerViewModel;
  @State lrc: LyricsViewModel = lyricsViewModel;

  aboutToAppear(): void {
    this.lrc.setContext(this.ctx());
    // 封面取色(issue-00/PRD story46):切歌 → 从封面提取主题色,500ms 渐变(真机验证渐变观感)
    playerViewModel.coverColorHandler = (t: Track): void => {
      this.applyCoverColors(t);
    };
  }

  private async applyCoverColors(t: Track): Promise<void> {
    if (t.coverPath === '') {
      return;
    }
    try {
      const abs = this.ctx().filesDir + '/' + t.coverPath;
      const colors = await BackgroundAdapter.extractFromFile(abs);
      animateTo({ duration: 500, curve: Curve.EaseOut }, () => {
        this.theme.applyExtracted(colors.primary, colors.secondary);
      });
    } catch (err) {
      // 封面取色失败静默,保持当前主题
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private coverUri(): string {
    const t = this.vm.currentTrack;
    if (t === null || t.coverPath === '') {
      return '';
    }
    return 'file://' + this.ctx().filesDir + '/' + t.coverPath;
  }

  @Builder
  LyricWindow() {
    Column({ space: 6 }) {
      if (this.lrc.lines.length > 0) {
        // 当前行 + 前后各一行;无歌词时整个区域隐藏
        Text(this.lrc.activeIndex > 0 ? this.lrc.lines[this.lrc.activeIndex - 1].text : '')
          .fontSize(14)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.lrc.activeIndex >= 0 ? this.lrc.lines[this.lrc.activeIndex].text : '')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.lrc.activeIndex >= 0 && this.lrc.activeIndex + 1 < this.lrc.lines.length
          ? this.lrc.lines[this.lrc.activeIndex + 1].text : '')
          .fontSize(14)
          .fontColor(this.theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(96)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column({ space: 20 }) {
      if (this.vm.currentTrack === null) {
        Column({ space: 8 }) {
          Text('还没有在播放')
            .fontSize(18)
            .fontColor(this.theme.ink)
          Text('去音乐库点一首歌')
            .fontSize(14)
            .fontColor(this.theme.muted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 封面:有封面图显示图,否则主色圆 + 光晕(黑胶展开动效留待原型评审)
        if (this.coverUri() !== '') {
          Image(this.coverUri())
            .width(220)
            .height(220)
            .borderRadius(110)
            .objectFit(ImageFit.Cover)
        } else {
          Circle()
            .width(220)
            .height(220)
            .fill(this.theme.primary)
            .opacity(0.85)
            .shadow({ radius: 60, color: this.theme.primary, offsetX: 0, offsetY: 0 })
        }

        Column({ space: 6 }) {
          Text(this.vm.currentTrack.title !== '' ? this.vm.currentTrack.title : this.vm.currentTrack.path)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.vm.currentTrack.artist}${this.vm.currentTrack.album !== '' ? ' · ' + this.vm.currentTrack.album : ''}`)
            .fontSize(15)
            .fontColor(this.theme.muted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        // 歌词窗口(无歌词自动隐藏)
        this.LyricWindow()

        // 进度条
        Row({ space: 8 }) {
          Text(fmt(this.vm.positionMs))
            .fontSize(12)
            .fontColor(this.theme.muted)
          Slider({
            value: this.vm.positionMs,
            min: 0,
            max: this.vm.durationMs > 0 ? this.vm.durationMs : 1
          })
            .layoutWeight(1)
            .selectedColor(this.theme.primary)
            .trackColor(this.theme.trackColor)
            .onChange((value: number) => {
              this.vm.seekTo(value);
            })
          Text(fmt(this.vm.durationMs))
            .fontSize(12)
            .fontColor(this.theme.muted)
        }
        .width('85%')

        // 音量
        Row({ space: 8 }) {
          Text('🔊')
            .fontSize(14)
            .fontColor(this.theme.muted)
          Slider({ value: this.vm.volume, min: 0, max: 1, step: 0.01 })
            .layoutWeight(1)
            .selectedColor(this.theme.secondary)
            .trackColor(this.theme.trackColor)
            .onChange((value: number) => {
              this.vm.setVolume(value);
            })
        }
        .width('70%')

        Row({ space: 36 }) {
          Text('⏮')
            .fontSize(26)
            .fontColor(this.theme.muted)
            .onClick(() => {
              queueViewModel.playPrev();
            })
          BubblePauseButton({
            theme: this.theme,
            isPlaying: this.vm.state === PlayerState.PLAYING,
            onToggle: (): void => {
              this.vm.togglePause();
            }
          })
          Text('⏭')
            .fontSize(26)
            .fontColor(this.theme.muted)
            .onClick(() => {
              queueViewModel.playNext();
            })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')

        if (this.vm.errorText !== '') {
          Text(this.vm.errorText)
            .fontSize(12)
            .fontColor(this.theme.secondary)
        }
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
