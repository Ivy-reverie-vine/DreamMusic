import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LibraryStore } from '../service/library/LibraryStore';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { ThemeService, ThemeMode } from '../service/theme/ThemeService';
import { networkViewModel } from '../viewmodel/NetworkViewModel';
import { queueViewModel } from '../viewmodel/QueueViewModel';
import { playerViewModel } from '../viewmodel/PlayerViewModel';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 主题:默认深色(issue-12 定稿)
    ThemeService.getInstance().applyMode(ThemeMode.DARK, true);
    // 内置背景图预设恢复(issue-14 定稿:固定图,持久化索引)
    ThemeService.getInstance().applyPresetBg(ThemeService.loadBgIndex(this.context));
    // 后台播控会话初始化(issue-07,真机验证)
    BackgroundPlayback.getInstance().init(this.context);
    // 音乐库存储初始化 + 启动增量扫描(issue-02/04,真机验证)
    LibraryStore.getInstance().init(this.context).then(() => {
      return LibraryScanService.scan(this.context);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'LibraryStore', 'init/scan failed: %{public}s', err.message);
    });
    // 启动健康检查(ADR-0002:启动时探活 + 每 15s 轮询,应用级生命周期)
    networkViewModel.load().then(() => {
      networkViewModel.startPolling();
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统深浅色切换即时生效(仅"跟随系统"模式响应)
    ThemeService.getInstance().applyMode(ThemeService.getInstance().mode,
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onBackground(): void {
    // 切后台落盘队列进度(issue-13 修复:断点续播不再依赖暂停)
    queueViewModel.persistNow(playerViewModel.positionMs);
  }

  onDestroy(): void {
    queueViewModel.persistNow(playerViewModel.positionMs);
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
}