import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { ApiClient, ApiError } from './ApiClient';
import { SecureCredentialStore, SecureReadResult } from './SecureCredentialStore';
import { LibraryStore } from '../library/LibraryStore';
import { shanghaiDateString } from '../../common/DateUtil';
import { normalizeBaseUrl } from './HealthStateMachine';

const PREF_NAME = 'ivy_net';
const KEY_SESSION = 'dm_session';
const KEY_API_KEY = 'dm_api_key';
const KEY_USERNAME = 'dm_username';
const KEY_BOUND = 'dm_bound';
const KEY_BIND_INVALID = 'dm_bind_invalid';
const KEY_BANNED = 'dm_banned';
const KEY_DREAM_POINTS = 'dm_dream_points';
const KEY_CHECKIN_DATE = 'dm_checkin_date';
const KEY_MESSAGE_TODAY = 'dm_message_today';
const KEY_NETEASE_UID = 'dm_netease_uid';
const PREFIX = '/dreammusic/api/v1';
const QR_DIR = 'qr';
const EMPTY_HEADERS: Record<string, string> = {};

/** /auth/me 返回的用户对象(按 API-DreamMusic.md §3,字段防御性可选) */
export interface DreamUser {
  id: number;
  username: string;
  status: string;
  bound: boolean;
  bindInvalid: boolean;
  dreamPoints: number;
  lastCheckinDate: string;
  messageToday: number;
  neteaseUid?: string | null;
  playSeconds?: number;
  playedSongCount?: number;
}

export interface DreamSession {
  token: string;
  username: string;
  createdAt: number;
  expiresAt: number;
  current: boolean;
}

export interface DreamPointLog {
  id: number;
  userId: number;
  delta: number;
  balanceAfter: number;
  type: string;
  note: string | null;
  refId: string | null;
  createdAt: number;
}

/** /auth/me 响应信封 */
interface MeEnvelope {
  code?: number;
  data?: DreamUser;
}

interface SessionsEnvelope {
  data?: DreamSession[];
}

interface PointLogsEnvelope {
  data?: DreamPointLog[];
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

/** /auth/checkin 响应 */
interface CheckinData {
  points?: number;
  alreadyChecked?: boolean;
}

interface CheckinEnvelope {
  data?: CheckinData;
}

/** /auth/redeem 响应 */
interface RedeemData {
  points?: number;
  redeemedPoints?: number;
}

interface RedeemEnvelope {
  data?: RedeemData;
}

/** 平台公告(公开) */
export interface Announcement {
  id: number;
  title: string;
  content: string;
  level: string;
  status: string;
  createdBy: string;
  createdAt: number;
  publishedAt: number | null;
  expiresAt: number | null;
}

interface AnnouncementsEnvelope {
  data?: Announcement[];
}

interface MessageData {
  points?: number;
  used?: number;
  remaining?: number;
  dailyLimit?: number;
  result?: string;
  detail?: string;
}

interface MessageEnvelope {
  data?: MessageData;
}

export interface MessageSendResult {
  points: number;
  used: number;
  remaining: number;
  dailyLimit: number;
  result: string;
  detail: string;
}

export interface CheckinResult {
  points: number;
  alreadyChecked: boolean;
}

export interface RedeemResult {
  points: number;
  redeemed: number;
}

/**
 * DreamMusic 中间层账户会话(API-DreamMusic.md,8/16 接入):
 * 注册/登录 → 会话 Cookie(dm_session)+ X-API-Key 双通道;QR 扫码绑定网易云账号;
 * 转发类接口带 X-API-Key,/auth/* 带 Cookie。
 */
export class DreamMusicAuth {
  private static credentialInit: Promise<void> | null = null;
  private static credentialReady: boolean = false;
  private static credentialCache: Record<string, string> = {};

  /** 启动时加载安全凭证;UI 只在此之后读取同步 getter。 */
  static async initialize(context: common.Context): Promise<void> {
    if (DreamMusicAuth.credentialInit !== null) {
      await DreamMusicAuth.credentialInit;
      return;
    }
    DreamMusicAuth.credentialInit = DreamMusicAuth.initializeCredentials(context);
    await DreamMusicAuth.credentialInit;
  }

