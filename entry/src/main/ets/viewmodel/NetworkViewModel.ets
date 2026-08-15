import { LibraryStore } from '../service/library/LibraryStore';
import { HealthClient } from '../service/network/HealthClient';
import { HealthStateMachine, ConnectionStatus, validateProfileUrl } from '../service/network/HealthStateMachine';
import { ServerProfile } from '../model/Entities';

const POLL_INTERVAL_MS = 15000;

/**
 * 网络预留状态容器(issue-10):Profile 多配置 + /health 健康检查三态。
 * 轮询:启动后立即一次 + 每 15s;失败静默,仅状态展示。
 */
@Observed
export class NetworkViewModel {
  profiles: ServerProfile[] = [];
  status: ConnectionStatus = ConnectionStatus.OFFLINE;
  statusText: string = '未配置服务器';
  lastCheckAt: number = 0;
  private machine: HealthStateMachine = new HealthStateMachine();
  private timerId: number = -1;
  private probing: boolean = false;

  constructor() {
    this.machine = new HealthStateMachine();
  }

  async load(): Promise<void> {
    this.profiles = await LibraryStore.getInstance().listProfiles();
    if (this.currentProfile() === null) {
      this.status = ConnectionStatus.OFFLINE;
      this.statusText = '未配置服务器';
    }
  }

  currentProfile(): ServerProfile | null {
    for (const p of this.profiles) {
      if (p.isCurrent) {
        return p;
      }
    }
    return null;
  }

  async addProfile(alias: string, url: string): Promise<boolean> {
    if (!validateProfileUrl(url)) {
      this.statusText = 'URL 无效(仅支持 http/https)';
      return false;
    }
    await LibraryStore.getInstance().insertProfile(alias.trim() === '' ? url : alias.trim(), url.trim());
    await this.load();
    await this.probe();
    return true;
  }

  async setCurrent(id: number): Promise<void> {
    await LibraryStore.getInstance().setCurrentProfile(id);
    await this.load();
    await this.probe();
  }

  async removeProfile(id: number): Promise<void> {
    await LibraryStore.getInstance().deleteProfile(id);
    await this.load();
    await this.probe();
  }

  /** 手动/定时探活:检查中 → 在线/离线,失败静默 */
  async probe(): Promise<void> {
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
    const ok = await HealthClient.probe(profile.url);
    this.status = this.machine.onProbeResult(ok);
    this.statusText = ok ? '在线' : '离线';
    this.lastCheckAt = Date.now();
    this.probing = false;
  }

  startPolling(): void {
    this.probe();
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      this.probe();
    }, POLL_INTERVAL_MS);
  }

  stopPolling(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}

export const networkViewModel: NetworkViewModel = new NetworkViewModel();
