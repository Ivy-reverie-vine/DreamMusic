import { common } from '@kit.AbilityKit';
import { AccountPlaybackStats, LocalPlaybackStats } from '../model/Entities';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { LibraryStore } from '../service/library/LibraryStore';

export type AccountStatsState = 'unauthenticated' | 'loading' | 'success-zero' |
  'success' | 'stale' | 'unavailable';

/** 统计页唯一编排入口：本机数据独立加载，账户数据失败不阻塞本地内容。 */
@Observed
export class PlaybackStatsViewModel {
  local: LocalPlaybackStats = {
    playRecordCount: 0,
    customPlaylistCount: 0,
    favoriteCount: 0
  };
  account: AccountPlaybackStats = {
    playSeconds: 0,
    playedSongCount: 0,
    syncedAt: 0
  };
  accountState: AccountStatsState = 'unauthenticated';
  accountError: string = '';
  loadingLocal: boolean = false;

  get hasAccountData(): boolean {
    return this.accountState === 'success' || this.accountState === 'success-zero' ||
      this.accountState === 'stale';
  }

  get accountStatusLabel(): string {
    if (this.accountState === 'unauthenticated') { return '登录后同步'; }
    if (this.accountState === 'loading') { return '正在同步'; }
    if (this.accountState === 'unavailable') { return '暂时不可用，请刷新重试'; }
    if (this.accountState === 'stale') { return '暂时无法更新，显示上次成功数据'; }
    return '来自 DreamMusic 账户';
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.loadLocal();
    await this.loadAccount(context);
  }

  async refresh(context: common.UIAbilityContext): Promise<void> {
    await this.load(context);
  }

  private async loadLocal(): Promise<void> {
    this.loadingLocal = true;
    try {
      this.local = await LibraryStore.getInstance().localPlaybackStats();
    } catch (err) {
      // 数据库初始化晚于页面时保留可渲染的零值；启动完成后重新进入会刷新。
    } finally {
      this.loadingLocal = false;
    }
  }

  private async loadAccount(context: common.UIAbilityContext): Promise<void> {
    await DreamMusicAuth.initialize(context);
    if (!DreamMusicAuth.isLoggedIn(context)) {
      this.accountState = 'unauthenticated';
      this.accountError = '';
      return;
    }
    this.accountState = 'loading';
    try {
      const profile = await DreamMusicAuth.profile(context);
      this.account = {
        playSeconds: profile.playSeconds,
        playedSongCount: profile.playedSongCount,
        syncedAt: profile.syncedAt
      };
      this.accountError = '';
      this.accountState = this.account.playSeconds === 0 && this.account.playedSongCount === 0
        ? 'success-zero' : 'success';
    } catch (err) {
      this.accountError = (err as Error).message;
      this.accountState = this.account.syncedAt > 0 ? 'stale' : 'unavailable';
    }
  }
}

export const playbackStatsViewModel: PlaybackStatsViewModel = new PlaybackStatsViewModel();
