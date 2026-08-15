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
- 禁止假设不存在的 API(例如 api-enhanced 本身没有 `/health` 端点,由我们后续补充;客户端契约见 `docs/adr/0002`)

## 2. 开发环境

| 组件           | 版本               | 路径                                           |
| :------------- | :----------------- | :--------------------------------------------- |
| DevEco Studio  | 6.1.0.830          | `D:\DevEco`                                    |
| HarmonyOS SDK  | 6.1.0.105 (API 23) | `D:\DevEco\sdk\default`                        |
| Node.js        | v18.20.1           | `D:\DevEco\tools\node`                         |
| ohpm           | 6.1.1.830          | `D:\DevEco\tools\ohpm\bin`                     |
| hvigor         | 6.23.5             | `D:\DevEco\tools\hvigor\bin`                   |
| hdc            | 3.2.0c             | `D:\DevEco\sdk\default\openharmony\toolchains` |
| JBR (内置 JDK) | OpenJDK 21.0.8     | `D:\DevEco\jbr`  优先使用 DevEco 内置 JBR      |
| JAVA_HOME      | JDK 22             | `D:\tool\Java\jdk-22`                          |

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

### 当前阶段 v1: 私人本地音乐播放器(纯本地)

- 音乐文件模型: 用户通过系统选择器导入,**复制进应用沙箱**后播放(ADR-0001);数据库以沙箱相对路径为音轨唯一键
- 后台播放: AVSession 锁屏/控制中心播控,断点续播,四种播放模式(顺序/单曲循环/列表循环/随机)
- 格式与元数据: MP3 / AAC(M4A) / FLAC / WAV;导入时提取标签与封面;歌词仅读同目录 `.lrc`(有则显示)
- UI: 五页(音乐库[歌曲/专辑/艺术家] / 正在播放 / 播放队列[拖拽排序] / 歌单 / 设置);暂停按钮为不规则椭圆泡泡
- 数据库: 9 张物理表(tracks / albums / artists / playlists / playlist_tracks / play_history / favorites / server_profiles / player_state;code-review 后与 PRD 对齐);启动增量扫描 + 手动全量重扫
- 网络预留(**只做这些**): api-enhanced 服务器 Profile 管理(Cloudflare Tunnel 域名为主、局域网直连备选)+ `GET /health` 健康检查(3s 超时、启动+15s 轮询+手动、三态静默显示,ADR-0002);**不调用任何业务端点**

### 后续阶段: 连接 api-enhanced

- api-enhanced(网易云 Node.js API 服务,已本地克隆且**允许修改**)经 Cloudflare Tunnel 域名以 HTTPS 暴露,证书为公网可信证书
- 应用经 HTTPS 拉取 JSON 与音乐文件;`/health` 端点由我们后续补进 api-enhanced
- 在线歌词、搜索等能力在此阶段接入,全部复用统一 HTTP 网关与连接状态

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
