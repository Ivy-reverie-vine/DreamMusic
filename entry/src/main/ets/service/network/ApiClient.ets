import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { normalizeBaseUrl } from './HealthStateMachine';

const DOMAIN = 0x0000;
const TAG = 'ApiClient';
const JSON_TIMEOUT_MS = 15000;
const DOWNLOAD_TIMEOUT_MS = 120000;
const EMPTY_HEADERS: Record<string, string> = {};

/** dataReceiveProgress 回调载荷(API 10+,SDK d.ts 核实) */
interface ReceiveProgressInfo {
  receiveSize: number;
  totalSize: number;
}

/** 业务响应统一信封(auth 自有接口 {code,data}/{code,message};转发类透传上游) */
interface Envelope {
  code?: number;
  message?: string;
  data?: object;
}

/** JSON 响应:body + 归一化小写响应头(登录取 Set-Cookie 用) */
export interface ApiJsonResult {
  body: object;
  headers: Record<string, string>;
}

/** 业务请求错误:code 供 301(绑定失效)/401/403/404/502 等特殊处理 */
export class ApiError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * 统一 HTTP 网关(DreamMusic 中间层,API-DreamMusic.md):
 * 转发类接口带 X-API-Key 请求头,/auth/* 带 Cookie;统一错误映射(401/403/404/502/301)。
 * API 对照 SDK d.ts 核实:dataReceive/dataReceiveProgress 事件、HttpRequestOptions。
 */
export class ApiClient {
  /** GET JSON(headers 如 {'X-API-Key': key} 或 {'Cookie': 'dm_session=...'}) */
  static async getJson(baseUrl: string, path: string, params: Record<string, string>,
    headers: Record<string, string>): Promise<ApiJsonResult> {
    const url = ApiClient.buildUrl(baseUrl, path, params);
    const client = http.createHttp();
    try {
      const resp = await client.request(url, {
        method: http.RequestMethod.GET,
        header: ApiClient.toHeader(headers),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: JSON_TIMEOUT_MS,
        readTimeout: JSON_TIMEOUT_MS
      });
      return ApiClient.parseJsonResponse(resp);
    } catch (err) {
      if (err instanceof ApiError) {
        throw err;
      }
      const e = err as Error;
      hilog.debug(DOMAIN, TAG, 'getJson failed: %{public}s', e.message);
      throw new ApiError('NETWORK', '网络请求失败:' + e.message);
    } finally {
      client.destroy();
    }
  }

  /** POST JSON(注册/登录/登出等 auth 接口;body 为普通对象) */
  static async postJson(baseUrl: string, path: string, body: object,
    headers: Record<string, string>): Promise<ApiJsonResult> {
    const client = http.createHttp();
    try {
      const resp = await client.request(normalizeBaseUrl(baseUrl) + path, {
        method: http.RequestMethod.POST,
        header: ApiClient.toHeader(headers),
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: JSON_TIMEOUT_MS,
        readTimeout: JSON_TIMEOUT_MS
      });
      return ApiClient.parseJsonResponse(resp);
    } catch (err) {
      if (err instanceof ApiError) {
        throw err;
      }
      const e = err as Error;
      hilog.debug(DOMAIN, TAG, 'postJson failed: %{public}s', e.message);
      throw new ApiError('NETWORK', '网络请求失败:' + e.message);
    } finally {
      client.destroy();
    }
  }

  /** DELETE(下载任务清理等) */
  static async deleteJson(baseUrl: string, path: string,
    headers: Record<string, string>): Promise<ApiJsonResult> {
    const client = http.createHttp();
    try {
      const resp = await client.request(normalizeBaseUrl(baseUrl) + path, {
        method: http.RequestMethod.DELETE,
        header: ApiClient.toHeader(headers),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: JSON_TIMEOUT_MS,
        readTimeout: JSON_TIMEOUT_MS
      });
      return ApiClient.parseJsonResponse(resp);
    } catch (err) {
      if (err instanceof ApiError) {
        throw err;
      }
      const e = err as Error;
      throw new ApiError('NETWORK', '网络请求失败:' + e.message);
    } finally {
      client.destroy();
    }
  }

