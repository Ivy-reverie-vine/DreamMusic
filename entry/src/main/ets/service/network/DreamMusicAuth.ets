import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { ApiClient, ApiError } from './ApiClient';
import { LibraryStore } from '../library/LibraryStore';

const PREF_NAME = 'ivy_net';
const KEY_SESSION = 'dm_session';
const KEY_API_KEY = 'dm_api_key';
const KEY_USERNAME = 'dm_username';
const KEY_BOUND = 'dm_bound';
const KEY_BIND_INVALID = 'dm_bind_invalid';
const KEY_BANNED = 'dm_banned';
const PREFIX = '/dreammusic/api/v1';
const QR_DIR = 'qr';

/** /auth/me 返回的用户对象(按 API-DreamMusic.md §3,字段防御性可选) */
export interface DreamUser {
  id: number;
  username: string;
  status: string;
  bound: boolean;
  bindInvalid: boolean;
}

/** /auth/me 响应信封 */
interface MeEnvelope {
  code?: number;
  data?: DreamUser;
}

/** /auth/api-key 响应 */
interface ApiKeyData {
  apiKey?: string;
}

interface ApiKeyEnvelope {
  code?: number;
  data?: ApiKeyData;
}

/** /auth/login 响应信封(data 为公开用户对象) */
interface LoginEnvelope {
  code?: number;
  data?: object;
}

/** 注册/登录请求体 */
interface RegisterBody {
  username: string;
  password: string;
  inviteCode: string;
}

interface LoginBody {
  username: string;
  password: string;
}

/** login/qr/create 响应 */
interface QrCreateData {
  qrimg?: string;
}

interface QrCreateEnvelope {
  code?: number;
  data?: QrCreateData;
}

/** login/qr/key 响应 */
interface QrKeyData {
  unikey?: string;
}

interface QrKeyEnvelope {
  data?: QrKeyData;
}

/** 通用 {code} 响应(QR 轮询) */
interface CodeEnvelope {
  code?: number;
}

interface QrStartResult {
  unikey: string;
  qrimgPath: string;
}

/**
 * DreamMusic 中间层账户会话(API-DreamMusic.md,8/16 接入):
 * 注册/登录 → 会话 Cookie(dm_session)+ X-API-Key 双通道;QR 扫码绑定网易云账号;
 * 转发类接口带 X-API-Key,/auth/* 带 Cookie。
 */
export class DreamMusicAuth {
  /** 当前服务器 Profile 的中间层 base(含 /dreammusic/api/v1 前缀) */
  static async base(context: common.Context): Promise<string> {
    const profiles = await LibraryStore.getInstance().listProfiles();
    for (let i = 0; i < profiles.length; i++) {
      const p = profiles[i];
      if (p.isCurrent) {
        return p.url + PREFIX;
      }
    }
    throw new Error('未配置 DreamMusic 中间层服务器,请先在设置中添加');
  }

  static isLoggedIn(context: common.Context): boolean {
    return DreamMusicAuth.load(context, KEY_SESSION) !== '';
  }

  static username(context: common.Context): string {
    return DreamMusicAuth.load(context, KEY_USERNAME);
  }

  static isBound(context: common.Context): boolean {
    return DreamMusicAuth.load(context, KEY_BOUND) === '1';
  }

  static isBindInvalid(context: common.Context): boolean {
    return DreamMusicAuth.load(context, KEY_BIND_INVALID) === '1';
  }

  static isBanned(context: common.Context): boolean {
    return DreamMusicAuth.load(context, KEY_BANNED) === '1';
  }

  /** 注册(邀请码)成功后自动登录 */
  static async register(context: common.Context, username: string, password: string,
    inviteCode: string): Promise<void> {
    const base = await DreamMusicAuth.base(context);
    const body: RegisterBody = {
      username: username,
      password: password,
      inviteCode: inviteCode
    };
    const empty: Record<string, string> = {};
    await ApiClient.postJson(base, '/auth/register', body, empty);
    await DreamMusicAuth.login(context, username, password);
  }

