# api-enhanced 项目调研笔记

> 用途: 本项目(本地音乐播放器)未来的网络能力来源。当前阶段**只预留接口**,不实现在线功能。

## 项目定位

- GitHub: [NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)
- 性质: 网易云音乐 Node.js API 服务(Fork 自原版 NeteaseCloudMusicApi v4.28.0,半重构 + 增强,持续维护)
- npm 包: [@neteasecloudmusicapienhanced/api](https://www.npmjs.com/package/@neteasecloudmusicapienhanced/api)
- 典型部署形态: 跑在用户自己的电脑上,局域网内供设备访问(正好符合本项目的"连接我的电脑"场景)

## 与本项目相关的关键点

### 1. 连接状态(ADR-0003,8/16 起取代 /health 探活)

- ✅ 已核实: api-enhanced 的 README(用户提供本地副本 `api-enhanced-README.md`)**没有 `/health` 端点**。
- ✅ 8/16 用户拍板: **不给服务端补端点**,连接状态改为真实业务请求驱动(ADR-0003),不再主动探活、不再 15s 轮询;设置页手动"刷新"以轻量请求 `/search/hot` 验证。

### 2. 部署与网络(已核实 README + 用户确认)

- ✅ 默认端口 **3000**;`node app.js` 启动,`PORT` 环境变量可改;要求 Node.js 22+,pnpm
- ✅ 默认**纯 HTTP**,README 无内置 HTTPS
- ✅ **用户实际部署形态(已确认)**: 用户有域名,通过 **Cloudflare Tunnel(cloudflared)** 暴露 api-enhanced → 公网 HTTPS、证书由 Cloudflare 签发(公网可信,鸿蒙端走系统信任链,**无需 caPath 自签证书**)
- ✅ 相关环境变量: CORS_ALLOW_ORIGIN / ENABLE_PROXY / ENABLE_RANDOM_CN_IP / ENABLE_GENERAL_UNBLOCK / ENABLE_FLAC / SELECT_MAX_BR / FOLLOW_SOURCE_ORDER
- ✅ 在线文档: https://neteasecloudmusicapienhanced.js.org/
- ❓ 是否保留局域网直连 http://IP:3000 作为备选配置——待确认

### 3. 后续可能用到的能力(仅预留,不实现)

- 搜索、歌曲详情、歌词(`/lyric`)、歌曲播放地址、登录状态等(README 列出的登录/歌单/搜索/歌词/云盘等能力)
- 本应用当前只做"连接状态管理 + 通用 HTTP 网关 + 服务器配置",不调用任何具体业务端点

## 待办核实清单

1. ✅ api-enhanced 无 `/health` → 已定:客户端契约 `GET /health`,服务端后续由我们补端点
2. ✅ HTTPS 落地方式: Cloudflare Tunnel 域名,公网证书,无需 caPath;是否保留 LAN 直连待确认
3. ❓ api-enhanced 本地 clone 的路径(后续改它加 /health 要用)
