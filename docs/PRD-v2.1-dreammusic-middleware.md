# PRD v2.1: 接入 DreamMusic 中间层(账户 + API Key + QR 绑定)

- 阶段: 8/16 追加轮次(取代 PRD-v2 中"匿名游客登录"方案)
- 依据: `D:/Blog/docs/API-DreamMusic.md`(中间层 API 契约)+ 服务端代码核验(D:\Blog\server)
- 目标环境: HarmonyOS 6.1 / API 23 / ArkTS / 真机 phone

## Background

上一轮在线功能按"直连 api-enhanced + 匿名登录"实现;8/16 用户提供 DreamMusic 中间层 API 文档并拍板**改走中间层**:

```
应用 → DreamMusic 中间层(/dreammusic/api/v1,:3001)
      → 鉴权(会话 Cookie 或 X-API-Key)
      → 白名单 → 注入绑定账号的网易云 cookie → api-enhanced(:3000)
```

## Scope

### 做

1. **账户会话**: 设置页新增"账户"区;注册(邀请码默认 `dreammusic`)/ 登录 → 存 `dm_session` Cookie + 换取并持久化 `X-API-Key`;退出登录
2. **QR 扫码绑定**: 登录后"绑定网易云账号" → `login/qr/key` → `login/qr/create?qrimg=true`(base64 落盘显示)→ 1.5s 轮询 `login/qr/check`(801/802/800/803);成功后刷新绑定态
3. **转发接口改道**: 搜索 `/search`、播放链接 `/song/url/v1`、歌词 `/lyric/new`,统一 `X-API-Key` 头 + `randomCNIP=true`;应用自动拼接 `/dreammusic/api/v1` 前缀
4. **音质**: `level=exhigh`(与 DreamMusic 网页端默认一致;8/16 匿名登录方案作废后按绑定账号音质)
5. **连接状态**: 探测改为 `GET /auth/me`(带会话 Cookie;401=可达未登录,403=可达,网络/502=离线);错误码 301(绑定失效)/403(未绑定)透出可读提示
6. 保留上一轮全部本地侧能力(下载入库/去重/在线歌词落盘 .lrc/断点/收藏/歌单)

### 不做

- 账号找回/改密/头像/签到/播放统计(中间层已有,本轮不接入)
- 音质选择器 UI(固定 exhigh,后续轮次)
- 解灰换源 `/song/url/match`、在线歌单同步、榜单/推荐/评论/云盘/电台

## Decisions

| # | 主题 | 决策 |
| :-: | :--- | :--- |
| 1 | 服务器 Profile | 存中间层根地址(如 `http://IP:3001` / `https://域名`),应用内部拼接 `/dreammusic/api/v1` |
| 2 | 凭证存储 | `ivy_net` preferences:dm_session / dm_api_key / 用户名 / 绑定态;转发用 API Key,/auth/* 用 Cookie |
| 3 | 绑定流程 | 设置页 QR sheet:base64 解码 → 沙箱 `qr/qr.png` → Image 显示;轮询状态上屏,过期可重新生成 |
| 4 | 错误映射 | HTTP 401/403/404/429/502 + 业务码 301/460/503 统一 ApiError(429=中间层限流,8/16 文档更新补充);仅 NETWORK/UPSTREAM_DOWN 视为离线 |

## Acceptance Criteria(真机)

- [ ] 设置页填中间层地址 → 登录/注册成功,账户区显示用户名与绑定态
- [ ] 未绑定点搜索 → 可读提示"请先绑定网易云账号";设置页 QR 扫码绑定后搜索可用
- [ ] 搜索 → 下载 → 播放全链路经中间层;下载的歌离线可播
- [ ] 绑定失效(code 301)时提示重新扫码;断网时中间层状态显示离线,本地功能不受影响

## Further Notes

- 服务端(D:\Blog\server)未改动;客户端仅做接口对接
- 相关文档: CONTEXT.md(账户会话/绑定/中间层术语已更新)、docs/adr/0003(连接状态请求驱动沿用)
