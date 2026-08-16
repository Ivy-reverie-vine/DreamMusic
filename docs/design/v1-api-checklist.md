# v1 本地离线音乐播放器 — 系统 API 清单(定稿)

> 回答"v1 要用的所有 API 是否已定、是否都是 kit 命名空间"。
> 结论: **能力面已 100% 覆盖,全部系统能力均为 `@kit.*` 命名空间导入**(API 12+ 官方推荐写法),另有 ArkUI 声明式框架(内置,不属于 kit)与测试框架。函数级签名在实现时按官方 API 参考核对(AGENT.md 约束)。
> 状态: ✅=官方文档出处已核实;❓=实现时到指定官方页面核对细节。

## 1. 文件导入与文件系统 — `@kit.CoreFileKit`

| API | 用途 | 官方出处 |
| :--- | :--- | :--- |
| `picker.AudioViewPicker` / `DocumentViewPicker` | 选择音频文件/文件夹(用户授权,无需存储权限) | [选择用户文件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/select-user-file) |
| `fileIo`(copyFileSync / listFileSync / readTextSync / unlinkSync / mkdirSync 等) | 复制进沙箱、扫描目录、读 .lrc、删除 | Core File Kit fileIo 官方 API 参考 |
| 沙箱目录 `context.filesDir` | 音乐库根目录 | UIAbilityContext(见 `@kit.AbilityKit`) |

## 2. 播放与元数据 — `@kit.MediaKit`

| API | 用途 | 官方出处 |
| :--- | :--- | :--- |
| `media.createAVPlayer` + `AVPlayer` | 音轨播放(create→setSource(url)→prepare→play,on('stateChange')) | [使用AVPlayer播放音频(ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avplayer-for-playback) |
| `AVPlayer` 格式与能力总览 | ❓ 实现时对照此页的格式/来源说明 | [Media Kit简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/media-kit-intro)(用户指定) |
| `media.createAVMetadataExtractor` + `fetchMetadata` / `fetchAlbumCover` | 标题/艺术家/专辑/时长/封面(→PixelMap) | [使用AVMetadataExtractor提取音视频元数据](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avmetadataextractor) |

> 格式策略: 导入时白名单 MP3/AAC(M4A)/FLAC/WAV(编解码官方支持,多方印证);若 Media Kit 简介页证实 AVPlayer 还支持 OGG 等,实现时按官方结论扩展。

## 3. 后台播放与播控 — `@kit.AVSessionKit` + `@kit.BackgroundTasksKit`

| API | 用途 | 官方出处 |
| :--- | :--- | :--- |
| `avSession.createAVSession` / `activate` / `setAVQueueItems` / 控制命令监听 | 锁屏/控制中心播控、媒体信息展示 | [后台播放-本地媒体会话](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/avsession-background-scene) |
| `backgroundTaskManager.startBackgroundRunning`(AUDIO_PLAYBACK) / `stopBackgroundRunning` | 后台长时任务保活 | 后台任务开发指导(官方) |

> 长时任务申请条件(官方): ①module.json5 `backgroundModes: ["audioPlayback"]` ②声明权限 `ohos.permission.KEEP_BACKGROUND_RUNNING` ③AVSession 已激活且有音频播放。上述权限为 normal 级 system_grant,安装即授予。

## 4. 数据持久化 — `@kit.ArkData`

| API | 用途 | 官方出处 |
| :--- | :--- | :--- |
| `relationalStore.getRdbStore` → `RdbStore`(executeSql / query / insert / update) | 7 张表: tracks / albums / artists / playlists / play_history / favorites / **server_profiles** | [Persisting RDB Store Data (ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-rdb-store) |

> 注: `server_profiles`(服务器 Profile 表)是 Q4"6 表"之后补的第 7 张表——网络预留需要持久化 Profile,统一放 SQLite,不引入 preferences,减少 API 面。

## 5. 网络 — `@kit.NetworkKit`

| API | 用途 | 官方出处 |
| :--- | :--- | :--- |
| `http.createHttp()` / `request` / `on('dataReceive')` / `on('dataReceiveProgress')` / `destroy` | 阶段 v2 业务请求与 CDN 下载(ADR-0003:请求驱动,不再 /health 探活);JSON 15s 超时、下载 120s 超时 | [@ohos.net.http (数据请求)](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/js-apis-http-V5) |

> 明文 HTTP: 由系统配置决定是否禁止(用户已核实),LAN 备选 Profile 先支持 http://,真机若不通再按官方配置调整。

## 6. 权限 — `@kit.AbilityKit`(仅声明,无运行时弹窗)

| 权限 | 等级 | 用途 | 声明位置 |
| :--- | :--- | :--- | :--- |
| `ohos.permission.INTERNET` | normal / system_grant | 网络请求 | module 级 `requestPermissions` |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | normal / system_grant | audioPlayback 长时任务 | module 级 `requestPermissions` |
| `backgroundModes: ["audioPlayback"]` | 后台模式声明(非权限) | 长时任务类型 | **ability 级**(与 skills 同级;已按 SDK 官方 schema 核实: `D:\DevEco\sdk\default\hms\toolchains\modulecheck\module.json`) |

> 通过选择器导入**无需**存储读写权限;AVSession 媒体通知**无需**通知授权 → **v1 没有任何运行时权限申请流程**。

## 7. UI — ArkUI 声明式框架(内置,非 kit)

- 路由: `Navigation` / 页面栈
- 列表: `List` + 拖拽排序(`onItemDragStart`/`onItemDrop`,IDEA.md 的队列拖拽)
- 封面: `Image`(直接吃 AVMetadataExtractor 返回的 PixelMap)
- 进度/音量: `Slider`;自定义绘制: 椭圆泡泡暂停按钮
- 状态管理: `@State` / `@Observed` / `@Provide` / `@Watch`(MVVM 绑定)

## 8. 测试 — 非 kit

- `@ohos/hypium`(oh-package.json5 devDependency,已存在)— 纯逻辑单测
- 编译把关: `hvigorw assembleHap`

## 9. 图片处理与取色(动态主题,issue-00)— `@kit.ImageKit` + `@kit.CoreFileKit`

| API | 用途 | 官方出处 |
| :--- | :--- | :--- |
| `picker.PhotoViewPicker` | 选择自定义背景图(相册/图库) | [图片获取与保存实践](https://developer.huawei.com/consumer/cn/doc/best-practices-V14/bpta-image_get_and_save-V14) |
| `image.createImageSource` → `createPixelMap`(缩小 ≤64px)→ `readPixels` / `readPixelsToBuffer` | 读背景图/封面像素,喂给取色引擎 | [Using PixelMap for PixelMap Operations](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/image-pixelmap-operation-V14) |
| 取色引擎(量化聚类+钳制) | 像素数组 → DESIGN.md 角色色 | 纯逻辑,Hypium 单测(非系统 API) |

> 封面 PixelMap 来自 AVMetadataExtractor(§2),可直接进入取色引擎,无需二次读文件。

## 覆盖度结论

- 所有系统能力调用点 = 7 个 kit:`CoreFileKit / MediaKit / AVSessionKit / BackgroundTasksKit / ArkData / NetworkKit / ImageKit`(+`AbilityKit` 提供 context/权限声明)
- 没有任何 `@ohos.*` 旧式非 kit 导入需求;ArkUI 组件为语言框架内置
- 每项都有官方文档出处,实现时按 AGENT.md 约束核对函数签名
