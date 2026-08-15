import { ThemeService } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { networkViewModel, NetworkViewModel } from '../viewmodel/NetworkViewModel';
import { ServerProfile } from '../model/Entities';
import { common } from '@kit.AbilityKit';
import { OutlineButton } from '../components/OutlineButton';
import { RADIUS_CARD, FONT_LABEL, FONT_TITLE } from '../common/DesignTokens';

/**
 * 设置页(issue-11 + issue-13 重排 + issue-14 定稿):
 * 分组卡片、小字号;背景图应用/失败状态可见;
 * 主题切换与"恢复默认主题"入口已按用户要求移除(默认深色)。
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

  async pickBackground(): Promise<void> {
    this.bgStatus = '应用背景图中…';
    const err = await BackgroundAdapter.pickAndApply(this.ctx(), this.theme);
    this.bgStatus = err === '' ? '已应用,界面随图而变' : err;
  }

  async rescan(): Promise<void> {
    this.scanStatus = '扫描中…';
    const report = await LibraryScanService.scan(this.ctx());
    this.scanStatus = `新增 ${report.added},缺失 ${report.missing}`;
  }

  @Builder
  GroupTitle(text: string) {
    Text(text)
      .fontSize(FONT_LABEL)
      .fontColor(this.theme.muted)
      .width('100%')
      .padding({ left: 6, top: 8 })
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

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text('设置')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .width('100%')

        // ---- 外观 ----
        this.GroupTitle('外观')

        this.SettingRow($r('sys.symbol.paintpalette'), '自定义背景图',
          this.bgStatus !== '' ? this.bgStatus : '从图取色,界面随图而变')
        Row() {
          OutlineButton({
            theme: this.theme,
            text: '选择图片',
            onTap: (): void => {
              this.pickBackground();
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12, bottom: 10 })

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

        // ---- 连接(预留) ----
        this.GroupTitle('连接(预留)')
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
