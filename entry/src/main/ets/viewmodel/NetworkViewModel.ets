import { common } from '@kit.AbilityKit';
import { LibraryStore } from '../service/library/LibraryStore';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { HealthStateMachine, ConnectionStatus, validateProfileUrl } from '../service/network/HealthStateMachine';
import { ServerProfile } from '../model/Entities';

/**
 * 网络状态容器(issue-10 + ADR-0003 重构,8/16):
 * Profile 多配置(DreamMusic 中间层);连接状态改为真实业务请求驱动(ADR-0003,不再 /health 探活、不再 15s 轮询);
 * 设置页手动"刷新"以 GET /auth/me 验证中间层连通并刷新登录/绑定状态。
 */
@Observed
export class NetworkViewModel {
  profiles: ServerProfile[] = [];
  status: ConnectionStatus = ConnectionStatus.OFFLINE;
  statusText: string = '未配置服务器';
  lastCheckAt: number = 0;
  private machine: HealthStateMachine = new HealthStateMachine();
  private probing: boolean = false;

  constructor() {
    this.machine = new HealthStateMachine();
  }

  async load(): Promise<void> {
    this.profiles = await LibraryStore.getInstance().listProfiles();
    if (this.profiles.length === 0) {
      this.status = ConnectionStatus.OFFLINE;
      this.statusText = '未配置服务器';
      return;
    }
    // 已有配置但未标当前 → 自动把第一条设为当前(避免误报"未配置服务器")
    if (this.currentProfile() === null) {
      await LibraryStore.getInstance().setCurrentProfile(this.profiles[0].id);
      this.profiles = await LibraryStore.getInstance().listProfiles();
    }
    // ADR-0003:未发生过业务请求时显示"未检测"
    this.status = ConnectionStatus.OFFLINE;
    this.statusText = '未检测';
  }

  currentProfile(): ServerProfile | null {
    for (const p of this.profiles) {
      if (p.isCurrent) {
        return p;
      }
    }
    return null;
  }

  async addProfile(alias: string, url: string, context: common.Context): Promise<boolean> {
    if (!validateProfileUrl(url)) {
      this.statusText = 'URL 无效(仅支持 http/https)';
      return false;
    }
    await LibraryStore.getInstance().insertProfile(alias.trim() === '' ? url : alias.trim(), url.trim());
    await this.load();
    await this.probe(context);
    return true;
  }

  async setCurrent(id: number, context: common.Context): Promise<void> {
    await LibraryStore.getInstance().setCurrentProfile(id);
    await this.load();
    await this.probe(context);
  }

  async removeProfile(id: number, context: common.Context): Promise<void> {
    await LibraryStore.getInstance().deleteProfile(id);
    await this.load();
    await this.probe(context);
  }

  /** 手动连接验证(设置页"刷新"):GET /auth/me(可带会话 Cookie),失败静默 */
  async probe(context: common.Context): Promise<void> {
    if (this.probing) {
      return;
    }
    const profile = this.currentProfile();
    if (profile === null) {
      this.status = ConnectionStatus.OFFLINE;
      this.statusText = '未配置服务器';
      return;
    }
    this.probing = true;
    this.status = this.machine.beginProbe();
    this.statusText = '检查中…';
    try {
      const state = await DreamMusicAuth.ping(context);
      if (state === 'online') {
        this.status = this.machine.onProbeResult(true);
        this.statusText = '在线';
      } else if (state === 'online-not-logged') {
        this.status = this.machine.onProbeResult(true);
        this.statusText = '在线(未登录)';
      } else {
        this.status = this.machine.onProbeResult(false);
        this.statusText = '离线(服务器未运行)';
      }
    } catch (err) {
      this.status = this.machine.onProbeResult(false);
      this.statusText = '离线';
    }
    this.lastCheckAt = Date.now();
    this.probing = false;
  }

  /** 业务请求成功上报(ADR-0003:请求即探活,搜索/下载调用点使用) */
  markOnline(): void {
    this.status = this.machine.onProbeResult(true);
    this.statusText = '在线';
    this.lastCheckAt = Date.now();
  }

  /** 业务请求失败上报 */
  markOffline(): void {
    this.status = this.machine.onProbeResult(false);
    this.statusText = '离线';
    this.lastCheckAt = Date.now();
  }
}

export const networkViewModel: NetworkViewModel = new NetworkViewModel();
