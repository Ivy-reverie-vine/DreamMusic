# DreamMusic 普通在线播放代理 — 实现笔记

> 记录 IvyReverieMusic 接入 DreamMusic 中间层后的普通在线播放链路、关键决策与真机注意事项。
> 关联: `API-DreamMusic.md`(D:\Blog\docs)、`docs/adr/0003`、`docs/PRD-v2.1` / `PRD-v2.2`。

## 1. 链路与角色

```
鸿蒙应用
  → DreamMusic 中间层(Express,:3001,/dreammusic/api/v1)
  → 鉴权(X-API-Key / dm_session)
  → 白名单 → 注入绑定账号的网易云 cookie
  → api-enhanced(:3000) → 网易云
音频: 中间层只返回普通播放直链(CDN URL),由 AVPlayer 直接播放
```

中间层是"代理+鉴权+注入",**不转发音频字节**；客户端用返回的普通 CDN 直链即时播放，并在后台下载到自己的沙箱入库。

## 2. 下载前链路

| 步骤 | 端点 | 说明 |
| :--- | :--- | :--- |
| 搜索 | `GET /search?keywords&type=1&limit&offset&randomCNIP=true` | 拿网易云歌曲 id / 名称 / 歌手 / 专辑 / 封面 / 时长 |
| 普通在线播放 | `GET /song/url/v1?id&level=exhigh&randomCNIP=true` | 只取普通 CDN 直链;`url` 为空 = 无版权/需会员,客户端不自行解灰 |
| 歌词 | `GET /lyric/new?id&randomCNIP=true` | 取 `lrc.lyric` 或 `yrc.lyric`,播放页显示并落盘为同名 `.lrc` |
| 封面 | 搜索结果 `album.picUrl` | 播放页即时使用远程 URL；下载完成后落盘到 `covers/<songId>.jpg` |

统一要求: 转发请求带 `X-API-Key` 头 + `randomCNIP=true`;不要自己传 `cookie`(中间层注入)。

## 3. 客户端播放边界

1. 点播直接取 `/song/url/v1` 的普通播放 URL，创建瞬态音轨(`id=-neteaseId` + `streamUrl`)交给 AVPlayer，同时启动后台下载。
2. 下载完成后写入 `tracks`，并用正式数据库 ID 原位替换队列中的瞬态 ID；切歌和重启均从本地库解析。
3. 播放页先使用远程封面和在线歌词；下载完成后切换到本地封面与同名 `.lrc`，切歌时用请求序号丢弃旧歌词响应。
4. URL 为空、无版权或普通播放失败时，只提示播放失败；不执行客户端解灰。

> 账户侧对齐(8/16): 设置页账户区新增 梦点余额 / 每日签到(+10,东八区幂等)/ 兑换码 / 平台公告(公开接口);`/auth/*` 现支持 X-API-Key,账户类调用不再依赖会话 Cookie。

## 4. 鉴权与绑定

- 登录/注册(邀请码)→ `dm_session` Cookie + `X-API-Key` 持久化到 `ivy_net` preferences
- 未绑定网易云 → 转发类接口 403「请先绑定网易云账号」;绑定失效 → 业务码 301
- QR 绑定: `login/qr/key` → `login/qr/create?qrimg=true`(base64 → 沙箱 `qr/qr.png`)→ 1.5s 轮询 `login/qr/check`(801/802/800/803)
- 登录门禁可跳过: 本地歌免登录;在线功能触发登录盖层

## 5. 错误映射(ApiClient)

| 码 | 含义 | 处理 |
| :--- | :--- | :--- |
| 401 | 未登录/会话过期/Key 错 | 回登录页或重新登录 |
| 403 | 未绑定/封禁 | 引导 QR 绑定或提示账号状态 |
| 404 | 接口不在白名单 | 提示联系扩展 `API_ALLOWED_PATHS` |
| 429 | 中间层限流(默认 300/分钟/IP) | 稍后再试 |
| 502 | 上游 api-enhanced 不可达 | 提示检查服务器是否运行 |
| code 301 | 网易云绑定失效 | 重新扫码绑定 |
| code 460/503 | 上游风控/过频 | 换 IP 或等待 |

仅 `NETWORK` / `UPSTREAM_DOWN` 视为离线;401/403/301 说明中间层可达,状态保持在线。

## 6. 关键源码

- `service/network/ApiClient.ets` — HTTP 网关(JSON + 错误映射)
- `service/network/DreamMusicAuth.ets` — 账户会话/API Key/QR 绑定
- `service/network/NetEaseApi.ets` — 搜索/普通播放链接/在线歌词
- `viewmodel/NetworkViewModel.ets` — 请求驱动连接状态(ADR-0003)
- `components/OnlineSearchView.ets` / `LoginView.ets` / `QrBindView.ets` — UI

## 7. 真机注意

- 默认服务器配置已内置: `https://nd.ivyreverie.dpdns.org`(首次安装自动写入并设为当前;已有配置不覆盖)
- 服务器 Profile 填**手机可达**的中间层地址(局域网 IP:3001 或公网域名),不是 localhost
- `level=exhigh`(320k),依赖绑定账号的音质权限;无版权歌直链为空
- CDN 播放直链有时效,仅在当前播放会话中使用;无版权歌直链为空
- 二维码 base64 可能带 `data:image/png;base64,` 前缀,解码前需剥离
- 登录/QR 相关请求勿高频(中间层限流 + 上游 2 分钟 URL 缓存)
