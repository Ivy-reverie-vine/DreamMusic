# Issue #12：统一歌曲封面验证记录

- 日期：2026-10-03（Asia/Shanghai）
- Issue：[统一本地与在线歌曲的封面展示](https://github.com/Ivy-reverie-vine/DreamMusic/issues/12)
- 用户授权：完成并关闭 #12，不需要本次实机验收。
- 范围：HarmonyOS 6.1 / API 23 客户端；保留统一在线入口与原有音频会话。

## 实现

`CoverArtService` 统一正在播放、迷你播放器、队列、AVSession 和取色的解析。本地文件存在时优先使用，文件缺失时尝试同音轨在线 URL，下载/解码失败与无封面使用同一 `cover_placeholder.svg`。封面 URL 只来自现有在线详情响应，来源引用 `mediaRef` 沿用当前音轨；不新增音乐来源或后端接口，不向封面 CDN 发送账户凭据。

在线封面保存到 `cacheDir/cover-art`，完整 URL sidecar 校验磁盘身份，最多 32 项、32MiB，按文件写入时间清除旧缓存。每次网络下载最多 8MiB，连接/读取超时各 8 秒，HTTP 对象在 finally 销毁，文件句柄写完关闭。相同 URL 的并发请求合并；离线时可读取已缓存封面。系统清理 cacheDir 后回退占位。失败结果缓存 30 秒，重新借用时到期可重试；当前显示节点不会轮询网络。

PixelMap 缓存按文件目录、URI/本地文件版本和解码尺寸分档：缩略图 96px、播放页/系统媒体图 512px、取色 64px RGBA。最多保留 12 个闲置条目且不超过 8MiB；正在被页面、取色或 AVSession 借用的图不提前释放。每次 ImageSource 解码均在 finally 释放；PixelMap 使用 lease 引用计数，页面离开、请求过期、会话更换、能力销毁与缓存淘汰均归还/释放。背景预设和自定义图的 ImageSource/PixelMap 异常路径也补齐释放。

`CoverLoadState` 为各节点维护请求序号，迟到结果只归还。新音轨立即清旧图；同音轨在线转本地通过 `mediaRef`/网易来源 ID 保持身份，保留当前图直到本地封面加载完成；下载封面缺失时继续尝试原在线封面缓存。取色复用同一解析、64px 缓存和背景版本/请求序号，另外核对当前音轨对象，切歌立即恢复背景配色，同音轨转换保留配色直到新的取色完成。取色钩子由主壳持有，播放页离开后也不会向已离开的页面回调。

AVSession 媒体信息只在音轨、标题、时长或封面源改变时更新，进度同步不重复解码。换音轨先提交新元数据与占位图，封面加载独立于播放状态同步；媒体信息写入串行且提交前核对请求版本。保持正在被系统会话使用的 lease 直到下一次媒体信息提交成功或会话销毁。瞬态转本地立即更新媒体元数据，仍使用已打开的音频会话/进度。搜索/在线音乐入口不再等待缺失封面的详情请求才开始播放。

## 主机自动化

`node scripts/check-covers.mjs` 执行真实 ArkTS 逻辑，仅在 ImageKit、HTTP、文件系统、AVSession 边界使用替身，通过：

- 本地优先、无封面、文件缺失、损坏封面与在线回退。
- 不同尺寸请求合并、PixelMap 引用计数、重复归还、缓存容量、文件同路径更新。
- 在线请求合并、磁盘离线读取、断网/HTTP 404/超尺寸回退、失败缓存与到期重试。
- 磁盘 32 项/32MiB 清理、文件句柄关闭、HTTP/ImageSource/PixelMap 释放。
- 快速切歌/离页/清缓存时旧解码迟到不提交；同音轨换图不插入占位帧。
- 在线图片进入媒体元数据、来源不同但瞬态 ID 相同仍正确区分、迟到旧网络图不覆盖新图。
- AVSession 写入顺序、进度不等封面、20 次进度/强制同步不产生新封面解码、清空曲目和销毁后迟到结果。
- 在线转本地保留音轨封面身份与播放位置、本地文件缺失回退、异步详情身份校验、详情未完成时音频播放入口仍能完成。

回归通过：`check-lyrics.mjs`、`check-playback-interactions.mjs`、`check-entry-page.mjs`、`check-theme-contrast.mjs`。主题对比度仍通过 7,372,830 次计算检查，最低正文 4.701:1，其余文字角色 4.636:1。

## 编译与实机边界

- 设置进程级 `DEVECO_SDK_HOME=D:\DreamMusic\.devEco-sdk-compat`，执行 `hvigorw assembleHap --no-daemon --stacktrace`（未关闭类型检查）：ArkTS、打包和签名全部通过。保留 SDK/既有代码的弃用与异常处理警告。
- 产物：`entry/build/default/outputs/default/entry-default-signed.hap`，5,059,971 字节；unsigned HAP 5,012,144 字节。
- `git diff --check` 通过。没有提交或推送工作区改动。
- 未运行全量 Hypium 测试；本次使用封面专项与相关主机回归。
- 实机图片解码/视觉、系统媒体卡片、真实网络/断网与音频播放操作：按用户明确要求跳过；主机替身测试不作为这些系统行为的实机证据。

## API 依据

- [ImageKit 图片解码与释放](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/image-decoding-V14)：按目标尺寸解码，使用完成后释放 ImageSource 与 PixelMap。
- [AVSession 开发指导](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/using-avsession-developer-V13)：通过 setAVMetadata 设置媒体图片，播放属性另行设置。
- [NetworkKit HTTP API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/js-apis-http-V5)：ARRAY_BUFFER、超时、maxLimit 和 destroy。
- 同时核对本机 API 23 SDK 的 `@ohos.multimedia.image.d.ts`、`@ohos.multimedia.avsession.d.ts`、`@ohos.net.http.d.ts`：`desiredPixelFormat/desiredSize`、Promise release、`mediaImage: PixelMap | string`、`maxLimit/usingCache`。官方网页正文读取失败时，以本机声明和实际 ArkTS 编译共同核实接口可用性。