  /** 登录:解析 Set-Cookie 存会话,并获取 API Key */
  static async login(context: common.Context, username: string, password: string): Promise<void> {
    const base = await DreamMusicAuth.base(context);
    const body: LoginBody = {
      username: username,
      password: password
    };
    const empty: Record<string, string> = {};
    const res = await ApiClient.postJson(base, '/auth/login', body, empty);
    const env = res.body as LoginEnvelope;
    if (env.code !== undefined && env.code !== 200) {
      throw new Error('登录失败');
    }
    const cookie = DreamMusicAuth.setCookieFrom(res.headers);
    if (cookie === '') {
      throw new Error('登录成功但未返回会话 Cookie');
    }
    DreamMusicAuth.save(context, KEY_SESSION, cookie);
    DreamMusicAuth.save(context, KEY_USERNAME, username);
    await DreamMusicAuth.refreshApiKey(context);
    await DreamMusicAuth.me(context);
  }

  /** 用会话 Cookie 拉 /auth/me,刷新绑定/封禁状态 */
  static async me(context: common.Context): Promise<DreamUser | null> {
    if (!DreamMusicAuth.isLoggedIn(context)) {
      return null;
    }
    const base = await DreamMusicAuth.base(context);
    const res = await ApiClient.getJson(base, '/auth/me', {},
      DreamMusicAuth.cookieHeader(context));
    const env = res.body as MeEnvelope;
    const user = env.data;
    if (user === undefined || user === null) {
      return null;
    }
    DreamMusicAuth.applyUser(context, user);
    return user;
  }

  /** 用户对象 → 本地绑定/封禁状态 */
  private static applyUser(context: common.Context, user: DreamUser): void {
    DreamMusicAuth.save(context, KEY_BOUND, user.bound ? '1' : '0');
    DreamMusicAuth.save(context, KEY_BIND_INVALID, user.bindInvalid ? '1' : '0');
    DreamMusicAuth.save(context, KEY_BANNED, user.status === 'banned' ? '1' : '0');
    if (user.username !== '') {
      DreamMusicAuth.save(context, KEY_USERNAME, user.username);
    }
  }

  /** 会话 Cookie → API Key(转发类接口凭证) */
  static async refreshApiKey(context: common.Context): Promise<string> {
    const base = await DreamMusicAuth.base(context);
    const res = await ApiClient.getJson(base, '/auth/api-key', {},
      DreamMusicAuth.cookieHeader(context));
    const env = res.body as ApiKeyEnvelope;
    const key = env.data !== undefined && env.data.apiKey !== undefined ? env.data.apiKey : '';
    if (key === '') {
      throw new Error('获取 API Key 失败');
    }
    DreamMusicAuth.save(context, KEY_API_KEY, key);
    return key;
  }

  /** 返回可用 API Key;未登录时抛可读错误 */
  static async ensureApiKey(context: common.Context): Promise<string> {
    if (!DreamMusicAuth.isLoggedIn(context)) {
      throw new ApiError('NEED_LOGIN', '请先在设置中登录并获取 API Key');
    }
    let key = DreamMusicAuth.load(context, KEY_API_KEY);
    if (key === '') {
      key = await DreamMusicAuth.refreshApiKey(context);
    }
    return key;
  }

  /** 退出登录:通知服务端销毁会话并清本地 */
  static async logout(context: common.Context): Promise<void> {
    if (DreamMusicAuth.isLoggedIn(context)) {
      try {
        const base = await DreamMusicAuth.base(context);
        const emptyBody: Record<string, string> = {};
        await ApiClient.postJson(base, '/auth/logout', emptyBody,
          DreamMusicAuth.cookieHeader(context));
      } catch (err) {
        // 服务端登出失败也继续清本地
      }
    }
    DreamMusicAuth.save(context, KEY_SESSION, '');
    DreamMusicAuth.save(context, KEY_API_KEY, '');
    DreamMusicAuth.save(context, KEY_USERNAME, '');
    DreamMusicAuth.save(context, KEY_BOUND, '0');
    DreamMusicAuth.save(context, KEY_BIND_INVALID, '0');
    DreamMusicAuth.save(context, KEY_BANNED, '0');
  }

