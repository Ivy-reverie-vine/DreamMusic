# Issue #20：贯通目录、音频和歌词身份并兼容旧播放

日期：2026-10-04（Asia/Shanghai）。范围：[#20 / T01](https://github.com/Ivy-reverie-vine/DreamMusic/issues/20)，对应 #19 的 G1 首个兼容切片；不代表 G1 其他工单或多源总规格完成。

## 实现

- NightDream v2 搜索/详情、播放与歌词响应兼容增加 `catalogRef`、`playbackRef`、`lyricsRef`、`playbackSource`、`lyricsSource`。三个引用仍是具体资源的 version 1 `mediaRef`；本切片单来源时均指向原资源。v1 响应保持原状，不重建注册表、代理或适配器，不引入自动换源。
- 实际 `MusicOrchestrator` 按具体引用分派；旧 `id` / `ids` / `source` 提示不改写资源。非法引用、未启用来源、不支持能力和当前未实现的跨资源身份组合保留 HTTP 状态并返回机器可读 `errorCode`。
- HarmonyOS 的真实 `NetEaseApi` 搜索接收新身份，`PlayerViewModel` 消费播放解析身份并校验目录一致，`LyricsViewModel` 消费歌词引用并公开实际歌词来源；详情/封面使用目录引用。正在播放页显示实际音频来源。旧 v2 响应缺少新字段时使用原 `mediaRef`，旧 v1/本地播放入口继续保留。
- 原目录标题、歌手、已有封面不被播放响应或迟到元数据改写；网易文件入库替换和已缓存文件命中也保留本次目录展示。非网易音频不进入网易数字 ID 下载链。首次在线准备阶段已能请求歌词，不再依赖 URL 先被写入 Track。
- Web 搜索、播放器恢复和正在播放消费三种角色；播放身份可随队列恢复，短时 URL 继续丢弃后重解析。已有目录封面优先，切歌后旧封面/歌词响应失效。
- `/music-test.html` 的已有单来源试听增加目录/音频/歌词引用、原目录封面、实际音频与歌词来源；歌词/详情独立获取，不阻塞音频起播。

## 验收证据

| Issue 验收项 | 本轮证据 | 结果 |
| --- | --- | --- |
| 现有来源经真实 NightDream HTTP 搜索、详情、播放、歌词往返，客户端实际消费 | `NightDream/server/proxy.identity.test.js` 使用真实 Express、认证/会话、临时服务端 SQLite、注册表、编排和网易/Meting adapter；`scripts/check-media-identity.mjs` 将真实 ArkTS API/队列/播放器/歌词接到同一 HTTP 入口 | 通过 |
| 具体资源保持原义，分别表达角色，非法/不支持引用明确失败 | HTTP 覆盖缺失/格式/空 ID/资源类型、未知与关闭来源、不支持歌词、冲突身份、旧 ID 覆盖攻击；空 URL/上游失败不换源 | 通过 |
| 展示原目录元数据和音频来源，迟到元数据不改选择 | ArkTS 公开 `currentTrack`、`state`、队列和歌词状态断言；覆盖后台本地替换、缓存命中、切歌迟到解析/封面；Web 公开 state、DOM 封面、来源、歌词及切歌迟到响应 | 通过 |
| 旧单来源、鉴权与网易绑定兼容 | 同一 HTTP 入口覆盖未登录/错误 API Key、v1 未绑定 403、真实登录会话/API Key、二维码 803 保存并剥离 Cookie、v1 原响应、绑定失效 301；全量旧回归通过 | 通过 |
| 兼容扩展，不重建基础设施，不加入自动换源 | 沿用 `createProxyRouter` / `MusicOrchestrator` / adapters；新字段可选；未改上游项目；不同资源组合明确拒绝 | 通过 |
| HTTP 身份往返、客户端公开播放状态、可操作单来源演示 | 上述新回归；已有启动器 `--source api-enhanced --check` 通过，演示页面接通四个接口与新身份 | 通过；真实试听本轮未执行 |

## 检查与构建

- NightDream `npm test`：**40 个文件、196 个测试通过**。包括新增 HTTP 6 项及 Web 3 项；覆盖原鉴权、来源开关/熔断、媒体代理、下载管理、播放器和歌词回归。
- NightDream `npm run build`：TypeScript 与 Vite 生产构建通过。新增 Web 测试最初的类型不完整已修正，随后该文件 3 项与生产构建重跑通过。
- HarmonyOS 主机：`node scripts/check-media-identity.mjs`、`check-playback-recovery.mjs`、`check-lyrics.mjs`、`check-covers.mjs`、`check-desktop-lyrics.mjs` 均通过。桌面歌词旧 fixture 曾把本地文件设为负 ID；本轮修正为符合真实模型的本地正 ID / 瞬态在线负 ID 后通过。
- API 23 HAP：设置 `$env:DEVECO_SDK_HOME='D:\DreamMusic\.devEco-sdk-compat'`，运行 `D:\DevEco\tools\hvigor\bin\hvigorw.bat assembleHap --no-daemon --stacktrace`，最终 `BUILD SUCCESSFUL in 3 s 613 ms`（增量复用此前本轮 CompileArkTS/PackageHap/SignHap 成功结果）。存在工程既有弃用/可能抛异常提示，未改 SDK 或构建配置。
- 签名产物：`entry/build/default/outputs/default/entry-default-signed.hap`；SHA256：`3A804B668F4C7C9656398168094AF6C99AE2A7FD93FD7904FE25669719F4A2C5`。
- 修改文件 `git diff --check` 通过；测试临时服务与服务端 SQLite 目录关闭并清理，本次构建临时日志在完成记录后删除。

## 单来源演示与证据边界

运行 `D:\DreamMusic\Start-NightDream.cmd --source api-enhanced`，登录后搜索歌曲，点击“获取链接并试听”。页面可查看三种引用、原目录信息、音频和歌词来源；观察音频 `playing` 状态和进度。Meting 可使用 `--source tencent`，沿用已有环境文件配置。

本轮 `--check` 只核实 Node、依赖、来源配置和端口，没有启动生产服务或使用真实音乐账号。HTTP 测试的业务编排、适配器和服务端认证/SQLite 是真实实现，仅第三方请求受控；ArkTS 客户端 Kit、客户端存储与下载边界使用替身。Web 测试检查状态与展示，未证明真实音频解码、进度推进或浏览器视觉；HAP 构建也不代表设备安装和播放验收。

真实平台试听、HarmonyOS AVPlayer/后台/锁屏和全曲完整性继续归后续 G7/G8。本票不实现聚合搜索、同录音匹配、跨源回退、Bilibili 或 LRCLIB。工作区原有改动保留；本次未提交、未推送。
