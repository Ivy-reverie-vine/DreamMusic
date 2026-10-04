# Issue #13：播放加载、失败与恢复验证记录

- 日期：2026-10-04（Asia/Shanghai）
- Issue：[明确播放加载、失败与恢复状态](https://github.com/Ivy-reverie-vine/DreamMusic/issues/13)
- 用户授权：完成并关闭 #13；本次不需要实机验收。
- 范围：HarmonyOS 6.1 / API 23 客户端；沿用 NightDream 统一入口、离线优先、下载入库和队列语义。

## 实现与验收对应

1. 正在播放页与迷你播放器共用 `PlaybackStatus`，明确展示正在加载、正在播放、已暂停、播放已结束与播放失败。在线本地缓存查找前就进入 PREPARING；地址解析与 AVPlayer 初始化/准备均包含在等待状态内。准备时播放按钮显示 LoadingProgress，播放/暂停及进度拖动不可用。恢复操作放在常驻播控区，文字与按钮使用既有主题和字号，按钮高度 48vp。
2. 网络、超时、来源解析、空音频地址和原生播放失败使用面向用户的文案及重试入口，不暴露底层 AVPlayer 状态、内部异常或 URL。文件缺失提供“到音乐库重新导入”，通过主壳进入音乐库；音乐库点选已有 missing 标记的音轨也交由真实文件检查更新播放器状态。登录/绑定问题提供设置与重试入口。
3. `PlayerViewModel.retry()` 保留当前音轨、播放位置和在线成功后的后台下载操作。在线播放每次准备/重试沿用同一 `mediaRef`（无引用时沿用既有网易 ID），经 `NetEaseApi.resolveUrl` 调用 NightDream 的原有 v1/v2 入口获取新地址。恢复不重建队列、不切换模式、不自行换源。在线搜索与在线音乐资料页共用 `OnlineMusicViewModel.playSong`，优先查找可用本地音轨；在线成功后仍后台下载并原位替换为本地音轨，非网易来源继续只瞬态播放。
4. 每次选择音轨产生新的请求序号并取消旧会话。本地查询、地址解析、原生状态/位置/结束/错误回调、准备后的 seek/历史、队列完成回写、后台下载与封面详情都检查请求或当前对象身份。相同音轨重复点播同样使用请求序号区分，旧失败不能替换新错误与恢复入口。
5. 新选择和恢复成功清除旧错误。歌词/取色钩子异常与封面详情、下载失败不会变为音频播放失败；这些能力继续使用自身失败/回退机制。定时暂停在本地查询或地址准备期间到期时，音频准备完成后仍执行暂停。
6. 每个请求持有独立 `PlayerSession`。取消初始化等待会显式拒绝旧 Promise 并清除超时；迟到创建的 AVPlayer 立即释放；prepare 返回后再次核对取消状态，取消后不调用 play。旧原生事件不再被转交；AVPlayer 与文件描述符按会话归属释放。

## 主机自动化

`node scripts/check-playback-recovery.mjs` 执行真实 ArkTS 播放、队列与在线入口逻辑，仅替换 Kit、网络和存储边界，通过：

- PREPARING → PLAYING → PAUSED → PLAYING、文件缺失与正确恢复动作。
- 网络、超时、解析、空 URL、认证、原生准备失败；原来源重新解析并重试成功，清除旧错误，保留队列、模式与播放位置。
- 旧 native 准备成功/失败、状态/位置/自然结束回调不能覆盖新选择或回写旧队列；新文件缺失的恢复入口不被旧 playing/error 清除。
- 地址解析成功/失败迟到、相同来源重复点播、本地查询迟到、旧后台下载迟到。
- 本地优先不解析在线 URL，查询失败仍完成在线队列选择；重试成功保留后台下载和本地替换。
- 歌词/封面钩子异常不打断音频；加载期间定时暂停到期。
- 迟到 createAVPlayer、初始化等待取消、prepare 期间取消、旧原生事件隔离与文件句柄释放。

相关回归均通过：

- `node scripts/check-playback-interactions.mjs`
- `node scripts/check-covers.mjs`
- `node scripts/check-lyrics.mjs`
- `node scripts/check-entry-page.mjs`
- `git diff --check`

既有封面和播控检查中的播放器替身补齐请求身份接口，以继续验证真实队列与封面逻辑。

## 编译与实机边界

- 进程级 `DEVECO_SDK_HOME=D:\DreamMusic\.devEco-sdk-compat`，执行 `hvigorw assembleHap --no-daemon --stacktrace`，保留类型检查：ArkTS 编译、HAP 打包和签名通过（BUILD SUCCESSFUL）。SDK/代码的弃用与可能抛异常警告仍存在。
- 产物：`entry/build/default/outputs/default/entry-default-signed.hap` 与 unsigned HAP。
- 实机等待/恢复体验、真实 AVPlayer 音频、系统播放卡片与生产网络：按用户明确要求，本次跳过。主机边界替身不作为这些设备行为的证据。
- 未运行全量 Hypium；本次运行播放专项与相关主机回归。工作区改动未提交、未推送。

## API 依据

核对本机 API 23 SDK 的 `@ohos.multimedia.media.d.ts`：`createAVPlayer`、stateChange/error/timeUpdate、初始化后 prepare、Promise release 与 AVPlayer state 声明。

官方参考：[AVPlayer API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-media-avplayer)、[使用 AVPlayer 播放音频](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avplayer-for-playback)。官方网页正文读取受限时，以目标 SDK 声明和实际 ArkTS 编译共同核实接口。
