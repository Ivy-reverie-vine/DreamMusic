# DreamMusic 当前项目内容基线

> 本文件以 `entry/src/main/ets`、模块配置和测试目录为事实基准，整理根目录及 `docs/` 中仍然有效的项目内容。
> 旧 PRD、issue 和调研资料可能记录历史方案；若与源码或 ADR-0003/0005 冲突，以源码和最新 ADR 为准。

## 1. 项目定位

DreamMusic 是面向 HarmonyOS 手机的私人音乐播放器：本地音乐以离线播放为核心，同时通过 NightDream 中间层提供统一、可扩展的在线音乐获取入口。当前实际来源是 `api-enhanced`，后续可由 NightDream 调度 YouTube 等其他来源；客户端不直接感知或拼接各来源服务。

当前目标环境由配置和项目约束共同确定：HarmonyOS 6.1、API 23、phone、ArkTS。构建配置中的 `targetSdkVersion` 和 `compatibleSdkVersion` 均为 `6.1.0(23)`。

项目禁止使用 Android API、Android 存储/导航/生命周期假设，以及未经官方 Kit 文档核实的 HarmonyOS API。

## 2. 领域词汇

- **音乐库**：应用沙箱内已登记的本地音轨集合。
- **音轨**：本地音频文件及标题、艺术家、专辑、时长、封面、网易云歌曲 ID 等元数据。
- **导入**：通过 HarmonyOS 文件选择器选择音频后，复制进应用沙箱并写入音乐库。
- **在线音轨**：搜索得到的网易云歌曲，播放期间可先作为瞬态条目使用；下载完成后转换为本地音轨。
- **账户会话**：NightDream 的 `dm_session` 和 `X-API-Key` 凭证。网易云 Cookie 只保存在服务端，不进入 App。
- **绑定**：通过二维码流程把 NightDream 账户与网易云账户绑定。
- **连接状态**：最近一次业务请求反映出的在线、离线、检查中状态；不是独立 `/health` 探活结果。
- **普通播放直链**：`/song/url/v1` 返回的普通 CDN URL，只用于播放和客户端下载入库，不执行解灰换源。
- **本地入库**：将音频、封面、歌词写入应用沙箱和 SQLite，使其可离线播放。

## 3. 当前架构

代码按以下方向组织：

```text
ArkUI pages/components
        ↓
viewmodel
        ↓
service
        ↓
model / common / HarmonyOS Kit
```

主要目录：

- `entry/src/main/ets/model`：音轨、播放状态等领域数据结构。
- `entry/src/main/ets/service/library`：SQLite、导入、扫描、音乐库 CRUD。
- `entry/src/main/ets/service/playback`：AVPlayer、队列、后台播放和系统播控。
- `entry/src/main/ets/service/network`：HTTP 网关、账户、NightDream 转发、在线音乐缓存和下载入库。
- `entry/src/main/ets/service/theme`、`service/color`：背景图、动态取色和主题状态。
- `entry/src/main/ets/viewmodel`：页面状态与领域操作编排。
- `entry/src/main/ets/components`、`pages`：ArkUI 页面和可复用组件。

主要系统 Kit：`@kit.NetworkKit`、`@kit.CoreFileKit`、`@kit.MediaKit`、`@kit.AVSessionKit`、`@kit.BackgroundTasksKit`、`@kit.ArkData`、`@kit.AssetStoreKit`、`@kit.ImageKit`、`@kit.AbilityKit`。

## 4. 本地音乐能力

### 导入与扫描

- `ImportService` 支持文件选择器导入音频，也保留文件夹选择入口。
- `ImportPlanner` 负责格式过滤、目标路径规划和去重。
- 支持的基础格式为 MP3、AAC/M4A、FLAC、WAV。
- 导入时使用 `AVMetadataExtractor` 读取标题、艺术家、专辑、时长和封面。
- 音乐文件复制到应用沙箱 `filesDir` 下的 `music/` 目录。
- 音轨路径使用沙箱相对路径；在线歌曲另外保存 `neteaseId`，用于播放和本地复用。
- `EntryAbility` 启动时初始化 `LibraryStore` 并执行增量扫描。
- 扫描会比较沙箱文件和数据库记录；缺失文件标记为缺失，不会自动删除数据库记录。
- 设置页支持重新扫描；音乐库支持仅移出记录或同时删除沙箱文件。

### SQLite

`LibraryStore` 当前实际创建 9 张表：

1. `tracks`
2. `albums`
3. `artists`
4. `playlists`
5. `playlist_tracks`
6. `play_history`
7. `favorites`
8. `server_profiles`
9. `player_state`

旧设计文档中写的“8 张表”已经过时，`player_state` 是源码中实际存在的第 9 张表。

当前提供的存储能力包括：音轨 CRUD、专辑/艺术家聚合、歌单 CRUD、歌单曲目顺序、收藏、播放历史、服务器 Profile、队列/播放模式/洗牌状态/断点进度/定时暂停持久化，以及歌曲标题和作者编辑。

