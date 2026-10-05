# Issue #33 验收记录

日期：2026-10-06（Asia/Shanghai）。范围 T14 / G7；前置 #29、#31、#32 已独立读回 CLOSED。本票不代表父 #19 或其他目标完成。

## 本轮修复

- 重复点播同一网易资源时，按沙箱目录与歌曲 ID 共用一个下载/入库任务；每次队列选择仍有独立请求身份。失败任务释放占位，后续点播可以重试。旧选择的下载完成仍被队列请求、实际音频引用与 URL 检查拦截。
- 封面补齐及瞬态条目转本地保留恢复凭据与歌词修订号。恢复期间封面替换了展示对象时，恢复使用当前展示对象，保留最新封面。已下载条目的旧流发生错误仍能恢复，下一次队列播放继续读取本地文件。
- Ability 销毁立即撤销播放器请求、原生会话、恢复定时器和歌词请求；冷启动恢复及卡片命令完成后再次清除迟到的暂停态投影。销毁期间的解析、歌词、媒体和下载回调均不能重新激活播放。
- 在线歌单/喜欢列表共用的点播行反馈按播放器请求隔离，旧点播结束不再覆盖新行的状态文字。

## 验收映射

| 条件 | 结果与可复现证据 |
| --- | --- |
| 快切、重复、迟到回调、取消 | `check-online-queue` 执行生产下载逻辑，经受控文件/SQLite 边界验证重复点播仅一次下载/插入、共享失败后重试、迟到下载与行反馈；`check-url-recovery` 验证真实 HTTP 410、重复原生错误去重、恢复中封面更新、切歌/总期限/销毁；`check-playback-recovery` 验证迟到原生创建/初始化/准备/位置/结束；`check-catalog-lyrics` 验证提供方忽略取消时旧词不进入显示或缓存，销毁后保持 IDLE |
| 来源控制与错误分层 | NightDream `proxy.playbackRegression.test.js` 新增 5 项真实 HTTP 回归：禁用/饱和/熔断同时覆盖自动、手动、恢复、歌词；其他来源和旧网易调用继续可用；手动及恢复经过媒体代理并保留 Range，媒体 HTTP 410 独立于可靠完整版解析结果；Meting 节流约束跨手动与恢复请求有效。既有 automatic/manual/otherRecording/catalogLyrics/lrclib/mediaProxy 套件继续覆盖取消、限时、匹配失败、试听/未知、传输及歌词失败 |
| 所有当前点播入口的下载边界 | 源码入口复查：搜索经 `OnlineSearchView → OnlineMusicViewModel`；在线歌单/喜欢列表经 `PlaylistsPage.playOnlineSong → OnlineMusicViewModel`；本地音乐库/歌单/历史与队列经 `QueueViewModel → PlayerViewModel`；手动同录音/其他录音经 PlayerViewModel。前两条统一在确认实际网易音频后才查询/下载网易缓存；后三条不创建网易下载任务。`check-automatic-playback` 执行真实搜索行；`check-online-queue` 执行真实在线歌单行方法（双方在线列表共用）及旧无引用条目，验证网易目录配 QQ 不读/删/写网易库；manual/otherRecording/mediaIdentity 检查 Bilibili 与手动候选 |
| 网易入库、本地和收藏兼容 | `check-online-queue` 使用生产下载/队列逻辑：消费已经解析的网易 URL、单次入库、仅替换所属瞬态条目、保留目录与收藏 ID；缓存命中播放本地文件；本地离线不发解析 HTTP；不同录音不继承收藏。已下载音轨的恢复与下一次本地重播语义分别验证。不新增跨源离线迁移 |
| 系统派生信息和关闭 | `check-covers`、`check-system-playback`、`check-music-forms`、`check-desktop-lyrics`、`check-playback-interactions` 验证主机状态、封面资源归还、系统更新顺序、卡片冷启动/关闭、歌词撤回与队列操作。修正旧封面测试缺少 `audioIntegrity.full` 和旧系统测试缺少 `dispose` 的替身，保持生产门禁 |

## 验证结果

- NightDream：`npm test -- --maxWorkers=2 --minWorkers=2` **53 文件 / 327 项通过**（包括服务端和网页）。新 HTTP 回归 5 项通过；TypeScript/Vite `npm run build` 通过。一个现有网页测试的后台取数记录了本地 :3000 未运行的 ECONNREFUSED，但测试与进程退出均成功。
- 客户端主机检查：`online-queue`、`url-recovery`、`automatic-playback`、`manual-playback`、`other-recording`、`catalog-lyrics`、`media-identity`、`playback-recovery`、`covers`、`system-playback`、`playback-interactions`、`music-forms`、`desktop-lyrics` 共 13 个脚本通过。新增断言执行实际 ArkTS 源码，部分 UI 检查执行 Hvigor 编译产物；HTTP 网关使用真实 Express/鉴权/临时 SQLite。
- HAP：`assembleHap --no-daemon --stacktrace` 通过 ArkTS 检查、打包及本机签名，生成 `entry-default-signed.hap`。保留现有异常处理/弃用告警；未关闭类型检查。
- 两仓库 `git diff --check` 通过。本机 `build-profile.json5` 和原有 `.scratch/` 不纳入提交；本次构建临时日志清理。

可按上面逐一运行 `node scripts/check-<名称>.mjs`；HAP 环境配方见 [构建环境](build-environment.md)。服务端复现说明见 NightDream `docs/playback-regression.md`。

## 验收边界

客户端主机测试控制 HarmonyOS Kit、客户端文件/SQLite 边界及第三方提供方响应；真实 HTTP 410/Range/媒体字节证明请求隔离与传输行为，不能作为自然来源可用率。没有执行本轮鸿蒙真机 AVPlayer、设备 SQLite、后台或锁屏验收；主机系统播控与歌词检查不标为设备验收。既有 #32 原生浏览器证据保留，但不宣称本轮重新执行了原生浏览器或设备测试。
