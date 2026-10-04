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
import { CoverArtService } from '../service/cover/CoverArtService';
import { playbackLaunch, PLAYBACK_DESTINATION_KEY, PLAYLIST_ID_KEY } from '../model/PlaybackLaunch';
import { PlaylistFormStore } from '../service/form/PlaylistFormStore';
import { rpc } from '@kit.IPCKit';
import { playbackRuntime } from '../viewmodel/PlaybackRuntime';
import { MUSIC_FORM_METHOD, MusicCardCommand } from '../model/MusicCard';

class CardCommandReply implements rpc.Parcelable {
  marshalling(data: rpc.MessageSequence): boolean { data.writeInt(0); return true; }
  unmarshalling(data: rpc.MessageSequence): boolean { data.readInt(); return true; }
}

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handlePlaybackWant(want);
    this.callee.on(MUSIC_FORM_METHOD, (data: rpc.MessageSequence) => {
      try {
        const params = JSON.parse(data.readString()) as MusicCardCommand;
        if (typeof params.command === 'string') { playbackRuntime.dispatch(this.context, params.command); }
      } catch (err) {}
      return new CardCommandReply();
    });
    playbackRuntime.ensureReady(this.context).catch((err: Error) => {
      hilog.error(DOMAIN, 'PlaybackRuntime', 'restore failed: %{public}s', err.message);
    });
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
        const backgroundStamp = theme.bgStamp;
        if (bgIndex >= 0 && bgIndex < BG_PRESETS.length) {
          BackgroundAdapter.extractPresetColors(this.context, BG_PRESETS[bgIndex].res)
            .then((colors) => {
              if (theme.bgStamp === backgroundStamp) {
                theme.applyBackgroundColors(colors);
              }
            })
            .catch(() => {
              // 取色失败保持当前色
            });
        }
      }
    });
    // 后台播控会话初始化(issue-07,真机验证)
    BackgroundPlayback.getInstance().init(this.context).then(() => {
      playerViewModel.refreshBackground();
    });
    // 音乐库存储初始化 + 启动增量扫描(issue-02/04,真机验证)
    LibraryStore.getInstance().init(this.context).then(() => {
      LibraryStore.getInstance().onPlaylistContentChanged = () => {
        PlaylistFormStore.refreshAll(this.context).catch(() => {});
      };
      PlaylistFormStore.refreshAll(this.context).catch(() => {});
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

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handlePlaybackWant(want);
  }

  private handlePlaybackWant(want: Want): void {
    const destination = want.parameters?.[PLAYBACK_DESTINATION_KEY];
    if (typeof destination === 'string') {
      const playlistId = want.parameters?.[PLAYLIST_ID_KEY];
      playbackLaunch.request(destination, playlistId === undefined ? 0 : Number(playlistId));
    }
  }

  onBackground(): void {
    // 切后台落盘队列进度(issue-13 修复:断点续播不再依赖暂停)
    queueViewModel.persistNow(playerViewModel.positionMs);
  }

  onDestroy(): void {
    this.callee.off(MUSIC_FORM_METHOD);
    queueViewModel.persistNow(playerViewModel.positionMs);
    // 在系统媒体信息提交/会话销毁后归还引用；仍被 UI 借用的图延迟到节点卸载再释放。
    playbackRuntime.dispose().then(() => BackgroundPlayback.getInstance().release()).finally(() => {
      CoverArtService.getInstance().clear();
    });
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
    BackgroundPlayback.getInstance().init(this.context).then(() => {
      playerViewModel.refreshBackground();
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }
}
