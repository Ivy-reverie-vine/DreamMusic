# Issue #21 验证记录

日期：2026-10-05。范围：T02 在线队列身份、实际音频下载边界与下载完成归属；前置 #20 已关闭。本记录不表示 #19 总规格或其他工单完成。

## 实现

- `createOnlineTrack` 为每次在线选择分配独立负 ID，避开队列空值 `-1`。平台数字 ID、字符串 ID 和临时 URL 都不作为队列 ID；网易目录 ID 单独保存在 `neteaseId`。
- 搜索和在线歌单/喜欢列表仍共用 `OnlineMusicViewModel.playSong`。先记录准备中的队列条目，再取得真实 `PlaybackResolution`；解析失败可以原条目重试。
- 只有实际 `playbackSource=api-enhanced`、正网易 ID 且目录/音频引用一致时，才查询旧缓存或下载入库。v1 的已定义单网易来源响应由真实 `NetEaseApi` 补全来源；v2 来源未知时不推断下载资格。
- 在线点播在缓存查询前确认实际音频；确认网易后仍复用原本地 ID、文件与收藏关联。本地音乐库直接播放不解析网络 URL。未确认的在线点播不会用目录数字 ID 猜测缓存音频。
- 下载服务再次检查资格，并下载本次实际起播解析的 URL，不重新按网易目录数字 ID 解析音频。封面/歌词使用对应角色引用。没有新增跨源离线迁移。
- 下载完成替换同时检查播放请求版本、队列选择 ID、网易 ID、实际来源、播放引用和解析 URL。URL 仅用于验证这次下载仍属于当前音频，不参与条目身份。切歌、同目录换源、原位改源和重复回调不能覆盖新状态；仅补齐封面不撤销合法下载归属。
- 同录音的音频变化保留原 Track ID、目录展示和已有收藏 ID；新的独立在线选择使用新 ID。未新增手动选源 UI 或永久录音绑定。

## 验收对照

| #21 条件 | 当前证据 |
| --- | --- |
| 跨平台数字 ID / 字符串 ID / 多瞬态条目不冲突 | `check-online-queue.mjs` 使用六个实际队列条目，包含同数字 ID、零 ID、不同字符串引用与相同资源的重复选择；逐项切歌、重排并观察队列和播放器状态 |
| 同录音保留目录和收藏，独立录音身份独立 | 同目录换音频保持本地 ID 70、标题、封面与收藏关联；新录音负 ID 不复用该收藏身份；下载/缓存命中也保持原 ID |
| 网易目录 + 非网易实际音频不误入库 | 用下载/网络/SQLite 边界构造跨源解析，观察实际 `PlayerViewModel` / `QueueViewModel` / `OnlineMusicViewModel`；断言无网易缓存查询、删除、音频下载或入库；下载服务直接拒绝跨源输入 |
| 搜索/资料入口与离线兼容 | 两入口共用同一公开 `playSong`；分别覆盖带引用选择和原 v1 资料条目；本地库无网络仍进入 PLAYING |
| 下载回调只替换对应选择 | 切歌、同目录换源、同请求原位改音频、重复完成均不覆盖新音频；合法封面补齐后可正常替换 |
| 实际客户端状态及真实网易逻辑回归 | 执行真实 ArkTS 在线、队列、播放器及 `OnlineDownloadService`；只替换 Kit、HTTP 与存储边界，检查下载实际解析 URL、文件路径、入库网易 ID、队列原位替换及播放位置；另有真实 NightDream HTTP 身份回归 |

## 已通过

六个主机检查脚本：

```text
node scripts/check-online-queue.mjs
node scripts/check-playback-recovery.mjs
node scripts/check-media-identity.mjs
node scripts/check-covers.mjs
node scripts/check-lyrics.mjs
node scripts/check-desktop-lyrics.mjs
```

`check-media-identity.mjs` 保留真实 NightDream HTTP、认证、临时服务端 SQLite、注册表与编排路径，第三方请求受控；本次新跨源结果在客户端网络/下载边界注入，不冒充服务端已实现自动换源。

API 23 完整 `assembleHap --no-daemon`（未使用 `--no-type-check`）通过，包含 ArkTS 类型检查、打包与签名。修正了首次编译发现的对象 spread 限制。签名 HAP SHA256：

```text
708569880F3881A32B843D4A951E6136FDF6CA28B29A06662195EC8796890A43
```

修改文件 `git diff --check` 通过。

## 证据边界

本轮未执行真实平台音频解码/进度、HarmonyOS 真机下载/真实客户端 SQLite、后台或锁屏验收；主机替身与 HAP 编译不替代这些证据，后续由 G7/G8 分别验收。T02 明确要求的客户端受控状态/下载边界验证已完成。

仓库原有 `build-profile.json5` 修改与 `.scratch/` 保留，不纳入本次提交。
