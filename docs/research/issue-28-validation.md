# Issue #28 验收记录

日期：2026-10-05（Asia/Shanghai）。范围 T09：当前队列条目手动选择已确认的同录音来源。#25 已 CLOSED。本票不代表 #19/G5/G8 或后续不同录音、Bilibili 人工确认入口完成。

## 验收对照

| 条件 | 实现与证据 |
| --- | --- |
| 已有来源选择，经统一解析播放并显示实际来源 | 搜索来源展开增加“为当前曲目使用…”；正在播放及搜索失败处共用 `SourceSelection`。通过 NightDream v2 `manual=true + mediaRef/catalogRef/searchSession` 解析；服务端核对用户、原目录、同录音分组，只解析指定来源，无客户端平台 URL 拼接 |
| 原资料与收藏/队列身份稳定 | 手动 QQ→酷狗只修改音频引用；同一 Track、队列 ID、原目录/歌词/封面/歌名/歌手保持稳定。客户端验证已有本地缓存 ID42 切到 QQ 仍保留 ID42/沙箱路径，不新建收藏条目或误入网易下载链 |
| 选择作用域及重新搜索 | Track 上保存候选快照、搜索会话与手动引用，不修改数据库或搜索结果。相同目录的两个队列条目拥有独立选择；往返切歌保留对应条目的选择；重新点播创建新条目、发送 automatic 请求，不继承旧选择 |
| 失败重试/重新选择与旧请求归属 | 编译后真实控件触发 QQ 失败重试及酷狗重新选择。QQ 试听/未知/空结果都不请求网易或酷狗兜底。解析中切到本地取消 HTTP/提供方请求，迟到结果不覆盖新曲；来源禁用、并发饱和、熔断受原控制约束 |
| 不伪造完整性/手动成功 | 只允许 full 且 URL 非空进入播放器。试听、完整性未知和不可用分类保持；失败/加载时不显示“正在使用”或实际播放来源，已选择仅表达用户指定候选，不表达播放成功 |
| 普通平台独立演示与可见交互记录 | 从聚合搜索、自动失败到编译控件展开、QQ选择、失败/重试、酷狗重新选择、重新搜索和本地切歌，经过实际 ArkTS/API/队列与鉴权HTTP网关；无需B站。控件树、文案/禁用状态及队列/引用记录见下方JSON |

## 已通过

- NightDream 全量 `npm test`：47个文件、274项通过，包含新增7项手动选择HTTP测试；`npm run build`（TypeScript/Vite）通过。测试环境原有一次 localhost:3000 连接拒绝输出未导致测试失败。
- `node scripts/check-manual-playback.mjs --record`：Hvigor编译后的真实 `SourceSelection` 控件回调 → 实际 ArkTS 播放器/队列/API → 真实 Express 鉴权/临时SQLite/来源编排与adapters。只有ArkUI渲染边界、Kit、客户端存储/下载和第三方HTTP响应受控；行为记录：[issue28-client-interactions.json](assets/issue28-client-interactions.json)。
- 自动回退、来源身份、完整性、在线队列与下载边界、播放器恢复检查均通过：`check-automatic-playback.mjs`、`check-media-identity.mjs`、`check-audio-integrity.mjs`、`check-online-queue.mjs`、`check-playback-recovery.mjs`。
- API23 `assembleHap --no-daemon --stacktrace`：ArkTS类型检查、打包、签名通过；未跳过类型检查或修改签名配置。原有弃用和可能抛异常提示仍在。
- 最终签名HAP SHA256：`1A97129B1697F88F15212D3C8C2D8099F005D22647F6B36A052B356DA5AEFF9F`，构建用时23.268秒。
- 界面沿用主题、15/12字阶与48vp控件热区；新增控件有可访问名称、加载时禁用选择、失败时可重试并保留候选。界面检测器结果为空，两仓库 `git diff --check` 通过。

## 验证边界与收尾

`hdc list targets` 为 Empty：本轮未执行鸿蒙安装、AVPlayer实际解码、原生布局/触摸、后台/锁屏或设备SQLite。没有使用浏览器或受控控件树冒充原生截图，也没有将受控 full 结果当作真实提供方整曲证明；真实来源与设备链路仍归G8验收。

仅保留可复现脚本与不含凭证/媒体URL的控件状态JSON。网关临时用户/SQLite随脚本finally清理，构建临时日志收尾移除。原有 `build-profile.json5` 和 `.scratch/` 保留、不提交。NightDream 契约见 `docs/manual-source-selection.md`；按用户要求更新checklist/评论，关闭后独立回读CLOSED，再分别提交push两个仓库本票文件并核对远端master SHA。
