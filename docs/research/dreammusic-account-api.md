# DreamMusic 账户/积分/下载/公告 API 调研(NightDream 中间层)

> 依据: `D:\DreamMusic\NightDream` 当前服务端源码。本文记录 NightDream 可提供的账户/积分/下载/公告能力；不等同于 HarmonyOS 客户端当前已调用的接口。
> 当前客户端只使用统一入口的普通播放直链并客户端下载入库；NightDream 负责未来新增来源的调度，客户端不直接选择来源。

## 0. 鉴权(重要变化)

`/auth/*` 现在 **Cookie 或 X-API-Key 均可**(`currentUser` 先会话后 Key),仅 `register/login/logout` 与公开的 `announcements` 例外。
→ 鸿蒙端所有账户类调用可统一用 `X-API-Key`,不再依赖会话 Cookie。

## 1. 账户与资料(部分在 App 内已用)

| 端点 | 方法 | 说明 |
| :--- | :--- | :--- |
| `/auth/me` | GET | 用户对象(含 `dreamPoints` / `lastCheckinDate` / `bound` / `bindInvalid` / `neteaseUid`) |
| `/auth/profile` | GET | 资料/统计(playSeconds/playedSongCount/dreamPoints) |
| `/auth/profile` | POST | 改签名 ≤60 字 |
| `/auth/password` | POST | 改密码(成功后所有会话失效) |
| `/auth/avatar` | POST | dataURL/base64 头像(jpg/png/webp ≤2MB,文件头校验) |
| `/auth/sessions` / `revoke` | GET/POST | 会话列表/下线 |

## 2. 梦点与签到

| 端点 | 方法 | 请求 | 返回 data |
| :--- | :--- | :--- | :--- |
| `/auth/checkin` | POST | 无 | `{points, alreadyChecked}` 每日 +10 梦点,东八区自然日幂等 |
| `/auth/points/log` | GET | 无 | 最近 50 条 `{id, delta, balanceAfter, type, note, refId, createdAt}` |

`type` 取值: `checkin` / `song_download` / `download_refund` / `admin_adjust`。

## 3. 下载与扣点(两个入口)

### 3.1 旧入口(直接返回直链)

`POST /auth/points/download` body `{songId, level}`
- 扣 1 梦点,返回 `{url, points, cost: 1, source}`
- 未绑定 → 403;梦点不足 → **402**「梦点不足,下载需要 1 梦点」
- `level` 白名单: `standard / exhigh / lossless / hires`

### 3.2 新下载管理器(推荐对齐)

| 端点 | 方法 | 说明 |
| :--- | :--- | :--- |
| `/auth/downloads` | POST | `{songId, level, songName, artist}` → 扣 1 梦点,后台抓文件落盘,立即返回 `{task, points, message}` |
| `/auth/downloads` | GET | 本人任务列表: `{id, songId, songName, artist, level, status(downloading/ready/failed), received, total, progress, source, fileName, error, ready}` |
| `/auth/downloads/:id/file` | GET | 取已完成文件(仅本人,`ready` 才可),服务端直接下载文件 |
| `/auth/downloads/:id` | DELETE | 删除任务与缓存文件 |

- **失败自动退款**: 抓取失败 → 状态 failed + 回补 1 梦点(`download_refund`)
- 直链解析链: 原曲下载 → unblock → qq/kugou/kuwo/migu 解灰换源(`downloadSource.js`)
- 文件扩展名按 Content-Type/URL 推断(mp3/flac/wav/m4a/ogg/aac)

## 4. 兑换码

| 端点 | 方法 | 鉴权 | 说明 |
| :--- | :--- | :--- | :--- |
| `/auth/redeem` | POST | 用户 | `{code}` → 加梦点,幂等(used_by 唯一);过期 400,无效 404 |
| `/auth/redeem-codes/generate` | POST | admin | `{points, count(1-100), note?, expiresAt?}` → `{codes}` |
| `/auth/redeem-codes` | GET | admin | 最近 100 条 |

## 5. 邀请码

| 端点 | 方法 | 鉴权 | 说明 |
| :--- | :--- | :--- | :--- |
| `/auth/invite-code` | GET | admin | 当前注册邀请码(settings 表优先,兜底 env REGISTER_CODE) |
| `/auth/invite-code` | POST | admin | 修改(4-64 位,立即生效) |

## 6. 公告

| 端点 | 方法 | 鉴权 | 说明 |
| :--- | :--- | :--- | :--- |
| `/auth/announcements` | GET | **公开** | 已发布未过期: `{id, title, content, level(info/maintenance/important), status, createdBy, createdAt, publishedAt, expiresAt}` |
| `/auth/announcements/admin` | GET | admin | 全部(含草稿/归档) |
| `/auth/announcements` | POST | admin | 新建 |
| `/auth/announcements/:id` | POST | admin | 编辑/发布/下线 |
| `/auth/announcements/:id` | DELETE | admin | 归档 |

## 7. 播放统计

`POST /auth/stats` body `{seconds(≤120), songId?}` — 播放中每 30s 上报一次,服务端限幅;用于 `playSeconds/playedSongCount`。

## 8. 限流与错误

- 全 API 内存滑动窗口 **300 次/分钟/IP**(`rateLimit.js`),429 + 无 Retry-After 头
- 登录失败 5 次锁 15 分钟(429「尝试次数过多」)
- 梦点不足 → **402**(现有 ApiClient 未映射,需补)

## 8.1 发消息(Bark 式 webhook,8/16 新增)

| 端点 | 方法 | 请求 | 返回 data |
| :--- | :--- | :--- | :--- |
| `/auth/message` | POST | `{title(≤40), content(≤200)}` | `{points, used, remaining, dailyLimit:3, result(sent/http_xxx/error), detail}` |

- 规则: 扣 **1 梦点**,每日最多 **3 次**(东八区自然日),**失败也扣**(中间服务可能拦截脏话)
- 服务端调用 `GET {messageWebhook}/{encodeURIComponent(title)}/{encodeURIComponent(content)}`(`MESSAGE_WEBHOOK` env 可改,默认 `https://api.chuckfang.com/ivyreverie`),10s 超时
- 记账: `message_logs` 表(result 记录发送结果)+ `dream_point_logs`(type=message_send)+ 审计
- 同步: `/auth/me` 等用户对象新增 `messageToday`,手机与网页看到同一计数(单一事实源)

## 9. App 对齐建议(待拍板)

| 功能 | 建议 | 依赖 |
| :--- | :--- | :--- |
| 梦点/签到 | 设置页账户区显示 `dreamPoints` + 「每日签到 +10」按钮(已签置灰);X-API-Key 调 `/auth/checkin` | 小 |
| 兑换码 | 设置页「兑换码」输入 → `/auth/redeem` → 刷新余额 | 小 |
| 公告 | 登录页或设置页拉 `/auth/announcements` 展示(level 区分样式) | 小 |
| 下载扣点 | 服务端可提供下载管理器(扣点、失败退款、替代源和任务文件);当前 HarmonyOS 客户端未调用该入口，客户端下载仍使用 `/song/url/v1` 返回的普通直链 | 中 |
| 播放统计 | 播放中每 30s 上报 `/auth/stats`(对齐网页) | 小 |
| 402 映射 | ApiClient 补 `RATE_LIMIT` 已有,再补 `INSUFFICIENT_POINTS(402)` 与登录锁定 429 文案 | 小 |
