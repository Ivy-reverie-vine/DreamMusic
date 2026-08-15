import { ThemeService, BG_PRESETS, BgPreset } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { networkViewModel, NetworkViewModel } from '../viewmodel/NetworkViewModel';
import { ServerProfile } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { OutlineButton } from '../components/OutlineButton';
import { RADIUS_CARD, FONT_LABEL, FONT_TITLE } from '../common/DesignTokens';

/**
 * 设置页(issue-14 定稿):
 * 标题在最上,选项依次排下——背景图(内置预设网格,点选即应用并持久化)/
 * 重新扫描 / api-enhanced 连接 / 服务器配置。
 */
@Component
export struct SettingsPage {
  @Prop theme: ThemeService;
  @State scanStatus: string = '';
  @State bgStatus: string = '';
  @State net: NetworkViewModel = networkViewModel;
  @State newAlias: string = '';
  @State newUrl: string = '';

  aboutToAppear(): void {
    this.net.load();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  applyBg(index: number): void {
    this.theme.applyPresetBg(index);
    ThemeService.saveBgIndex(this.ctx(), index);
    this.bgStatus = `已应用背景 ${index + 1}`;
  }

  async rescan(): Promise<void> {
    this.scanStatus = '扫描中…';
    const report = await LibraryScanService.scan(this.ctx());
    this.scanStatus = `新增 ${report.added},缺失 ${report.missing}`;
  }

  @Builder
  SettingRow(icon: Resource, title: string, subtitle: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.theme.muted])
      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontColor(this.theme.ink)
        if (subtitle !== '') {
          Text(subtitle)
            .fontSize(11)
            .fontColor(this.theme.muted)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
  }

  @Builder
  BgGrid() {
    Row({ space: 10 }) {
      ForEach(BG_PRESETS, (p: BgPreset, index: number) => {
        Stack() {
          Image(p.res)
            .width(76)
            .height(132)
            .borderRadius(14)
            .objectFit(ImageFit.Cover)
          if (this.theme.bgPresetIndex === index) {
            Column()
              .width('100%')
              .height('100%')
              .borderRadius(14)
              .border({ width: 2, color: this.theme.primary })
              .backgroundColor(ThemeService.alpha(this.theme.primary, 0.18))
          }
        }
        .stateStyles({
          pressed: { .opacity(0.7) }
        })
        .onClick(() => {
          this.applyBg(index);
        })
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 10 })
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text('设置')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .width('100%')

        // 背景图(内置预设,点选即应用)
        this.SettingRow($r('sys.symbol.paintpalette'), '背景图',
          this.bgStatus !== '' ? this.bgStatus : '从内置氛围图中选择,界面随图取色')
        this.BgGrid()

        // 重新扫描
        this.SettingRow($r('sys.symbol.arrow_clockwise'), '重新扫描',
          this.scanStatus !== '' ? this.scanStatus : '比对沙箱目录与数据库')
        Row() {
          OutlineButton({
            theme: this.theme,
            text: '扫描',
            onTap: (): void => {
              this.rescan();
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12, bottom: 10 })

        // api-enhanced 连接(预留)
        this.SettingRow($r('sys.symbol.wifi'), 'api-enhanced', this.net.statusText)
        Row() {
          OutlineButton({
            theme: this.theme,
            text: '刷新',
            onTap: (): void => {
              this.net.probe();
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12, bottom: 10 })

        Row({ space: 8 }) {
          TextInput({ placeholder: '别名(可选)', text: this.newAlias })
            .fontSize(13)
            .fontColor(this.theme.ink)
            .placeholderColor(this.theme.muted)
            .backgroundColor(this.theme.card)
            .borderRadius(12)
            .height(38)
            .width(110)
            .onChange((v: string) => {
              this.newAlias = v;
            })
          TextInput({ placeholder: 'https://你的域名', text: this.newUrl })
            .fontSize(13)
            .fontColor(this.theme.ink)
            .placeholderColor(this.theme.muted)
            .backgroundColor(this.theme.card)
            .borderRadius(12)
            .height(38)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.newUrl = v;
            })
          OutlineButton({
            theme: this.theme,
            text: '添加',
            onTap: (): void => {
              this.net.addProfile(this.newAlias, this.newUrl).then(() => {
                this.newAlias = '';
                this.newUrl = '';
              });
            }
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6 })

        ForEach(this.net.profiles, (p: ServerProfile) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(p.alias)
                .fontSize(14)
                .fontColor(this.theme.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(p.url)
                .fontSize(11)
                .fontColor(this.theme.muted)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (!p.isCurrent) {
              Text('设为当前')
                .fontSize(12)
                .fontColor(this.theme.primaryText)
                .onClick(() => {
                  this.net.setCurrent(p.id);
                })
            } else {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(13)
                  .fontColor([this.theme.primaryText])
                Text('当前')
                  .fontSize(12)
                  .fontColor(this.theme.primaryText)
              }
            }
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(15)
              .fontColor([this.theme.muted])
              .padding(4)
              .onClick(() => {
                this.net.removeProfile(p.id);
              })
          }
          .width('100%')
          .padding(10)
          .borderRadius(12)
          .backgroundColor(this.theme.card)
        })
      }
      .padding(20)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }
}