  /**
   * 下载二进制到沙箱文件;onProgress 0-100(基于 dataReceiveProgress,API 10+)。
   * 8/16 修复:流式下载必须用 requestInStream(普通 request 不会触发 dataReceive,文件会写 0 字节),
   * 并对空文件报错,杜绝"入库了但文件是空的"。
   */
  static async download(url: string, destAbsPath: string,
    onProgress: (pct: number) => void,
    headers: Record<string, string> = EMPTY_HEADERS): Promise<void> {
    const client = http.createHttp();
    let fd: number = -1;
    let written: number = 0;
    try {
      if (fileIo.accessSync(destAbsPath)) {
        fileIo.unlinkSync(destAbsPath);
      }
      const file = fileIo.openSync(destAbsPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fd = file.fd;
      client.on('dataReceive', (data: ArrayBuffer) => {
        if (fd >= 0 && data.byteLength > 0) {
          fileIo.writeSync(fd, data);
          written += data.byteLength;
        }
      });
      client.on('dataReceiveProgress', (info: ReceiveProgressInfo) => {
        if (info.totalSize > 0) {
          const pct = Math.min(100, Math.round(info.receiveSize * 100 / info.totalSize));
          onProgress(pct);
        }
      });
      const code = await client.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: ApiClient.toHeader(headers),
        connectTimeout: DOWNLOAD_TIMEOUT_MS,
        readTimeout: DOWNLOAD_TIMEOUT_MS
      });
      if (code < 200 || code >= 300) {
        if (code === 401) {
          throw new ApiError('UNAUTHORIZED', '会话或 API Key 已失效');
        }
        if (code === 403) {
          throw new ApiError('FORBIDDEN', '没有下载权限');
        }
        if (code === 429) {
          throw new ApiError('RATE_LIMIT', '请求过于频繁,请稍后再试');
        }
        if (code === 502) {
          throw new ApiError('UPSTREAM_DOWN', '上游服务暂不可用');
        }
        throw new ApiError('HTTP_' + code, '下载失败(' + code + ')');
      }
      if (written <= 0) {
        throw new ApiError('EMPTY', '下载文件为空,请重试');
      }
      if (fd >= 0) {
        fileIo.closeSync(fd);
        fd = -1;
      }
    } catch (err) {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
          // 关闭失败忽略
        }
        fd = -1;
      }
      try {
        if (fileIo.accessSync(destAbsPath)) {
          fileIo.unlinkSync(destAbsPath);
        }
      } catch (e) {
        // 清理失败忽略
      }
      if (err instanceof ApiError) {
        throw err;
      }
      const e = err as Error;
      hilog.debug(DOMAIN, TAG, 'download failed: %{public}s', e.message);
      throw new ApiError('NETWORK', '下载失败:' + e.message);
    } finally {
      client.destroy();
    }
  }

  /** 2xx 且 JSON 可解析 → 透传 body;否则按 {code,message} 映射错误 */
  private static parseJsonResponse(resp: http.HttpResponse): ApiJsonResult {
    const status = resp.responseCode;
    let parsed: Envelope | null = null;
    const raw = resp.result;
    if (typeof raw === 'string' && raw.length > 0) {
      try {
        parsed = JSON.parse(raw) as Envelope;
      } catch (err) {
        parsed = null;
      }
    } else if (raw !== null && typeof raw === 'object' && !(raw instanceof ArrayBuffer)) {
      parsed = raw as Envelope;
    }
    if (status >= 200 && status < 300) {
      if (parsed === null) {
        throw new ApiError('BAD_JSON', '服务器响应解析失败');
      }
      // 转发类透传上游:HTTP 200 但业务码 301 = 网易云绑定失效
      if (parsed.code === 301) {
        throw new ApiError('BIND_INVALID',
          parsed.message !== undefined && parsed.message !== '' ? parsed.message : '网易云绑定已失效,请重新扫码');
      }
      return { body: parsed as object, headers: ApiClient.normalizeHeaders(resp.header) };
    }
    const msg = parsed !== null && parsed.message !== undefined && parsed.message !== ''
      ? parsed.message
      : '请求失败(' + status + ')';
    if (status === 401) {
      throw new ApiError('UNAUTHORIZED', msg);
    }
    if (status === 403) {
      throw new ApiError('FORBIDDEN', msg);
    }
    if (status === 404) {
      throw new ApiError('NOT_ALLOWED', msg);
    }
    // 梦点不足(下载需 1 梦点,DreamMusic 下载管理器)
    if (status === 402) {
      throw new ApiError('INSUFFICIENT_POINTS',
        msg !== '' && msg !== '请求失败(402)' ? msg : '梦点不足,下载需要 1 梦点');
    }
    // 中间层限流(默认 300 次/分钟/IP,API-DreamMusic.md §5.3)
    if (status === 429) {
      throw new ApiError('RATE_LIMIT',
        msg !== '' && msg !== '请求失败(429)' ? msg : '请求过于频繁,请稍后再试');
    }
    if (status === 502) {
      throw new ApiError('UPSTREAM_DOWN', msg);
    }
    if (parsed !== null && parsed.code === 301) {
      throw new ApiError('BIND_INVALID', msg);
    }
    throw new ApiError('HTTP_' + status, msg);
  }

  /** 响应头对象 → 小写 key 的 Record(Set-Cookie 取用) */
  private static normalizeHeaders(header: Object): Record<string, string> {
    const out: Record<string, string> = {};
    const keys = Object.keys(header);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const v = (header as Record<string, object | string | number>)[k];
      if (typeof v === 'string') {
        out[k.toLowerCase()] = v;
      } else if (v !== undefined && v !== null) {
        out[k.toLowerCase()] = String(v);
      }
    }
    return out;
  }

  private static buildUrl(baseUrl: string, path: string, params: Record<string, string>): string {
    let url = normalizeBaseUrl(baseUrl) + path;
    const parts: string[] = [];
    const keys = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]));
    }
    if (parts.length > 0) {
      url = url + '?' + parts.join('&');
    }
    return url;
  }

  private static toHeader(headers: Record<string, string>): Record<string, string> {
    const out: Record<string, string> = {};
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      out[k] = headers[k];
    }
    if (out['Content-Type'] === undefined) {
      out['Content-Type'] = 'application/json';
    }
    return out;
  }
}
