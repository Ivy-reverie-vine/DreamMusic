import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LibraryStore } from '../service/library/LibraryStore';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { BackgroundPlayback } from '../service/playback/BackgroundPlayback';
import { ThemeService, ThemeMode, BG_PRESETS } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
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
    // 背景恢复(阶段 v2):优先自定义背景(沙箱固定文件,持久化相对路径),无则回退内置预设索引
    const theme = ThemeService.getInstance();
    BackgroundAdapter.restoreIfPresent(this.context, theme).then((restored: boolean) => {
      if (!restored) {
        const bgIndex = ThemeService.loadBgIndex(this.context);
        theme.applyPresetBg(bgIndex);
        if (bgIndex >= 0 && bgIndex < BG_PRESETS.length) {
          BackgroundAdapter.extractPresetColors(this.context, BG_PRESETS[bgIndex].res)
            .then((colors) => {
              theme.applyExtracted(colors.primary, colors.secondary);
            })
            .catch(() => {
              // 取色失败保持当前色
            });
        }
      }
    });
    // 后台播控会话初始化(issue-07,真机验证)
    BackgroundPlayback.getInstance().init(this.context);
    // 音乐库存储初始化 + 启动增量扫描(issue-02/04,真机验证)
    LibraryStore.getInstance().init(this.context).then(() => {
      return Promise.all([
        LibraryScanService.scan(this.context),
        networkViewModel.load()
      ]);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'LibraryStore', 'init/scan failed: %{public}s', err.message);
    });
    // 连接状态加载随库存初始化完成(ADR-0003:请求驱动,不再启动探活与 15s 轮询)
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

    windowStage.loadContent('pages/IndexV2', (err) => {
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
    playerViewModel.checkSleepTimer();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }
}
