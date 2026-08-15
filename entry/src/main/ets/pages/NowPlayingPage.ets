import { ThemeService } from '../service/theme/ThemeService';
import { BubblePauseButton } from '../components/BubblePauseButton';
import { playerViewModel, PlayerViewModel } from '../viewmodel/PlayerViewModel';
import { PlayerState } from '../model/Playback';
import { common } from '@kit.AbilityKit';

function fmt(ms: number): string {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ':' + (s < 10 ? '0' + s : s.toString());
}

/** 正在播放页(issue-05):封面/曲目信息/进度/音量/泡泡暂停按钮 */
@Component
export struct NowPlayingPage {
  @Prop theme: ThemeService;
  @State vm: PlayerViewModel = playerViewModel;

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
            .trackColor('#33FFFFFF')
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
            .trackColor('#33FFFFFF')
            .onChange((value: number) => {
              this.vm.setVolume(value);
            })
        }
        .width('70%')

        Row({ space: 36 }) {
          Text('⏮')
            .fontSize(26)
            .fontColor(this.theme.muted)
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
