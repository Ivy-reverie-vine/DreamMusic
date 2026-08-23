import { common } from '@kit.AbilityKit';
import {
  Announcement, DreamMusicAuth, DreamPointLog
} from '../service/network/DreamMusicAuth';

/** “我的”所有账户卡片共享的状态源，避免页面各自读取旧的本地快照。 */
@Observed
export class AccountViewModel {
  loggedIn: boolean = false;
  username: string = '';
  bound: boolean = false;
  bindInvalid: boolean = false;
  points: number = 0;
  checkedIn: boolean = false;
  messageUsed: number = 0;
  messageRemaining: number = 3;
  announcements: Announcement[] = [];
  pointLogs: DreamPointLog[] = [];
  loading: boolean = false;
  action: string = '';
  statusText: string = '';

  async refresh(context: common.UIAbilityContext): Promise<void> {
    this.loading = true;
    try {
      await DreamMusicAuth.initialize(context);
      this.loggedIn = DreamMusicAuth.isLoggedIn(context);
      if (!this.loggedIn) {
        this.applyLocal(context);
        return;
      }
      const user = await DreamMusicAuth.me(context);
      if (user === null) {
        this.loggedIn = false;
        this.applyLocal(context);
        return;
      }
      this.username = user.username;
      this.bound = user.bound;
      this.bindInvalid = user.bindInvalid;
      this.points = user.dreamPoints;
      this.checkedIn = DreamMusicAuth.checkedInToday(context);
      this.messageUsed = user.messageToday;
      this.messageRemaining = Math.max(0, 3 - user.messageToday);
    } catch (err) {
      this.statusText = '账户状态暂时不可用';
      this.applyLocal(context);
    } finally {
      this.loading = false;
    }
  }

  private applyLocal(context: common.UIAbilityContext): void {
    this.loggedIn = DreamMusicAuth.isLoggedIn(context);
    this.username = DreamMusicAuth.username(context);
    this.bound = DreamMusicAuth.isBound(context);
    this.bindInvalid = DreamMusicAuth.isBindInvalid(context);
    this.points = DreamMusicAuth.dreamPoints(context);
    this.checkedIn = DreamMusicAuth.checkedInToday(context);
    this.messageUsed = DreamMusicAuth.messageToday(context);
    this.messageRemaining = Math.max(0, 3 - this.messageUsed);
  }

  async loadAnnouncements(context: common.UIAbilityContext): Promise<void> {
    try {
      this.announcements = await DreamMusicAuth.announcements(context);
    } catch (err) {
      this.statusText = '公告暂时无法加载';
      this.announcements = [];
    }
  }

  async checkin(context: common.UIAbilityContext): Promise<void> {
    if (!this.loggedIn || this.action !== '' || this.checkedIn) {
      return;
    }
    this.action = 'checkin';
    try {
      const result = await DreamMusicAuth.checkin(context);
      this.points = result.points;
      this.checkedIn = true;
      this.statusText = result.alreadyChecked ? '今日已签到过' : '签到成功 +10 梦点';
    } catch (err) {
      this.statusText = '签到失败: ' + (err as Error).message;
    } finally {
      this.action = '';
    }
  }

  async redeem(context: common.UIAbilityContext, code: string): Promise<void> {
    if (!this.loggedIn || code.trim() === '' || this.action !== '') {
      return;
    }
    this.action = 'redeem';
    try {
      const result = await DreamMusicAuth.redeem(context, code);
      this.points = result.points;
      this.statusText = '兑换成功 +' + result.redeemed + ' 梦点';
    } catch (err) {
      this.statusText = '兑换失败: ' + (err as Error).message;
    } finally {
      this.action = '';
    }
  }

  async sendMessage(context: common.UIAbilityContext, title: string,
    content: string): Promise<void> {
    if (!this.loggedIn || title.trim() === '' || content.trim() === '' || this.action !== '') {
      this.statusText = '标题和内容不能为空';
      return;
    }
    this.action = 'message';
    try {
      const result = await DreamMusicAuth.sendMessage(context, title, content);
      this.points = result.points;
      this.messageUsed = result.used;
      this.messageRemaining = result.remaining;
      const reason = result.detail !== '' ? result.detail : result.result;
      this.statusText = result.result === 'sent'
        ? '消息已发送，今日剩余 ' + result.remaining + ' 次'
        : '已扣 1 梦点，发送未送达: ' + reason;
    } catch (err) {
      this.statusText = '发送失败: ' + (err as Error).message;
    } finally {
      this.action = '';
    }
  }

  async loadPointLogs(context: common.UIAbilityContext): Promise<void> {
    if (!this.loggedIn) {
      return;
    }
    try {
      this.pointLogs = await DreamMusicAuth.pointLogs(context);
    } catch (err) {
      this.statusText = '梦点流水暂时无法加载';
      this.pointLogs = [];
    }
  }
}

export const accountViewModel: AccountViewModel = new AccountViewModel();