  /**
   * 连接探测(ADR-0003 请求驱动):GET /auth/me。
   * 返回: 'online' 中间层可达且已登录;'online-not-logged' 可达未登录;'offline' 不可达。
   */
  static async ping(context: common.Context): Promise<string> {
    try {
      const base = await DreamMusicAuth.base(context);
      const headers: Record<string, string> = {};
      if (DreamMusicAuth.isLoggedIn(context)) {
        headers['Cookie'] = 'dm_session=' + DreamMusicAuth.load(context, KEY_SESSION);
      }
      const res = await ApiClient.getJson(base, '/auth/me', {}, headers);
      const env = res.body as MeEnvelope;
      const user = env.data;
      if (user !== undefined && user !== null) {
        DreamMusicAuth.applyUser(context, user);
      }
      return 'online';
    } catch (err) {
      if (err instanceof ApiError && (err.code === 'UNAUTHORIZED' || err.code === 'FORBIDDEN')) {
        return err.code === 'UNAUTHORIZED' ? 'online-not-logged' : 'online';
      }
      return 'offline';
    }
  }

  /** QR 绑定:拿 key + 生成二维码图片(返回沙箱绝对路径) */
  static async qrStart(context: common.Context): Promise<QrStartResult> {
    const base = await DreamMusicAuth.base(context);
    const key = await DreamMusicAuth.ensureApiKey(context);
    const headers: Record<string, string> = { 'X-API-Key': key };
    const keyRes = await ApiClient.getJson(base, '/login/qr/key', {}, headers);
    const keyEnv = keyRes.body as QrKeyEnvelope;
    const unikey = keyEnv.data !== undefined && keyEnv.data.unikey !== undefined
      ? keyEnv.data.unikey : '';
    if (unikey === '') {
      throw new Error('获取二维码 key 失败');
    }
    const params: Record<string, string> = {};
    params['key'] = unikey;
    params['qrimg'] = 'true';
    const createRes = await ApiClient.getJson(base, '/login/qr/create', params, headers);
    const createEnv = createRes.body as QrCreateEnvelope;
    const qrimg = createEnv.data !== undefined && createEnv.data.qrimg !== undefined
      ? createEnv.data.qrimg : '';
    if (qrimg === '') {
      throw new Error('生成二维码失败');
    }
    const path = await DreamMusicAuth.saveQrPng(context, qrimg);
    return { unikey: unikey, qrimgPath: path };
  }

  /** 轮询扫码结果:801 等待 / 802 已扫待确认 / 800 过期 / 803 成功(成功后刷新绑定态) */
  static async qrCheck(context: common.Context, unikey: string): Promise<number> {
    const base = await DreamMusicAuth.base(context);
    const key = await DreamMusicAuth.ensureApiKey(context);
    const params: Record<string, string> = {};
    params['key'] = unikey;
    params['timestamp'] = String(Date.now());
    const headers: Record<string, string> = {};
    headers['X-API-Key'] = key;
    const res = await ApiClient.getJson(base, '/login/qr/check', params, headers);
    const env = res.body as CodeEnvelope;
    const code = env.code !== undefined ? env.code : 0;
    if (code === 803) {
      await DreamMusicAuth.me(context);
    }
    return code;
  }

  private static setCookieFrom(headers: Record<string, string>): string {
    const raw = headers['set-cookie'] !== undefined ? headers['set-cookie'] : '';
    if (raw === '') {
      return '';
    }
    const first = raw.split(';')[0];
    const eq = first.indexOf('=');
    if (eq <= 0) {
      return '';
    }
    return first.substring(eq + 1);
  }

  private static cookieHeader(context: common.Context): Record<string, string> {
    const out: Record<string, string> = {};
    out['Cookie'] = 'dm_session=' + DreamMusicAuth.load(context, KEY_SESSION);
    return out;
  }

  /** base64 PNG → 沙箱 qr/qr.png(Image 以 file:// 显示) */
  private static async saveQrPng(context: common.Context, qrimg: string): Promise<string> {
    let b64 = qrimg;
    const comma = b64.indexOf(',');
    if (comma >= 0) {
      b64 = b64.substring(comma + 1);
    }
    const helper = new util.Base64Helper();
    const bytes = helper.decodeSync(b64);
    const dir = context.filesDir + '/' + QR_DIR;
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
    const path = dir + '/qr.png';
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path);
    }
    const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
      fileIo.writeSync(f.fd, buf);
    } finally {
      fileIo.closeSync(f.fd);
    }
    return path;
  }

  private static load(context: common.Context, key: string): string {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      return prefs.getSync(key, '') as string;
    } catch (err) {
      return '';
    }
  }

  private static save(context: common.Context, key: string, value: string): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.putSync(key, value);
      prefs.flush();
    } catch (err) {
      // 持久化失败静默
    }
  }
}
