# DreamMusic 音乐下载代理 — 实现笔记

> 记录 IvyReverieMusic 接入 DreamMusic 中间层后的在线音乐下载链路、关键决策与真机注意事项。
> 关联: `API-DreamMusic.md`(D:\Blog\docs)、`docs/adr/0003`、`docs/PRD-v2.1` / `PRD-v2.2`。

## 1. 链路与角色

```
鸿蒙应用
  → DreamMusic 中间层(Express,:3001,/dreammusic/api/v1)
  → 鉴权(X-API-Key / dm_session)
  → 白名单 → 注入绑定账号的网易云 cookie
  → api-enhanced(:3000) → 网易云
音频文件: 中间层只返回播放直链(CDN URL),文件由应用直连 CDN 下载进沙箱
```

中间层是"代理+鉴权+注入",**不转发音频字节**;下载阶段应用直连 CDN。

## 2. 下载前链路

| 步骤 | 端点 | 说明 |
| :--- | :--- | :--- |
| 搜索 | `GET /search?keywords&type=1&limit&offset&randomCNIP=true` | 拿网易云歌曲 id / 名称 / 歌手 / 专辑 / 封面 / 时长 |
| 播放链接 | `GET /song/url/v1?id&level=exhigh&randomCNIP=true` | 返回 CDN 直链;`url` 为空 = 无版权/需会员 |
| 歌词 | `GET /lyric/new?id&randomCNIP=true` | 取 `lrc.lyric`,落盘同名 `.lrc`(失败静默) |
| 封面 | 搜索结果 `album.picUrl` | 直连 CDN 下载,落盘 `covers/<id>.jpg`(失败静默) |

统一要求: 转发请求带 `X-API-Key` 头 + `randomCNIP=true`;不要自己传 `cookie`(中间层注入)。

## 3. 下载入库(应用侧)

1. 点播(阶段 v2.3): 先查本地(去重,文件损坏视为未下载)→ 无则取直链 → 瞬态音轨(`id=-neteaseId` + `streamUrl`)**流式即播**(AVPlayer `url` 网络源)→ 同时后台下载
2. 去重: 按 `tracks.netease_id` 查库且文件非空,已存在直接本地播放,不重复下载
3. 音频: `ApiClient.download` 用 `requestInStream`(流式下载专用,普通 request 不触发 dataReceive)直连 CDN,`dataReceive` 分块写文件,`dataReceiveProgress` 上报 0-100%;空文件报错不入库
4. 文件命名: 音频 `music/<neteaseId>.<ext>`(扩展名取直链);封面 `covers/<neteaseId>.jpg`;歌词 `music/<neteaseId>.lrc`
5. 入库: `LibraryStore.insertTrack` + `indexTrackMeta`(专辑/艺术家聚合),`netease_id` 列自动迁移;下载完即与本地音轨同域(队列/断点/收藏/歌单),瞬态流式条目重启不恢复
6. 失败清理: 下载异常删除半成品文件,错误上屏;下载失败不影响正在进行的流式播放

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

- `service/network/ApiClient.ets` — HTTP 网关(JSON + 二进制下载 + 错误映射)
- `service/network/DreamMusicAuth.ets` — 账户会话/API Key/QR 绑定
- `service/network/NetEaseApi.ets` — 搜索/播放链接/歌词
- `service/network/OnlineDownloadService.ets` — 下载→入库→歌词/封面
- `viewmodel/NetworkViewModel.ets` — 请求驱动连接状态(ADR-0003)
- `components/OnlineSearchView.ets` / `LoginView.ets` / `QrBindView.ets` — UI

## 7. 真机注意

- 默认服务器配置已内置: `https://nd.ivyreverie.dpdns.org`(首次安装自动写入并设为当前;已有配置不覆盖)
- 服务器 Profile 填**手机可达**的中间层地址(局域网 IP:3001 或公网域名),不是 localhost
- `level=exhigh`(320k),依赖绑定账号的音质权限;无版权歌直链为空
- CDN 直链有时效,下载后已落盘,不受影响;下载失败会清理半成品
- 二维码 base64 可能带 `data:image/png;base64,` 前缀,解码前需剥离
- 登录/QR 相关请求勿高频(中间层限流 + 上游 2 分钟 URL 缓存)
