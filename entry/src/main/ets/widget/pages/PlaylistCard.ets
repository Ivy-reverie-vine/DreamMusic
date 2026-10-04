import { CARD_BG, CARD_INK, CARD_MUTED } from '../../model/MusicCard';
import { PLAYLIST_DESTINATION } from '../../model/PlaybackLaunch';

let storage = new LocalStorage();

@Entry(storage)
@Component
struct PlaylistCard {
  @LocalStorageProp('playlistId') playlistId: number = 0;
  @LocalStorageProp('title') title: string = '我喜欢的音乐';
  @LocalStorageProp('summary') summary: string = '正在读取本地歌单';
  @LocalStorageProp('action') action: string = '打开歌单';

  build() {
    FormLink({ action: 'router', abilityName: 'EntryAbility', moduleName: 'entry',
      params: { 'dreammusic.destination': PLAYLIST_DESTINATION, 'dreammusic.playlistId': this.playlistId } }) {
      Column({ space: 8 }) {
        Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(CARD_INK)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.summary).fontSize(12).fontColor(CARD_MUTED).width('100%')
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text(this.action + ' ›').fontSize(12).fontColor(CARD_INK).width('100%').height(44)
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
        .padding(12).backgroundColor(CARD_BG).borderRadius(16)
    }.width('100%').height('100%').accessibilityText(this.title + '，' + this.summary + '，' + this.action)
  }
}
