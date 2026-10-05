# Issue #24 验证记录

日期：2026-10-05（Asia/Shanghai）。范围：T05 完整版/试听/未知/不可用判定及普通播放门禁。前置 #21 已关闭，本票不增加自动跨平台或 Bilibili 候选，不代表 #19 的其他工单完成。

## 验收对照

| 条件 | 实现和证据 |
| --- | --- |
| 四类结论和判断依据从适配器贯通客户端 | 网关 v1/v2 扩展 audioIntegrity；保留 status、reason、目录/资源时长及 evidence。实际 ArkTS NetEaseApi 消费并存入当前音轨，封面更新/下载替换保留；旧网关缺字段明确为未知 |
| 独立可复现场景 | 真实网关 HTTP 回归网易和 Meting：显式试听对象、资源短/长、缺字段、字符串 null、空/非法 URL、返回身份不符。主机脚本另覆盖详情失败及媒体 HTTP 503 |
| 完整音频正常播放，其他结果不误报成功 | 两个客户端均 gate full；ArkTS 搜索/在线资料、队列、同资源重试共用门禁。试听/未知有可读状态、搜索重试播放按钮及既有来源展开；Web 保留结果可重新点播或切换来源 |
| 选定录音身份与终止条件 | mediaRef 只解析该资源；旧网易数字 ID 不传到另一平台。无候选结束，不引入新回退。Web 普通播放也移除旧 QQ 解灰兜底；网易/QQ 引用和目录展示回归通过 |
| 下载、本地与网易回归 | canDownloadNetEase 同时要求实际网易来源、目录与音频引用一致、可靠完整版。试听/未知/媒体失败不触发入库；既有真实客户端下载服务、队列替换、本地离线、迟到响应回归通过 |
| HTTP 到客户端决策及真实样本分开 | check-audio-integrity.mjs 执行实际 ArkTS 业务代码，HTTP/auth/SQLite/编排/adapters 为实际实现。Kit/持久化/下载边界及第三方响应受控。完整 90 秒 WAV 经真实本地 HTTP 全量读取、验证 WAV 数据长度并独立测量时长；既有试听响应形状使用 freeTrialInfo 对象回归 |

## 已通过的检查

- NightDream 全量测试 43 个文件 / 231 项全部通过；TypeScript/Vite 生产构建通过。
- `check-audio-integrity.mjs`：四类状态、HTTP 206 前段读取/完整歌词不作为证明、媒体读取失败及原引用重试、v1 网易与本地离线通过。
- `check-media-identity.mjs`、`check-online-queue.mjs`、`check-playback-recovery.mjs`、`check-aggregate-search.mjs`：原目录/实际音频/歌词身份、网易下载入库、队列与迟到响应、合并结果来源点播通过。仅替换 Kit、客户端存储/下载和第三方网络边界。
- API 23 `assembleHap --no-daemon --stacktrace`，保留完整 ArkTS 类型检查、打包及签名通过；存在工程既有弃用/可能抛异常提示，未修改构建配置或 SDK。
- 最终签名 HAP SHA256：`5507A305F7EECFD3BFED88FDA98FD0264FAB25720BE2139825A32A92916D48E4`。
- 两个仓库 `git diff --check` 通过。HTTP fixture 清理临时 SQLite；本次构建和测试临时日志收尾删除。

## 样本与设备状态

| 验证层 | 本轮状态 |
| --- | --- |
| 实际业务 HTTP / ArkTS / Web 公共状态 | 通过受控第三方响应和媒体回归 |
| 受控音频文件 | 90 秒 PCM WAV 全量读取和时长校验通过；不是平台提供的真实歌曲 |
| 真实网易/QQ/酷狗/Audius 音频 | 未执行取样，不宣称整曲成功率、试听覆盖率或平台数据形状已校准 |
| 浏览器真实 audio 解码 | 未执行；React/DOM 测试不替代真实浏览器播放 |
| HarmonyOS 真机 | hdc 检测到设备；本轮未安装/操作设备，未取得 AVPlayer 解码、原生界面、后台/锁屏证据 |

政策详见同级 `NightDream/docs/audio-integrity.md`。NetEase 按提供方实际资源时长与显式非试听标记判定；Meting/Audius 实际响应缺证据时继续未知，不把 URL、码率、文件大小或网络读取前段升格为完整。真正的来源样本与设备验收仍属于后续 G7/G8。

本次修改涉及 DreamMusic 与 NightDream 两个仓库。按用户要求关闭本票后提交并推送本票文件；既有 `build-profile.json5` 修改及 `.scratch/` 内容保留、不纳入提交。
