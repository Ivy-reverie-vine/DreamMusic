import { ThemeService } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { common } from '@kit.AbilityKit';

/** 设置页(导入/背景图/服务器配置入口在对应 issue 填充) */
@Component
export struct SettingsPage {
  @Prop theme: ThemeService;
  @State scanStatus: string = '';

  async pickBackground(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await BackgroundAdapter.pickAndApply(ctx, this.theme);
  }

  async rescan(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.scanStatus = '扫描中…';
    const report = await LibraryScanService.scan(ctx);
    this.scanStatus = `扫描完成:新增 ${report.added},缺失 ${report.missing}`;
  }

  build() {
    Column({ space: 16 }) {
      Text('设置')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
        .width('100%')

      Column({ space: 12 }) {
        // 背景图与取色(issue-00,真机验证)
        Row() {
          Column({ space: 2 }) {
            Text('自定义背景图')
              .fontSize(16)
              .fontColor(this.theme.ink)
            Text('从图取色,界面随图而变')
              .fontSize(12)
              .fontColor(this.theme.muted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('选择图片')
            .fontSize(14)
            .fontColor(this.theme.ink)
            .backgroundColor(this.theme.primary)
            .borderRadius(18)
            .onClick(() => {
              this.pickBackground();
            })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.theme.bg)

        Row() {
          Column({ space: 2 }) {
            Text('重新扫描音乐库')
              .fontSize(16)
              .fontColor(this.theme.ink)
            Text(this.scanStatus !== '' ? this.scanStatus : '比对沙箱目录与数据库')
              .fontSize(12)
              .fontColor(this.theme.muted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('扫描')
            .fontSize(14)
            .fontColor(this.theme.ink)
            .backgroundColor(this.theme.secondary)
            .borderRadius(18)
            .onClick(() => {
              this.rescan();
            })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.theme.bg)

        Row() {
          Text('恢复默认主题')
            .fontSize(16)
            .fontColor(this.theme.ink)
            .layoutWeight(1)
          Button('恢复')
            .fontSize(14)
            .fontColor(this.theme.ink)
            .backgroundColor(this.theme.secondary)
            .borderRadius(18)
            .onClick(() => {
              this.theme.applyDefault();
            })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.theme.bg)

        Column({ space: 8 }) {
          Text('设置项陆续到位')
            .fontSize(14)
            .fontColor(this.theme.muted)
          Text('导入管理、服务器配置、扫描、主题')
            .fontSize(12)
            .fontColor(this.theme.muted)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }
}
