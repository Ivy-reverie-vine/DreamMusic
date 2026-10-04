# 项目技术约束

> 修改必须申请用户同意

## 1. 鸿蒙版本锁定

- 目标设备系统: HarmonyOS 6.1
- API Version: **API 23**
- API Kit: 遇到功能需求时,**必须**从对应 Kit 导入;Kit 名称与导入名以官方 API 参考为准,禁止凭记忆或 Android 经验编造
- 权限声明: 网络请求(`ohos.permission.INTERNET`), 后台长时任务(audioPlayback), 媒体权限, 通知(实际所需权限以各 Kit 官方文档为准;通过系统选择器导入文件**无需**存储读写权限)
- 开发语言: ArkTS
- 所有系统能力必须基于 Kit 官方文档

### 禁止事项

- 禁止使用 Android API,禁止套用 Android 开发习惯(例如 MediaStore 式全盘音乐扫描在鸿蒙 NEXT 不存在,本项目采用"导入复制进沙箱"模型,见 `docs/adr/0001`)
- 禁止假设不存在的 API(例如 api-enhanced 本身没有 `/health` 端点;连接状态遵守 `docs/adr/0003` 的真实业务请求驱动契约)

## 2. 开发环境

| 组件           | 版本               | 路径                                           |
| :------------- | :----------------- | :--------------------------------------------- |
| DevEco Studio  | 6.1.0.830          | `D:\DevEco`                                    |
| HarmonyOS SDK  | 6.1.0.105 (API 23) | `D:\DevEco\sdk\default`                        |
| Node.js        | v18.20.1           | `D:\DevEco\tools\node`                         |
| ohpm           | 6.1.1.830          | `D:\DevEco\tools\ohpm\bin`                     |
| hvigor         | 6.23.7             | `D:\DevEco\tools\hvigor\bin`                   |
| hdc            | 3.2.0c             | `D:\DevEco\sdk\default\openharmony\toolchains` |
| JBR (内置 JDK) | OpenJDK 21.0.8     | `D:\DevEco\jbr`  优先使用 DevEco 内置 JBR      |
| JAVA_HOME      | JDK 22             | `D:\tool\Java\jdk-22`                          |

### 构建阻塞排查与固定做法

- 当前 DevEco SDK 的真实安装目录仍是 `D:\DevEco\sdk\default`,但 Hvigor 6.23.7 的 HarmonyOS SDK 扫描器无法直接识别该 SDK Manager 布局。不要复制、移动或修改真实 SDK；使用已验证的本地兼容根 `D:\DreamMusic\.devEco-sdk-compat`。
- 构建 HAP 前必须在当前 PowerShell 进程设置 SDK 路径：

  ```powershell
  $env:DEVECO_SDK_HOME='D:\DreamMusic\.devEco-sdk-compat'
  & 'D:\DevEco\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --no-type-check --stacktrace
  ```

- `entry/local.properties` 是 DevEco 自动生成文件；HarmonyOS 模式下不会作为 `DEVECO_SDK_HOME` 的替代配置，禁止把兼容路径写入其中。若当前 PowerShell 看不到用户级环境变量，不要误判为 SDK 缺失，先使用上面的进程级设置并记录环境问题。
- ArkTS 的 `catch` 变量可能是任意类型，禁止直接 `throw err`；必须先 `err instanceof Error`,否则抛出明确的 `new Error(...)`。新增代码须避免 `10605087 ArkTS Compiler Error`。
- 若 NightDream/Vite 报 `EPERM` 覆盖 `dist` 下的静态文件，先确认 `dist` 是 `.gitignore` 的生成目录，并用主机权限重跑 `npm run build`;不要为此修改 `vite.config.ts` 或提交 `dist`。

## 3. 项目架构

- 手机前端: ArkTS + ArkUI
- 代码分层: MVVM,目录 `model / service / viewmodel / components / common`,依赖单向(view → viewmodel → service → model)
- 数据: SQLite(`@kit.ArkData` relationalStore)
- 网络: `@kit.NetworkKit`(http)
- 媒体: `@kit.MediaKit`(AVPlayer / AVMetadataExtractor)
- 后台播控: `@kit.AVSessionKit` + `@kit.BackgroundTasksKit`(audioPlayback 长时任务)
- 文件导入: `@kit.CoreFileKit`(文件选择器)