  private static async initializeCredentials(context: common.Context): Promise<void> {
    const session = await SecureCredentialStore.read(KEY_SESSION);
    const apiKey = await SecureCredentialStore.read(KEY_API_KEY);
    DreamMusicAuth.credentialCache[KEY_SESSION] =
      await DreamMusicAuth.migrateCredential(context, KEY_SESSION, session);
    DreamMusicAuth.credentialCache[KEY_API_KEY] =
      await DreamMusicAuth.migrateCredential(context, KEY_API_KEY, apiKey);
    DreamMusicAuth.credentialReady = session.available && apiKey.available;
    if (!DreamMusicAuth.credentialReady) {
      DreamMusicAuth.credentialInit = null;
    }
  }

  private static async migrateCredential(context: common.Context, key: string,
    secure: SecureReadResult): Promise<string> {
    // AssetStoreKit 不可用时不回退到普通 preferences,避免重新暴露凭证。
    if (!secure.available) {
      return '';
    }
    if (secure.value !== '') {
      DreamMusicAuth.clearLegacy(context, key);
      return secure.value;
    }
    const legacy = DreamMusicAuth.loadLegacy(context, key);
    if (legacy === '') {
      return '';
    }
    try {
      await SecureCredentialStore.write(key, legacy);
      DreamMusicAuth.clearLegacy(context, key);
      return legacy;
    } catch (err) {
      // 下次启动重试迁移;本次不把明文凭证放进内存。
      return '';
    }
  }

  /** 当前服务器 Profile 的中间层 base(含 /dreammusic/api/v1 前缀) */
  static async base(context: common.Context): Promise<string> {
    const profiles = await LibraryStore.getInstance().listProfiles();
    for (let i = 0; i < profiles.length; i++) {
      const p = profiles[i];
      if (p.isCurrent) {
        return normalizeBaseUrl(p.url) + PREFIX;
      }
    }
    throw new Error('未配置 DreamMusic 中间层服务器,请先在设置中添加');
  }

  static isLoggedIn(context: common.Context): boolean {
    return DreamMusicAuth.credentialCache[KEY_SESSION] !== undefined &&
      DreamMusicAuth.credentialCache[KEY_SESSION] !== '';
  }

  static username(context: common.Context): string {
    return DreamMusicAuth.loadLegacy(context, KEY_USERNAME);
  }

  static isBound(context: common.Context): boolean {
    return DreamMusicAuth.loadLegacy(context, KEY_BOUND) === '1';
  }

  static isBindInvalid(context: common.Context): boolean {
    return DreamMusicAuth.loadLegacy(context, KEY_BIND_INVALID) === '1';
  }

  static isBanned(context: common.Context): boolean {
    return DreamMusicAuth.loadLegacy(context, KEY_BANNED) === '1';
  }

  static dreamPoints(context: common.Context): number {
    const raw = DreamMusicAuth.loadLegacy(context, KEY_DREAM_POINTS);
    const n = parseInt(raw, 10);
    return Number.isNaN(n) ? 0 : n;
  }

  static lastCheckinDate(context: common.Context): string {
    return DreamMusicAuth.loadLegacy(context, KEY_CHECKIN_DATE);
  }

  static messageToday(context: common.Context): number {
    const n = parseInt(DreamMusicAuth.loadLegacy(context, KEY_MESSAGE_TODAY), 10);
    return Number.isNaN(n) ? 0 : n;
  }

  static neteaseUid(context: common.Context): string {
    return DreamMusicAuth.loadLegacy(context, KEY_NETEASE_UID);
  }

  /** 今日是否已签到(东八区自然日) */
  static checkedInToday(context: common.Context): boolean {
    return DreamMusicAuth.lastCheckinDate(context) === shanghaiDateString();
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
    await DreamMusicAuth.initialize(context);
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
    await DreamMusicAuth.saveCredential(KEY_SESSION, cookie);
    DreamMusicAuth.saveLegacy(context, KEY_USERNAME, username);
    await DreamMusicAuth.refreshApiKey(context);
    await DreamMusicAuth.me(context);
  }

