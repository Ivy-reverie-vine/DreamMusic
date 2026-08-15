import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LibraryStore } from '../service/library/LibraryStore';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { ThemeService } from '../service/theme/ThemeService';
import { networkViewModel } from '../viewmodel/NetworkViewModel';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 深浅色初始读取(issue-11,跟随系统)
    ThemeService.getInstance().setDarkMode(
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // 后台播控会话初始化(issue-07,真机验证)
    BackgroundPlayback.getInstance().init(this.context);
    // 音乐库存储初始化 + 启动增量扫描(issue-02/04,真机验证)
    LibraryStore.getInstance().init(this.context).then(() => {
      return LibraryScanService.scan(this.context);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'LibraryStore', 'init/scan failed: %{public}s', err.message);
    });
    // 启动健康检查(ADR-0002:启动时探活;code-review 修复)
    networkViewModel.load().then(() => {
      networkViewModel.startPolling();
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统深浅色切换即时生效(issue-11)
    ThemeService.getInstance().setDarkMode(
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}