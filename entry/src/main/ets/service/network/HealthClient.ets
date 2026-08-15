import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { normalizeBaseUrl } from './HealthStateMachine';

const DOMAIN = 0x0000;
const TAG = 'HealthClient';
const TIMEOUT_MS = 3000;

/**
 * HTTP 适配层(issue-10,真机验证项):
 * 唯一允许的端点是 GET {base}/health(ADR-0002);3s 超时;
 * 2xx 且响应体可解析 → true,其余(超时/连接失败/非 2xx/空体)→ false。
 */
export class HealthClient {
  static async probe(baseUrl: string): Promise<boolean> {
    const url = normalizeBaseUrl(baseUrl) + '/health';
    const client = http.createHttp();
    try {
      const resp = await client.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        return false;
      }
      const body = resp.result;
      if (typeof body === 'string') {
        return body.length > 0;
      }
      return body !== null && body !== undefined;
    } catch (err) {
      const e = err as Error;
      hilog.debug(DOMAIN, TAG, 'probe failed: %{public}s', e.message);
      return false;
    } finally {
      client.destroy();
    }
  }
}