### 播放与队列

- `PlayerSession` 通过 `AVPlayer` 支持沙箱文件和在线 URL 播放。
- `PlayerViewModel` 提供播放、暂停、继续、跳转、音量和播放状态同步。
- 设置页提供 30/60/120 分钟定时暂停；定时器以设备级绝对截止时间保存到 `player_state`，到期通过显式 `pause()` 停止播放，不改变队列。
- `QueueEngine` 支持顺序、单曲循环、列表循环、随机四种模式。
- 随机顺序、当前位置和播放步数会写入 `player_state`。
- `QueueViewModel` 支持拖拽排序、自动切歌、队列恢复和本地音轨替换。
- 切后台和 Ability 销毁时会保存播放进度；队列 ViewModel 也提供定时持久化路径。
- `BackgroundPlayback` 使用 AVSession 和 `audioPlayback` 长时任务对接锁屏/控制中心播控。
- 定时暂停到期会同步后台播控状态，并尝试停止 `audioPlayback` 长时任务；锁屏、后台和 Ability 重启行为仍需真机验收。

### 歌词与主题

- 本地歌词读取音轨同目录的同名 `.lrc`，由 `LrcParser` 解析。
- 在线歌词来自 `/lyric/new`，支持读取 LRC，并在缺少 LRC 时将 YRC 转为 LRC 后落盘。
- `ThemeService` 支持深色、浅色、跟随系统三种模式，默认深色。
- 背景图由选择器导入沙箱，`ImageKit` 缩放并读取像素，`ColorExtract` 计算主题色。
- 正在播放页会根据封面更新主题色；默认主题使用设计文档中的铜绿色种子色。
- UI 使用 `DesignTokens`、玻璃底栏、封面缩略图、黑胶式播放页、椭圆泡泡暂停按钮和 SymbolGlyph 图标。
- 系统开启“减弱动效”时，导航触点光晕会关闭，页面动效使用降级路径。

## 5. NightDream 在线能力与统一来源入口

NightDream 是本项目配套的中间层，不是仅为 api-enhanced 提供固定转发的薄代理。客户端只依赖 NightDream 的统一接口，由中间层负责账户鉴权、网易云绑定、白名单、限流、来源选择、来源降级和响应归一化。当前来源为 api-enhanced；增加 YouTube 等来源时，应在 NightDream 内扩展调度，不改变 HarmonyOS 客户端的来源模型。

### 地址与认证

App 保存的是 NightDream 根地址，代码自动拼接：

```text
/dreammusic/api/v1
```

`DreamMusicAuth` 的实际流程为：

```text
注册 → 登录 → 读取 dm_session → 获取 X-API-Key → /auth/me → 必要时 QR 绑定
```

- `dm_session` 和 `dm_api_key` 使用 `SecureCredentialStore` 与 `@kit.AssetStoreKit` 保存。
- 普通 preferences 只保存用户名、绑定状态、梦点、签到日期、今日消息次数等非秘密状态。
- 未登录时可以跳过登录门禁并使用本地音乐；在线功能会再次要求登录。
- 已登录但未绑定或绑定失效时，启动流程会引导二维码绑定。
- 二维码状态使用 `800/801/802/803`，轮询间隔由 `QrBindView` 控制。

### HTTP 网关

`ApiClient` 统一处理：

- JSON GET/POST/DELETE 请求；
- JSON 请求 15 秒连接/读取超时；
- 二进制下载 120 秒超时；
- 响应 JSON 解析和错误映射；
- `X-API-Key`、`Cookie` 和响应头归一化；
- `requestInStream`、`dataReceive`、`dataReceiveProgress` 文件下载；
- 空文件检测和失败文件清理。

自有 `/auth/*` 接口按 `{code,data}` 解析；转发接口保留上游 JSON 结构，不强行增加 `data` 包装。

### 当前实际转发接口

源码中已经调用：

- `/search`
- `/song/url/v1`
- `/song/detail`
- `/lyric/new`
- `/user/playlist`
- `/playlist/track/all`
- `/likelist`
- `/like`

转发请求使用 `X-API-Key` 和 `randomCNIP=true`。搜索、封面、歌词查询缓存约 2 分钟；查询遇到限流或上游 503 时最多进行两次退避重试。

个人音乐库读取支持歌单分页和喜欢歌曲详情按 500 个 ID 分批，不把喜欢列表固定截断到 999 首。

### 当前账户接口

源码已接入：

- 注册、登录、登出、当前用户、API Key；
- QR Key、二维码创建、二维码状态检查；
- 签到、兑换码、公告；
- 会话列表、会话撤销、梦点流水；
- 播放统计；
- 消息发送。

消息发送由服务端维护扣点、每日次数和失败记录；App 显示发送状态和今日次数。

## 6. 在线播放与下载边界

