# Issue #30 验收记录

日期：2026-10-05（Asia/Shanghai）。范围 T11 / G6 原目录歌词切片；前置 #25 已 CLOSED。
本票未接 LRCLIB，不表示 #19、G6 其余工单或 G8 完成。

## 验收对照

| 条件 | 实现与证据 |
| --- | --- |
| 原目录取词、返回实际来源 | NightDream 接受 catalogRef/playbackRef 的独立歌词契约，唯一请求原平台自己的 ID；网易目录→自动 QQ 完整音频→网易歌词由真实 HTTP/鉴权/SQLite/注册表/adapter 和客户端 API 串联。另覆盖 Bilibili 音频、同平台不同 ID 和 QQ 目录；不把音频 ID 传进原平台 |
| 起播独立、明确失败状态 | 歌词返回 available/missing/instrumental/unsupported/unavailable/timeout/failed/cancelled；来源预算最大 5 秒，实际音频请求不用等歌词。客户端 LOADING、超时、失败、不支持、空结果时仍 PLAYING；失败不标绑定全局失效、不自动请求其他歌词平台 |
| 内容与时间轴分开 | 同具体资源时间标签才 trusted；跨资源或纯文本 uncertain，静态显示并禁用跟随/高亮。编译的 NowPlayingPage 文本、样式决策和滚动调用受到验证；纯音乐只有提供方明确标记才显示。系统桌面歌词同步内容及时撤回 |
| 切源/切歌与缓存 | 按目录/实际音频关系缓存，切源重算。特别覆盖队列自动重解析：原目录歌词先变为 trusted，随后解析到 QQ 音频，播放器更新来源后通知歌词重新加载，撤回原同步状态。切到本地会取消 HTTP/上游，故意忽略取消的迟到成功仍不能覆盖新歌 |
| 原平台成功直接返回 | 正常结果只有一次原平台取词，无 LRCLIB 或音频平台歌词请求；fallback.implemented=false 保留真实后续回退状态。空結果提示暂无歌词，不冒充纯音乐或已穷尽 LRCLIB |
| HTTP 与客户端显示验收 | 新增9项 HTTP 测试、Web来源/高亮/换源/迟到状态测试及 check-catalog-lyrics。后者执行真实 ArkTS 状态和 Hvigor 编译歌词组件，覆盖同步→静态、正文、空、纯音乐、不支持、超时、失败及取消。Kit/存储/第三方 HTTP 与 ArkUI渲染原语受控 |

## 验证结果

- NightDream `npm test -- --maxWorkers=2 --minWorkers=2`：49 个文件、296 项通过。首次默认高并发全量测试有一项既有 Bilibili 总预算用例 252ms 超过 250ms；降低验证并发后通过，没有放宽业务或测试阈值。现有 Controls 的 localhost:3000 连接提示不影响测试退出结果。
- NightDream TypeScript/Vite `npm run build` 通过。
- HarmonyOS `assembleHap --no-daemon --stacktrace` 通过，包含 ArkTS 类型检查及本机配置签名。没有使用 `--no-type-check`。
- `check-catalog-lyrics`、`check-lyrics`、`check-media-identity`、`check-desktop-lyrics`、`check-system-playback`、`check-other-recording`、`check-playback-recovery`、`check-automatic-playback` 主机检查通过。
- 两仓库 `git diff --check` 通过。

## 验证边界与收尾

真实 HTTP 指真实监听的 Express 入口与实际业务编排，第三方平台回复受控；不是本轮公开平台歌词命中率或整曲播放证据。
编译歌词组件验证显示/高亮/跟随决策，不替代设备像素布局、触摸、媒体解码、后台/锁屏或真实设备 SQLite；本轮未宣称这些通过，保留在 G8。
没有接入 LRCLIB、跨源下载入库、永久来源选择或自动偏移校正。

临时测试网关/账号/SQLite 均在 finally 清理。复现脚本和本记录作为持久证据；原有 build-profile.json5 签名配置与 .scratch 保留且不提交。
契约与网关复现见 NightDream `docs/catalog-lyrics.md`。按用户授权更新清单、关闭并独立读回 CLOSED，再提交并 push 两仓库本票文件并核对远端 master SHA。