  /** 用会话 Cookie 拉 /auth/me,刷新绑定/封禁状态 */
  static async me(context: common.Context): Promise<DreamUser | null> {
    await DreamMusicAuth.initialize(context);
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
    DreamMusicAuth.saveLegacy(context, KEY_BOUND, user.bound ? '1' : '0');
    DreamMusicAuth.saveLegacy(context, KEY_BIND_INVALID, user.bindInvalid ? '1' : '0');
    DreamMusicAuth.saveLegacy(context, KEY_BANNED, user.status === 'banned' ? '1' : '0');
    if (user.username !== '') {
      DreamMusicAuth.saveLegacy(context, KEY_USERNAME, user.username);
    }
    if (user.dreamPoints !== undefined && !Number.isNaN(user.dreamPoints)) {
      DreamMusicAuth.saveLegacy(context, KEY_DREAM_POINTS, String(user.dreamPoints));
    }
    if (user.lastCheckinDate !== undefined && user.lastCheckinDate !== null) {
      DreamMusicAuth.saveLegacy(context, KEY_CHECKIN_DATE, user.lastCheckinDate);
    }
    if (user.messageToday !== undefined && !Number.isNaN(user.messageToday)) {
      DreamMusicAuth.saveLegacy(context, KEY_MESSAGE_TODAY, String(user.messageToday));
    }
    if (user.neteaseUid !== undefined && user.neteaseUid !== null) {
      DreamMusicAuth.saveLegacy(context, KEY_NETEASE_UID, String(user.neteaseUid));
    }
  }

  /** 会话 Cookie → API Key(转发类接口凭证) */
  static async refreshApiKey(context: common.Context): Promise<string> {
    await DreamMusicAuth.initialize(context);
    const base = await DreamMusicAuth.base(context);
    const res = await ApiClient.getJson(base, '/auth/api-key', {},
      DreamMusicAuth.cookieHeader(context));
    const env = res.body as ApiKeyEnvelope;
    const key = env.data !== undefined && env.data.apiKey !== undefined ? env.data.apiKey : '';
    if (key === '') {
      throw new Error('获取 API Key 失败');
    }
    await DreamMusicAuth.saveCredential(KEY_API_KEY, key);
    return key;
  }

  /** 返回可用 API Key;未登录时抛可读错误 */
  static async ensureApiKey(context: common.Context): Promise<string> {
    await DreamMusicAuth.initialize(context);
    if (!DreamMusicAuth.isLoggedIn(context)) {
      throw new ApiError('NEED_LOGIN', '请先在设置中登录并获取 API Key');
    }
    let key = DreamMusicAuth.credentialCache[KEY_API_KEY] !== undefined
      ? DreamMusicAuth.credentialCache[KEY_API_KEY] : '';
    if (key === '') {
      key = await DreamMusicAuth.refreshApiKey(context);
    }
    return key;
  }

  /**
   * API Key 失效时只做一次重新获取;重试仍 401 则清理本地会话。
   * callback 内不得自行循环重试,避免多个页面形成请求风暴。
   */
  static async withApiKey<T>(context: common.Context,
    callback: (headers: Record<string, string>) => Promise<T>): Promise<T> {
    const key = await DreamMusicAuth.ensureApiKey(context);
    const headers: Record<string, string> = { 'X-API-Key': key };
    try {
      return await callback(headers);
    } catch (err) {
      if (!(err instanceof ApiError) || err.code !== 'UNAUTHORIZED') {
        if (err instanceof Error) {
          throw err;
        }
        throw new Error('请求失败');
      }
      DreamMusicAuth.credentialCache[KEY_API_KEY] = '';
      try {
        const refreshed = await DreamMusicAuth.refreshApiKey(context);
        const retryHeaders: Record<string, string> = { 'X-API-Key': refreshed };
        return await callback(retryHeaders);
      } catch (retryErr) {
        if (retryErr instanceof ApiError && retryErr.code === 'UNAUTHORIZED') {
          await DreamMusicAuth.clearLocalAuthState(context);
          throw new ApiError('NEED_LOGIN', '会话已失效,请重新登录');
        }
        if (retryErr instanceof Error) {
          throw retryErr;
        }
        throw new Error('请求失败');
      }
    }
  }

  /** 退出登录:通知服务端销毁会话并清本地 */
  static async logout(context: common.Context): Promise<void> {
    await DreamMusicAuth.initialize(context);
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
    await DreamMusicAuth.clearLocalAuthState(context);
  }