当前客户端实现的是统一入口下的普通播放/本地入库流程：

```text
搜索
  → /song/url/v1 获取普通直链
  → AVPlayer 立即播放
  → 后台用 ApiClient.download 下载普通直链
  → 下载封面和歌词
  → 写入 SQLite
  → 将队列中的瞬态在线条目替换为本地音轨
```

明确约束：

- `level` 固定为 `exhigh`。
- URL 为空时视为无版权或需要会员，播放/下载失败并提示用户。
- 不调用 `/song/url/match`，不做客户端解灰，不创建 `/auth/downloads` 下载任务。
- 当前源码没有实现 `/auth/downloads` 任务轮询、任务文件获取或任务删除流程。
- `OnlineDownloadService` 使用 `music/<neteaseId>.<ext>` 保存音频，`covers/<neteaseId>.jpg` 保存封面，歌词保存到 `music/<neteaseId>.lrc`。
- 封面或歌词下载失败不会阻断音频入库；缺失资源后续可尝试修复。

因此，客户端不直接调用来源服务，也不自行选择或拼接 YouTube、网易云等来源。`/song/url/match`、服务端解灰和 `/auth/downloads` 如果继续存在，只能作为 NightDream 内部或未来统一入口的服务端能力；它们不是当前 HarmonyOS 客户端的直接调用契约。

## 7. 页面与用户流程

当前主壳为五个页签：

1. 音乐库：歌曲、专辑、艺术家视图；在线搜索入口；导入和编辑歌曲。
2. 正在播放：封面、歌词、进度和播放控制。
3. 队列：当前队列、拖拽排序和播放模式。
4. 歌单：本地歌单、我喜欢的音乐、最近播放，以及在线歌单/喜欢列表。
5. 我的：账户、服务器、主题、背景图、扫描、签到、兑换码、公告、消息等设置。

登录门禁允许本地优先使用；在线搜索、在线播放、歌词和在线音乐库操作需要有效账户及必要的网易云绑定。

## 8. 连接状态与错误处理

`HealthStateMachine` 仍是状态机实现名称，但当前连接判断由真实业务请求驱动：

- 请求开始：检查中；
- 业务成功：在线；
- 网络失败、超时、非成功 HTTP 或关键字段缺失：离线；
- 未发生过请求：未检测。

当前入口在 `NetworkViewModel.probe()`，不会启动旧文档所述的 `/health` 定时探活。

主要错误映射：

- `401`：会话/API Key 失效；
- `402`：梦点不足；
- `403`：未绑定或账户无权限；
- `404`：路径未允许或资源不存在；
- `429`：中间层限流；
- `502`：上游不可达；
- 上游业务码 `301`：网易云绑定失效；
- 上游 `460/503`：风控或过频。

## 9. 测试和验证

当前测试目录包含：

- `entry/src/test/ColorExtract.test.ets`
- `DateUtil.test.ets`
- `HandwrittenLayout.test.ets`
- `HealthStateMachine.test.ets`
- `ImportPlanner.test.ets`
- `List.test.ets`
- `LocalUnit.test.ets`
- `LrcParser.test.ets`
- `QueueEngine.test.ets`
- `SleepTimer.test.ets`
- `ScanDiff.test.ets`

另有 `entry/src/ohosTest` 下的设备侧测试模板。

纯逻辑测试覆盖取色、日期、手写布局、连接状态、导入规划、歌词解析、队列和扫描差异；AVPlayer、AVSession、文件选择器、AssetStoreKit、真实 HTTP 和真机登录/绑定仍属于设备环境验证范围。

构建命令以 `docs/research/build-environment.md` 为准：

```powershell
node D:\DevEco\tools\hvigor\hvigor\bin\hvigor.js --no-daemon assembleHap
```

定时暂停已通过纯逻辑测试、完整 `hvigor test` 和 `assembleHap`；本次尚未完成后台/锁屏/Ability 重启等真机验收。UI 仍待重新设计，后续会进行较大范围的视觉和交互改版。

## 10. 文档冲突与待确认事项

以下内容需要按项目后续决策执行：

1. 新增音乐来源时，先在 NightDream 内实现来源适配和调度，再由统一接口向客户端暴露稳定结果。
2. `/auth/downloads`、`/song/url/match` 等服务端能力是否启用，由 NightDream 的当前实现和统一入口策略决定；客户端不直接依赖它们。
3. 定时暂停的设备侧验收仍待完成；后续重点是 UI 重新设计和大范围视觉/交互改版。

## 11. 后续工作流

项目约定的开发流程为：

```text
grill-with-docs → to-prd → to-issues → implement-review
```

任何新功能都应先明确是否属于本地核心、NightDream 统一来源入口、账户/代理或 UI 设计改版，避免客户端绕过中间层直接接入新来源，也避免重新引入已被 ADR-0003 淘汰的 `/health` 探活。音频来源策略由 NightDream 统一调度，客户端保持稳定的播放和入库契约。
