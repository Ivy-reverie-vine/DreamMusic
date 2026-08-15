/**
 * 连接健康状态机 + Profile URL 校验(纯逻辑,零 Kit 依赖)——issue-10 单测接缝。
 * 契约见 ADR-0002:3s 超时、2xx 且 body 可解析=在线、启动+15s 轮询+手动、三态静默。
 */

export enum ConnectionStatus {
  CHECKING = 'CHECKING',
  ONLINE = 'ONLINE',
  OFFLINE = 'OFFLINE'
}

export class HealthStateMachine {
  private current: ConnectionStatus = ConnectionStatus.OFFLINE;

  get status(): ConnectionStatus {
    return this.current;
  }

  beginProbe(): ConnectionStatus {
    this.current = ConnectionStatus.CHECKING;
    return this.current;
  }

  /** ok:2xx 且响应体可解析 → 在线;超时/连接失败/非 2xx → 离线 */
  onProbeResult(ok: boolean): ConnectionStatus {
    this.current = ok ? ConnectionStatus.ONLINE : ConnectionStatus.OFFLINE;
    return this.current;
  }
}

/** Profile URL 校验:仅允许 http/https 且有主机名 */
export function validateProfileUrl(url: string): boolean {
  if (url.length === 0) {
    return false;
  }
  const lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return false;
  }
  const rest = url.substring(url.indexOf('://') + 3);
  // 去掉路径与结尾斜杠后必须还剩主机部分
  const host = rest.split('/')[0];
  return host.length > 0;
}

/** 归一化 baseUrl:去尾部斜杠,供 /health 拼接 */
export function normalizeBaseUrl(url: string): string {
  const trimmed = url.trim();
  return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
}
