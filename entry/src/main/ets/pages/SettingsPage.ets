import { ThemeService } from '../service/theme/ThemeService';

/** 设置页(导入/背景图/服务器配置入口在对应 issue 填充) */
@Component
export struct SettingsPage {
  @Prop theme: ThemeService;

  build() {
    Column({ space: 16 }) {
      Text('设置')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
        .width('100%')
      Column({ space: 8 }) {
        Text('设置项陆续到位')
          .fontSize(18)
          .fontColor(this.theme.ink)
        Text('导入管理、背景图与取色、服务器配置、扫描、主题')
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