### Kit 与官方文档对照(实现时以官方 API 参考为准)

| 能力 | Kit | 官方文档 |
| :--- | :--- | :--- |
| AVPlayer 音频播放 | `@kit.MediaKit` | [使用AVPlayer播放音频(ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avplayer-for-playback) |
| 音频元数据/封面提取 | `@kit.MediaKit` | [使用AVMetadataExtractor提取音视频元数据](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avmetadataextractor) |
| 后台播放/系统播控 | `@kit.AVSessionKit` | [后台播放-本地媒体会话](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avsession-background-scene) |
| 长时任务 audioPlayback | `@kit.BackgroundTasksKit` | 后台任务开发指导(官方文档) |
| SQLite 持久化 | `@kit.ArkData` | [Persisting RDB Store Data (ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-rdb-store) |
| HTTP/HTTPS 请求 | `@kit.NetworkKit` | [@ohos.net.http (数据请求)](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/js-apis-http-V5) |
| 文件/音频选择器 | `@kit.CoreFileKit` | [选择用户文件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/select-user-file) |

## 4. 项目目标

### 当前产品基线: 私人本地音乐播放器 + NightDream 统一在线入口

- 音乐文件模型: 用户通过系统选择器导入,**复制进应用沙箱**后播放(ADR-0001);数据库以沙箱相对路径为音轨唯一键
- 后台播放: AVSession 锁屏/控制中心播控,断点续播,四种播放模式(顺序/单曲循环/列表循环/随机)
- 格式与元数据: MP3 / AAC(M4A) / FLAC / WAV;导入时提取标签与封面;歌词仅读同目录 `.lrc`(有则显示)
- UI 目标: 四个一级入口(音乐库[歌曲/专辑/艺术家] / 正在播放 / 播放队列[拖拽排序] / 我的);歌单、播放历史、播放统计、公告消息和账户内容进入“我的”子页面;暂停按钮为不规则椭圆泡泡。当前实现已完成五入口到四入口迁移；剩余真机视觉与边缘返回验收。
- 数据库: 9 张物理表(tracks / albums / artists / playlists / playlist_tracks / play_history / favorites / server_profiles / player_state;code-review 后与 PRD 对齐);启动增量扫描 + 手动全量重扫
- 在线能力经 NightDream 中间层统一入口提供;当前来源为 api-enhanced,未来可由 NightDream 调度 YouTube 等其他来源。客户端不得直接接入具体来源。

### 中间层职责

- NightDream 负责账户鉴权、网易云绑定、白名单、限流、来源选择、来源降级和响应归一化。
- App 只访问 NightDream 的 `/dreammusic/api/v1` 和来源中立的 `/dreammusic/api/v2`,不直接访问 api-enhanced、网易云、YouTube 或其他来源。
- 新增音乐来源必须在 `D:\DreamMusic\NightDream` 中实现和验证，不改变客户端统一入口。
- 普通播放和本地下载入库的客户端边界遵守 `docs/adr/0005-audio-source-boundary.md`；服务端替代源或任务下载能力不得被客户端自行拼接调用。
- v2 搜索结果使用版本化 `mediaRef`；播放、详情、封面和歌词沿用同一引用。非网易来源当前只做瞬态在线播放，不写入现有网易云数字 ID 下载/SQLite 替换链。

## 5. 测试流程

- 编译测试: `hvigorw assembleHap`
- 纯逻辑(队列算法/扫描去重/播放模式/健康判定): Hypium 本地单元测试
- 鸿蒙系统能力(AVPlayer/AVSession/选择器/网络): 需用户真机运行测试

## 6. 开发流程与文档约定

- 需求阶段 pipeline: `grill-with-docs → to-prd → to-issues → implement-review`
- 领域术语: 根目录 `CONTEXT.md`,术语变更即时更新
- 调研与事实: `docs/research/`;决策记录: `docs/adr/`;设计总表: `docs/design/`
- **UI 与视觉权威: 根目录 `PRODUCT.md`(产品/品牌)与 `DESIGN.md`(视觉系统,当前为 seed 版);任何 UI 改动不得与二者冲突;代码落地后重跑 document 流程回填真实 token**
- 实现时所有系统 API 必须查官方文档后使用,禁止编造
