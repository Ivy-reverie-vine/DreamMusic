import { ThemeService } from '../service/theme/ThemeService';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { common } from '@kit.AbilityKit';
import { MusicLibraryPage } from './MusicLibraryPage';
import { NowPlayingPage } from './NowPlayingPage';
import { QueuePage } from './QueuePage';
import { PlaylistsPage } from './PlaylistsPage';
import { SettingsPage } from './SettingsPage';

/**
 * 应用主壳:底部玻璃导航 + 五页切换(issue-01)。
 * 沉浸光感点击反馈与真玻璃底栏细节在 issue-00 组件库完善(真机验证)。
 */
@Entry
@Component
struct Index {
  @State theme: ThemeService = ThemeService.getInstance();
  @State current: number = 0;
  private tabs: string[] = ['音乐库', '正在播放', '队列', '歌单', '设置'];

  aboutToAppear(): void {
    // 断点续播恢复(issue-06):还原队列/当前曲/进度为暂停态
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    queueViewModel.restore(ctx);
  }

  @Builder
  PageContent() {
    if (this.current === 0) {
      MusicLibraryPage({ theme: this.theme })
    } else if (this.current === 1) {
      NowPlayingPage({ theme: this.theme })
    } else if (this.current === 2) {
      QueuePage({ theme: this.theme })
    } else if (this.current === 3) {
      PlaylistsPage({ theme: this.theme })
    } else {
      SettingsPage({ theme: this.theme })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景:近黑底(有背景图后由 issue-00 叠图+蒙层)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.bg)

      Column() {
        this.PageContent()
      }
      .width('100%')
      .height('100%')

      // 玻璃底栏:半透明模糊,内容透过可见(DESIGN.md 玻璃底栏规则)
      Row() {
        ForEach(this.tabs, (item: string, index: number) => {
          Column({ space: 2 }) {
            Text(item)
              .fontSize(12)
              .fontColor(index === this.current ? this.theme.primary : this.theme.muted)
              .fontWeight(index === this.current ? FontWeight.Bold : FontWeight.Normal)
            Circle()
              .width(4)
              .height(4)
              .fill(index === this.current ? this.theme.primary : this.theme.transparent)
          }
          .layoutWeight(1)
          .padding({ top: 10, bottom: 10 })
          .onClick(() => {
            this.current = index;
          })
        })
      }
      .width('100%')
      .padding({ bottom: 8 })
      .backgroundColor(this.theme.overlayDim)
      .backgroundBlurStyle(BlurStyle.Thin)
    }
    .width('100%')
    .height('100%')
  }
}
