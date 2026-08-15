# HarmonyOS 官方文档调研笔记(本地音乐播放器)

> 目标环境: HarmonyOS 6.1 / API 23 / ArkTS(见根目录 AGENT.md)
> 状态: 持续更新。✅=已核对官方文档;❓=待核实/待真机验证。

## 1. 音频播放 — Audio Kit / Media Kit

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| AVPlayer 音频播放 | ✅ 用 `@kit.MediaKit` 的 `AVPlayer` 播放音频,标准流程 create→setSource(url)→prepare→play | [使用AVPlayer播放音频(ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avplayer-for-playback) |
| AVPlayer API 参考 | ✅ 状态机、事件回调(on('stateChange') 等)以此为准 | [AVPlayer API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-media-avplayer) |
| 音视频开发概述 | ✅ 能力总览,选型依据 | [音视频开发概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/av-overview) |

## 2. 后台播放与播控 — AVSession Kit

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| 后台播放 | ✅ 音乐类应用后台播放的标准做法是接入 **AVSession**(媒体会话),配合后台任务类型 `audioPlayback`,可实现锁屏/通知栏播控 | [后台播放-本地媒体会话](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avsession-background-scene) |
| 接入场景 | ✅ 控制中心、系统播控面板接入方式 | [应用接入AVSession场景介绍](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/avsession-access-scene) |
| 后台播放 FAQ | ✅ 官方 FAQ | [如何后台播放音乐](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-audio-1) |

## 3. 元数据提取 — AVMetadataExtractor

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| 元数据提取 | ✅ `AVMetadataExtractor` 可提取标题/艺术家/专辑/封面(`fetchAlbumCover`)等 | [使用AVMetadataExtractor提取音视频元数据](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avmetadataextractor) |
| API 参考 | ✅ | [AVMetadataExtractor API](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/arkts-apis-media-avmetadataextractor) |

## 4. 数据持久化 — ArkData relationalStore

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| 关系型数据库 | ✅ 用 `@kit.ArkData` 的 `relationalStore.getRdbStore` 得到 RdbStore,即 SQLite 封装,SQL 语法可用 | [Persisting RDB Store Data (ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-rdb-store) |
| API 参考 | ✅ | [relationalStore API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-data-relationalstore-f) |

## 5. 网络 — Network Kit

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| HTTP 请求 | ✅ `@kit.NetworkKit` → `@ohos.net.http` 的 `http.createHttp()`,支持 HTTP/HTTPS,`HttpRequestOptions` 可设超时、`caPath` 等 | [@ohos.net.http (数据请求)](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/js-apis-http-V5) |
| 明文 HTTP | ✅ **已核实(用户)**: 明文 HTTP 由系统配置决定是否禁止,非硬编码禁止 → LAN 备选 Profile 先支持 http://,真机不通再按配置调整 | [论坛:全局禁止HTTP明文传输](https://developer.huawei.com/consumer/cn/forum/topic/0202215451804646457) |

## 6. 本地音乐文件获取 — Core File Kit / 选择器

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| 选择用户文件 | ✅ 通过 `DocumentViewPicker` / `AudioViewPicker` 由用户挑选文件或目录,返回 URI,可申请持久化授权(`persistPermission`) | [选择用户文件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/select-user-file) |
| AudioViewPicker 实战 | ✅ 官方博客示例 | [使用DocumentViewPicker和AudioViewPicker选择音频文件](https://developer.huawei.com/consumer/cn/blog/topic/03216948115595082) |
| 媒体库 photoAccessHelper | ✅ 受限开放能力,主要面向图片/视频资产;**音频资产的系统级扫描能力待确认** | [媒体资源使用指导-受限开放能力](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/photoaccesshelper-resource-guidelines-V13) |
| AVPlayer 可播放的路径 | ⚠️ 社区帖称 AVPlayer 只能播网络 URL 和应用沙箱路径。**用户确认不构成风险**: 本项目采用沙箱模型(ADR-0001)已规避;真机验证时顺带确认,仅作未来"免复制"优化调研 | [论坛讨论](https://bbs.itying.com/topic/6905aa7d5479bc0071f5256d) |
| 持久化授权不复制 | ⚠️ 同上,仅调研 | [论坛:永久化权限而不需copy](http://bbs.itying.com/topic/6781b37924cdd5004b44661f) |

## 7. 音频格式支持

| 主题 | 结论 |
| :--- | :--- |
| AVPlayer 解码格式 | ✅ 基础四种 MP3/AAC(M4A)/FLAC/WAV 已多方印证(官方编解码能力);**实现时对照 [Media Kit简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/media-kit-intro)(用户指定)确认是否支持 OGG 等扩展** |

## 8. 通知与权限

- 网络权限 `ohos.permission.INTERNET`(AGENT.md 已列)
- 后台播放相关:长时任务类型 `audioPlayback` + AVSession(官方 FAQ 确认)
- 通过选择器导入文件**不需要**存储读写权限(用户授权 URI 即可)
- 媒体通知(播控通知)随 AVSession 自动出现,无需单独通知权限

## 9. 图片读取与取色(动态主题)

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| 读像素 | ✅ `@kit.ImageKit`: `image.createImageSource` → `createPixelMap`(可指定缩小尺寸)→ `readPixels` / `readPixelsToBuffer` 拿像素缓冲,取色引擎在其上做纯逻辑运算 | [Using PixelMap for PixelMap Operations](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/image-pixelmap-operation-V14) |
| 选背景图 | ✅ `picker.PhotoViewPicker`(`@kit.CoreFileKit` / @ohos.file.picker)从相册选图 | [图片获取与保存实践](https://developer.huawei.com/consumer/cn/doc/best-practices-V14/bpta-image_get_and_save-V14) |

## 10. 沉浸光感(点击发光/玻璃底栏,官方新特性)

| 主题 | 结论 | 官方链接 |
| :--- | :--- | :--- |
| 沉浸光感 | ✅ 鸿蒙 6.x 官方特性:光效光源跟手(触点光晕)、组件导航样式优化;QQ 音乐鸿蒙版的点击发光与玻璃底栏即此能力。HarmonyOS 6.1/API 23 在覆盖范围 | [沉浸光感-最佳实践](https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-spatiality-immersive) |
| 光效跟手 | ✅ 官方问答 | [光效光源跟手](https://developer.huawei.com/consumer/cn/forum/topic/0203213193412845108) |
| 组件/接口名 | ❓ 实现时以官方 API 参考核对(HdsTabs 等),不凭社区帖猜测 | [组件导航样式优化讨论](https://bbs.itying.com/topic/6a2b9e2ab50553004baead69) |

## 待办核实清单

1. ✅ AVPlayer 路径限制 → 沙箱模型已规避(ADR-0001),真机顺带验证
2. ✅ 明文 HTTP → 由系统配置决定(用户核实),按现方案执行
3. ✅ AVPlayer 格式 → 基础四种已印证;实现时对照 Media Kit 简介页扩缩
4. ❓ photoAccessHelper 能否枚举音频资产(仅调研,不影响 v1 方案)