  /**
   * 连接探测(ADR-0003 请求驱动):GET /auth/me。
   * 返回: 'online' 中间层可达且已登录;'online-not-logged' 可达未登录;'offline' 不可达。
   */
  static async ping(context: common.Context): Promise<string> {
    await DreamMusicAuth.initialize(context);
    try {
      const base = await DreamMusicAuth.base(context);
      const headers: Record<string, string> = {};
      if (DreamMusicAuth.isLoggedIn(context)) {
        headers['Cookie'] = 'dm_session=' + DreamMusicAuth.credentialCache[KEY_SESSION];
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
    return DreamMusicAuth.withApiKey<QrStartResult>(context,
      async (headers: Record<string, string>) => {
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
      const result: QrStartResult = { unikey: unikey, qrimgPath: path };
      return result;
    });
  }

  /** 轮询扫码结果:801 等待 / 802 已扫待确认 / 800 过期 / 803 成功(成功后刷新绑定态) */
  static async qrCheck(context: common.Context, unikey: string): Promise<number> {
    const base = await DreamMusicAuth.base(context);
    return DreamMusicAuth.withApiKey<number>(context,
      async (headers: Record<string, string>) => {
      const params: Record<string, string> = {};
      params['key'] = unikey;
      params['timestamp'] = String(Date.now());
      const res = await ApiClient.getJson(base, '/login/qr/check', params, headers);
      const env = res.body as CodeEnvelope;
      const code = env.code !== undefined ? env.code : 0;
      if (code === 803) {
        await DreamMusicAuth.me(context);
      }
      return code;
    });
  }

  /** 每日签到(+10 梦点,东八区自然日幂等) */
  static async checkin(context: common.Context): Promise<CheckinResult> {
    const base = await DreamMusicAuth.base(context);
    const emptyBody: Record<string, string> = {};
    return DreamMusicAuth.withApiKey(context, async (headers: Record<string, string>) => {
      const res = await ApiClient.postJson(base, '/auth/checkin', emptyBody, headers);
      const env = res.body as CheckinEnvelope;
      const data = env.data;
      const points = data !== undefined && data.points !== undefined ? data.points : 0;
      const already = data !== undefined && data.alreadyChecked === true;
      DreamMusicAuth.saveLegacy(context, KEY_DREAM_POINTS, String(points));
      DreamMusicAuth.saveLegacy(context, KEY_CHECKIN_DATE, shanghaiDateString());
      const result: CheckinResult = { points: points, alreadyChecked: already };
      return result;
    });
  }

  /** 兑换码加梦点(幂等) */
  static async redeem(context: common.Context, code: string): Promise<RedeemResult> {
    const base = await DreamMusicAuth.base(context);
    const body: Record<string, string> = {};
    body['code'] = code.trim();
    return DreamMusicAuth.withApiKey<RedeemResult>(context,
      async (headers: Record<string, string>) => {
      const res = await ApiClient.postJson(base, '/auth/redeem', body, headers);
      const env = res.body as RedeemEnvelope;
      const data = env.data;
      const points = data !== undefined && data.points !== undefined ? data.points : 0;
      const redeemed = data !== undefined && data.redeemedPoints !== undefined ? data.redeemedPoints : 0;
      DreamMusicAuth.saveLegacy(context, KEY_DREAM_POINTS, String(points));
      const result: RedeemResult = { points: points, redeemed: redeemed };
      return result;
    });
  }

  /** 平台公告(公开,无需登录) */
  static async announcements(context: common.Context): Promise<Announcement[]> {
    const base = await DreamMusicAuth.base(context);
    const res = await ApiClient.getJson(base, '/auth/announcements', {}, EMPTY_HEADERS);
    const env = res.body as AnnouncementsEnvelope;
    return env.data !== undefined && env.data !== null ? env.data : [];
  }

  /** 在线会话列表，供设置页的会话管理展示。 */
  static async sessions(context: common.Context): Promise<DreamSession[]> {
    const base = await DreamMusicAuth.base(context);
    const res = await DreamMusicAuth.withApiKey(context,
      (headers: Record<string, string>) => {
        return ApiClient.getJson(base, '/auth/sessions', {}, headers);
      });
    const env = res.body as SessionsEnvelope;
    return env.data !== undefined && env.data !== null ? env.data : [];
  }

  /** 撤销指定会话;token 只用于本次请求,不落盘、不写日志。 */
  static async revokeSession(context: common.Context, token: string): Promise<void> {
    const base = await DreamMusicAuth.base(context);
    const body: Record<string, string> = {};
    body['token'] = token;
    await DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
      return ApiClient.postJson(base, '/auth/sessions/revoke', body, headers).then(() => {
      });
    });
  }

  /** 梦点流水，供设置页展示最近记录。 */
  static async pointLogs(context: common.Context): Promise<DreamPointLog[]> {
    const base = await DreamMusicAuth.base(context);
    const res = await DreamMusicAuth.withApiKey(context,
      (headers: Record<string, string>) => {
        return ApiClient.getJson(base, '/auth/points/log', {}, headers);
      });
    const env = res.body as PointLogsEnvelope;
    return env.data !== undefined && env.data !== null ? env.data : [];
  }

