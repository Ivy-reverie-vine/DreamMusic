import { CARD_BG, CARD_INK, CARD_MUTED, MUSIC_FORM_METHOD } from '../../model/MusicCard';
import { PLAYBACK_DESTINATION } from '../../model/PlaybackLaunch';

let storage = new LocalStorage();

@Entry(storage)
@Component
struct MusicCard {
  @LocalStorageProp('title') title: string = '还没有播放的音乐';
  @LocalStorageProp('artist') artist: string = '打开应用，选择一首歌';
  @LocalStorageProp('status') status: string = '暂无歌曲';
  @LocalStorageProp('state') state: string = 'idle';
  @LocalStorageProp('hasTrack') hasTrack: boolean = false;
  @LocalStorageProp('canPlay') canPlay: boolean = false;
  @LocalStorageProp('cover') cover: string = '';
  @LocalStorageProp('accent') accent: string = CARD_INK;
  @LocalStorageProp('ohos.extra.param.key.form_dimension') dimension: number = 2;

  @Builder
  Cover(size: number) {
    Image(this.cover === '' ? $r('app.media.cover_placeholder') : this.cover)
      .width(size).height(size).objectFit(ImageFit.Cover).borderRadius(12)
  }

  @Builder
  SongText() {
    Column({ space: 4 }) {
      Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(CARD_INK)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text(this.artist).fontSize(12).fontColor(CARD_MUTED)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  @Builder
  Control(command: string, icon: Resource, label: string, enabled: boolean) {
    if (enabled) {
      FormLink({ action: 'call', abilityName: 'EntryAbility', moduleName: 'entry',
        params: { method: MUSIC_FORM_METHOD, command: command } }) {
        Image(icon).width(24).height(24).fillColor(this.accent)
      }.width(44).height(44).accessibilityText(label)
    } else {
      Image(icon).width(24).height(24).fillColor(CARD_MUTED).opacity(0.4)
        .margin(10).accessibilityText(label + '，暂不可用')
    }
  }

  @Builder
  Controls() {
    Row() {
      this.Control('previous', $r('app.media.card_previous'), '上一首', this.hasTrack && this.state !== 'preparing')
      this.Control(this.state === 'playing' ? 'pause' : 'play',
        this.state === 'playing' ? $r('app.media.card_pause') : $r('app.media.card_play'),
        this.state === 'playing' ? '暂停' : '播放', this.canPlay)
      this.Control('next', $r('app.media.card_next'), '下一首', this.hasTrack && this.state !== 'preparing')
    }.width('100%').justifyContent(FlexAlign.SpaceBetween)
  }

  build() {
    Column({ space: 4 }) {
      if (this.dimension === 3) {
        Row({ space: 16 }) {
          FormLink({ action: 'router', abilityName: 'EntryAbility', moduleName: 'entry',
            params: { 'dreammusic.destination': PLAYBACK_DESTINATION } }) {
            this.Cover(104)
          }.accessibilityText('打开正在播放')
          Column({ space: 8 }) {
            FormLink({ action: 'router', abilityName: 'EntryAbility', moduleName: 'entry',
              params: { 'dreammusic.destination': PLAYBACK_DESTINATION } }) {
              this.SongText()
            }.width('100%').layoutWeight(1)
            this.Controls()
          }.layoutWeight(1).height(104)
        }.layoutWeight(1).width('100%')
      } else {
        FormLink({ action: 'router', abilityName: 'EntryAbility', moduleName: 'entry',
          params: { 'dreammusic.destination': PLAYBACK_DESTINATION } }) {
          Row({ space: 8 }) {
            this.Cover(44)
            this.SongText()
          }.width('100%')
        }.width('100%').layoutWeight(1).accessibilityText('打开正在播放')
        this.Controls()
      }
      FormLink({ action: 'router', abilityName: 'EntryAbility', moduleName: 'entry',
        params: { 'dreammusic.destination': PLAYBACK_DESTINATION } }) {
        Text(this.status).fontSize(11).fontColor(CARD_MUTED).width('100%')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
    }.width('100%').height('100%').padding(12).backgroundColor(CARD_BG).borderRadius(16)
  }
}
