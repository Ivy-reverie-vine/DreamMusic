import { ThemeService } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { playlistsViewModel } from '../viewmodel/PlaylistsViewModel';
import { networkViewModel, NetworkViewModel } from '../viewmodel/NetworkViewModel';
import { ServerProfile } from '../model/Entities';
import { ConnectionStatus } from '../service/network/HealthStateMachine';
import { common } from '@kit.AbilityKit';

/** 设置页(导入/背景图/服务器配置/扫描/主题) */
@Component
export struct SettingsPage {
  @Prop theme: ThemeService;
  @State scanStatus: string = '';
  @State net: NetworkViewModel = networkViewModel;
  @State newAlias: string = '';
  @State newUrl: string = '';

  aboutToAppear(): void {
    this.net.load().then(() => {
      this.net.startPolling();
    });
  }

  aboutToDisappear(): void {
    this.net.stopPolling();
  }

  statusColor(): string {
    switch (this.net.status) {
      case ConnectionStatus.ONLINE:
        return this.theme.primary;
      case ConnectionStatus.CHECKING:
        return this.theme.secondary;
      default:
        return this.theme.muted;
    }
  }

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
          Column({ space: 2 }) {
            Text('api-enhanced 连接(预留)')
              .fontSize(16)
              .fontColor(this.theme.ink)
            Text(this.net.statusText)
              .fontSize(12)
              .fontColor(this.statusColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('刷新')
            .fontSize(14)
            .fontColor(this.theme.primary)
            .onClick(() => {
              this.net.probe();
            })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.theme.bg)

        Row({ space: 8 }) {
          TextInput({ placeholder: '别名(可选)', text: this.newAlias })
            .fontSize(13)
            .fontColor(this.theme.ink)
            .placeholderColor(this.theme.muted)
            .backgroundColor(this.theme.bg)
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
            .backgroundColor(this.theme.bg)
            .borderRadius(12)
            .height(38)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.newUrl = v;
            })
          Button('添加')
            .fontSize(13)
            .fontColor(this.theme.ink)
            .backgroundColor(this.theme.primary)
            .borderRadius(16)
            .onClick(() => {
              this.net.addProfile(this.newAlias, this.newUrl).then(() => {
                this.newAlias = '';
                this.newUrl = '';
              });
            })
        }
        .width('100%')

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
                .fontColor(this.theme.primary)
                .onClick(() => {
                  this.net.setCurrent(p.id);
                })
            } else {
              Text('✓ 当前')
                .fontSize(12)
                .fontColor(this.theme.primary)
            }
            Text('✕')
              .fontSize(13)
              .fontColor(this.theme.muted)
              .padding(4)
              .onClick(() => {
                this.net.removeProfile(p.id);
              })
          }
          .width('100%')
          .padding(10)
          .borderRadius(12)
          .backgroundColor(this.theme.bg)
        })

        Row() {
          Column({ space: 2 }) {
            Text('播放历史')
              .fontSize(16)
              .fontColor(this.theme.ink)
            Text('自动记录最近播放,上限 500 条')
              .fontSize(12)
              .fontColor(this.theme.muted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('清空')
            .fontSize(14)
            .fontColor(this.theme.ink)
            .backgroundColor(this.theme.secondary)
            .borderRadius(18)
            .onClick(() => {
              playlistsViewModel.clearHistory();
            })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.theme.bg)

        Row() {
          Column({ space: 2 }) {
            Text('主题')
              .fontSize(16)
              .fontColor(this.theme.ink)
            Text(this.theme.isDark ? '深色 · 跟随系统' : '浅色 · 跟随系统')
              .fontSize(12)
              .fontColor(this.theme.muted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(this.theme.isDark ? '🌙' : '☀️')
            .fontSize(16)
            .fontColor(this.theme.muted)
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
