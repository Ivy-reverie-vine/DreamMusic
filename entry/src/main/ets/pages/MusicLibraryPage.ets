import { ThemeService } from '../service/theme/ThemeService';
import { ImportService } from '../service/library/ImportService';
import { common } from '@kit.AbilityKit';

/** 音乐库页(歌曲/专辑/艺术家三视图占位,issue-04 填充;导入入口已接) */
@Component
export struct MusicLibraryPage {
  @Prop theme: ThemeService;
  @State tab: number = 0;
  @State importStatus: string = '';

  async importFiles(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.importStatus = '选择文件中…';
    const sources = await ImportService.pickAudioFiles(ctx);
    if (sources.length === 0) {
      this.importStatus = '未选择文件';
      return;
    }
    this.importStatus = `导入 0/${sources.length}`;
    const result = await ImportService.importSources(ctx, sources, (done: number, total: number): void => {
      this.importStatus = `导入 ${done}/${total}`;
    });
    this.importStatus = `完成:导入 ${result.imported},跳过 ${result.skipped},重复 ${result.duplicates}`;
  }

  async importFolder(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.importStatus = '选择文件夹中…';
    const sources = await ImportService.pickAudioFolder(ctx);
    if (sources.length === 0) {
      this.importStatus = '文件夹中没有支持的音频';
      return;
    }
    const result = await ImportService.importSources(ctx, sources, (done: number, total: number): void => {
      this.importStatus = `导入 ${done}/${total}`;
    });
    this.importStatus = `完成:导入 ${result.imported},跳过 ${result.skipped},重复 ${result.duplicates}`;
  }

  build() {
    Column({ space: 16 }) {
      Text('音乐库')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(['歌曲', '专辑', '艺术家'], (item: string, index: number) => {
          Text(item)
            .fontSize(16)
            .fontColor(index === this.tab ? this.theme.primary : this.theme.muted)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(index === this.tab ? this.theme.bg : '#00000000')
            .onClick(() => {
              this.tab = index;
            })
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('导入文件')
          .fontSize(14)
          .fontColor(this.theme.ink)
          .backgroundColor(this.theme.primary)
          .borderRadius(18)
          .onClick(() => {
            this.importFiles();
          })
        Button('导入文件夹')
          .fontSize(14)
          .fontColor(this.theme.ink)
          .backgroundColor(this.theme.secondary)
          .borderRadius(18)
          .onClick(() => {
            this.importFolder();
          })
        Text(this.importStatus)
          .fontSize(12)
          .fontColor(this.theme.muted)
          .layoutWeight(1)
      }
      .width('100%')

      Column({ space: 8 }) {
        Text('音乐库还是空的')
          .fontSize(18)
          .fontColor(this.theme.ink)
        Text('用上方按钮导入 MP3/AAC(M4A)/FLAC/WAV,导入后这里出现你的音乐')
          .fontSize(14)
          .fontColor(this.theme.muted)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }
}