  /** 播放统计上报;服务端再限幅到 120 秒。 */
  static async reportStats(context: common.Context, seconds: number,
    songId: number = 0): Promise<void> {
    const safeSeconds = Math.max(1, Math.min(120, Math.floor(seconds)));
    const base = await DreamMusicAuth.base(context);
    const body: Record<string, number> = {};
    body['seconds'] = safeSeconds;
    if (songId > 0) {
      body['songId'] = songId;
    }
    await DreamMusicAuth.withApiKey(context, (headers: Record<string, string>) => {
      return ApiClient.postJson(base, '/auth/stats', body, headers).then(() => {
      });
    });
  }

  /** 发消息(Bark 式 webhook):扣 1 梦点,每日最多 3 次,失败也扣;次数/扣点由中间层统一记账 */
  static async sendMessage(context: common.Context, title: string,
    content: string): Promise<MessageSendResult> {
    const base = await DreamMusicAuth.base(context);
    const body: Record<string, string> = {};
    body['title'] = title.trim();
    body['content'] = content.trim();
    return DreamMusicAuth.withApiKey<MessageSendResult>(context,
      async (headers: Record<string, string>) => {
      const res = await ApiClient.postJson(base, '/auth/message', body, headers);
      const env = res.body as MessageEnvelope;
      const data = env.data;
      const result: MessageSendResult = {
        points: data !== undefined && data.points !== undefined ? data.points : 0,
        used: data !== undefined && data.used !== undefined ? data.used : 0,
        remaining: data !== undefined && data.remaining !== undefined ? data.remaining : 0,
        dailyLimit: data !== undefined && data.dailyLimit !== undefined ? data.dailyLimit : 3,
        result: data !== undefined && data.result !== undefined ? data.result : '',
        detail: data !== undefined && data.detail !== undefined ? data.detail : ''
      };
      DreamMusicAuth.saveLegacy(context, KEY_DREAM_POINTS, String(result.points));
      DreamMusicAuth.saveLegacy(context, KEY_MESSAGE_TODAY, String(result.used));
      return result;
    });
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
    out['Cookie'] = 'dm_session=' + DreamMusicAuth.credentialCache[KEY_SESSION];
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

  private static loadLegacy(context: common.Context, key: string): string {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      return prefs.getSync(key, '') as string;
    } catch (err) {
      return '';
    }
  }

  private static saveLegacy(context: common.Context, key: string, value: string): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.putSync(key, value);
      prefs.flush();
    } catch (err) {
      // 持久化失败静默
    }
  }

  private static clearLegacy(context: common.Context, key: string): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      prefs.deleteSync(key);
      prefs.flush();
    } catch (err) {
      // 清理失败不影响安全凭证使用,下次启动继续清理
    }
  }

  private static async saveCredential(key: string, value: string): Promise<void> {
    await SecureCredentialStore.write(key, value);
    DreamMusicAuth.credentialCache[key] = value;
  }

  private static async clearLocalCredentials(context: common.Context): Promise<void> {
    try {
      await SecureCredentialStore.remove(KEY_SESSION);
    } catch (err) {
      // 退出登录仍清理内存态;下次启动可再次尝试删除
    }
    try {
      await SecureCredentialStore.remove(KEY_API_KEY);
    } catch (err) {
      // 退出登录仍清理内存态;下次启动可再次尝试删除
    }
    DreamMusicAuth.credentialCache[KEY_SESSION] = '';
    DreamMusicAuth.credentialCache[KEY_API_KEY] = '';
    DreamMusicAuth.clearLegacy(context, KEY_SESSION);
    DreamMusicAuth.clearLegacy(context, KEY_API_KEY);
  }

  private static async clearLocalAuthState(context: common.Context): Promise<void> {
    await DreamMusicAuth.clearLocalCredentials(context);
    DreamMusicAuth.saveLegacy(context, KEY_USERNAME, '');
    DreamMusicAuth.saveLegacy(context, KEY_BOUND, '0');
    DreamMusicAuth.saveLegacy(context, KEY_BIND_INVALID, '0');
    DreamMusicAuth.saveLegacy(context, KEY_BANNED, '0');
    DreamMusicAuth.saveLegacy(context, KEY_NETEASE_UID, '');
  }
}
