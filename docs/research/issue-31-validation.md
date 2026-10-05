# Issue #31 验收记录

日期：2026-10-05（Asia/Shanghai）。范围 T12 / G6；前置 #30 已独立读回 CLOSED。

| 验收条件 | 结果与证据 |
| --- | --- |
| 原目录 → LRCLIB 顺序 | 原适配同步/纯文本与纯音乐直接返回，缺失/不适配再查公共 LRCLIB；实际 HTTP 测试检查请求顺序和无其他歌词平台 |
| 原曲元数据与候选校验 | 服务端取原目录会话或详情，以歌名/歌手/专辑/秒时长 get→search，复用严格录音策略；拒绝错误歌手、Live、专辑/时长冲突、缺失时长和搜索歧义，不使用视频/UP 主字段 |
| 文本/同步/纯音乐/缺失/失败 | 状态与实际歌词身份独立保存；严格匹配、有效同步标签且音频为同具体目录资源时 trusted，其余静态。实际 HTTP、Web、编译的 ArkTS 歌词组件检查正文、来源、提示、高亮及滚动决定 |
| 缓存、换源、切歌和重试 | 提供方内容缓存不保存时间轴结论；两端按目录/音频隔离，不缓存失败或可重试的静态升级。实际 ArkTS 与 Web 重试取得新词且音频不重启；切歌取消及忽略取消的迟到成功不会覆盖显示或写入缓存 |
| 真实业务 HTTP 与客户端 | Express/鉴权/临时 SQLite/注册表/adapter → 生产 API/队列/歌词状态；测试第三方边界受控。浏览器生产 NowPlaying 的同步、静态、纯音乐、空、失败、重试成功有状态和截图；没有新增长期自建服务 |
| 真实 LRCLIB 小样本 | 4 条业务样本：七里香同步命中、合成不存在条目 get404/search空、Rick Astley/晴天预算超时；保留文本类型和失败状态，未外推中文覆盖率 |

## 验证

- NightDream 全量 50 文件 / 309 项通过；随后新增两个缓存反例，相关 4 文件 / 56 项通过。最终只调整静态可读性，再验证 NowPlaying 13 项与 TypeScript/Vite build 通过。
- HarmonyOS `assembleHap --no-daemon --stacktrace` 通过，包含 ArkTS 类型检查与当前本机签名；没有关闭类型检查。
- `check-catalog-lyrics`（T11+T12）、`check-lyrics`、`check-media-identity`、`check-desktop-lyrics`、`check-system-playback` 通过。
- 两仓库 `git diff --check` 通过；保留已有 build-profile.json5 和 .scratch，不纳入提交。
- 浏览器默认桌面与 390×844 手机尺寸检查；重试按钮 48px，错误/静态文字提高到白色 75% 透明度。保存 JPEG 原生截图，同步桌面 1280×720、静态快照 390×219、失败重试手机 390×844。

真实公共服务样本、端点状态及元数据类型见 NightDream `docs/lrclib-live-2026-10-05.json`；源码、契约、复现和截图索引见 `docs/lrclib-fallback.md`。
本票不表示 G7/G8 或父 #19 完成；真实完整媒体播放、鸿蒙触摸/像素布局、后台/锁屏和设备 SQLite 未在本票验收。
真实样本没有仅普通文本或纯音乐命中，对应行为经受控 HTTP/客户端验证；请求超时不会改记未命中。

临时浏览器页面已删、服务已停；常规测试和实时采样网关自动清理 SQLite。
两个浏览器 QA 临时数据库目录的删除被自动审批拒绝（blocked by policy），仍留在系统 Temp：dreammusic-identity-vjXgku、dreammusic-identity-xABt5o；不进入任何仓库提交。
