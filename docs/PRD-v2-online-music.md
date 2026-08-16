# PRD v2: 在线音乐接入 + 自定义背景修复 + UI 修补(IvyReverieMusic)

- 阶段: to-prd(grill-with-docs → to-prd → to-issues → implement-review;本文件为 8/16 范围记录,实施已同步落地)
- 标签: ready-for-agent
- 父级: docs/PRD-v1-local-music-player.md / docs/PRD-v1.1-visual-polish.md
- 依据: 8/16 grill-with-docs 访谈(8 问全部拍板)+ CONTEXT.md / docs/adr/0003
- 目标环境: HarmonyOS 6.1 / API 23 / ArkTS / 真机 phone(验收一律真机)

## Background

v1 只预留 api-enhanced(服务器 Profile + 连接状态),不调用业务端点。8/16 用户决定进入在线阶段,并**推翻"流式不落盘"边界**:自建播放器的歌必须存本地。连接状态契约同步作废 `/health`(ADR-0003),改为真实业务请求驱动。

## Scope(用户拍板)

### 做

1. **自定义背景图恢复 + 缓存切换修复**: PhotoViewPicker 选图 → 沙箱固定名单份存储 → 取色;`bgStamp` 奇偶重建强制 Image 重载(内置预设已真机验证的方案);内置 5 图保留为回退;新增"恢复默认背景"入口;启动恢复自定义优先
2. **在线搜索**: 音乐库页头搜索图标 → 页内全屏搜索子视图(保持五页框架);300ms 防抖、limit 30 滚动加载更多、空态/加载/离线提示
3. **在线音轨下载入库并播放**: 点结果 = 下载完成再播放;按网易云 id 去重(已在库直接播);`/song/url/v1?level=standard`;行内下载进度;失败友好提示(无版权/需会员/网络)
4. **持久化**: 音频/封面/歌词落盘沙箱,入库 `tracks`(新增 `netease_id` 列,自动迁移);队列、断点续播、收藏、歌单按普通本地音轨生效
5. **在线歌词**: 下载时 `/lyric` 落盘 `music/<id>.lrc`,复用现有 LrcLoader(本地无 .lrc 时显示)
6. **匿名游客登录**: `/register/anonimous` 拿 cookie 存 preferences;301 失效自动重取一次
7. **连接状态重构**: ADR-0003 请求驱动;移除启动+15s 轮询与 `/health` 探活;设置页"刷新"改轻量请求 `/search/hot`
8. **UI 五项改进**: ① 主题三态切换入口恢复(深/浅/跟随系统,兑现 DESIGN.md)② 删除服务器/歌单、清空最近播放加确认弹窗 ③ 最近播放可点播 ④ 背景图区域重做(预设网格窄屏溢出修复)⑤ 音乐库行改"爱心 + ⋯ 底部弹层"(添加到歌单/移除/网易云来源标记),专辑/艺术家详情行同步

### 不做

- 账号登录(二维码/手机号)、VIP 音质、音质选择(本轮固定 `standard`,高音质随账号登录轮次)
- 在线歌单同步、榜单、推荐、评论、云盘、电台
- api-enhanced 服务端 `/health` 端点(ADR-0003 取代)

## Domain(与 CONTEXT.md 对齐)

在线音轨 / 在线歌词 / 游客会话 / 自定义背景图 / 连接状态(请求驱动,ADR-0003)

## Implementation Decisions

| # | 主题 | 决策 |
| :-: | :--- | :--- |
| 1 | 自定义背景 | 固定文件名 `background/background_custom.<ext>` 单份存储;切换先清旧文件再复制;`bgStamp` 奇偶分支重建 Image;预设与自定义共用 `bgSrc` |
| 2 | 下载播放 | 串行"下载→入库→播放";行内进度(HTTP `dataReceiveProgress`);失败清残留文件 |
| 3 | 去重 | `tracks.netease_id` 唯一判定,已在库直接播放不重复下载 |
| 4 | 文件命名 | 音频 `music/<neteaseId>.<ext>`(扩展名取自直链);封面 `covers/<neteaseId>.jpg`;歌词 `music/<neteaseId>.lrc` |
| 5 | 连接状态 | 每次业务请求成败驱动三态;搜索/下载调用点上报 `markOnline/markOffline` |
| 6 | UI | 音乐库行操作收进底部弹层;设置页主题三态 + 背景区 + 删除确认统一 AlertDialog |

## Acceptance Criteria(真机验收)

- [ ] 设置页: 主题三态切换生效并持久化(重启保留);自定义背景图选择后即时切换、重启恢复;恢复默认背景回到上次内置预设;删除服务器有确认
- [ ] 音乐库: 搜索图标进入在线搜索;输入防抖出结果、滚动加载更多;点结果 → 行内进度 → 播放;同一首再次点播不重复下载;下载的歌出现在音乐库且离线可播
- [ ] 在线歌词: 下载的网易云歌在"正在播放"页显示歌词(歌词可用时)
- [ ] 连接: 设置页"刷新"显示在线/离线;断网时搜索给可读提示,本地播放不受影响
- [ ] 队列/断点: 下载的歌参与队列、断点续播、收藏、歌单

## Out of Scope(边界)

账号登录、音质选择、在线歌单同步、榜单/推荐/评论/云盘/电台;在线流式不落盘方案已被"存本地"取代。

## Further Notes

- 实现已落地: `hvigorw assembleHap` 编译通过、Hypium 55 用例全绿;真机评审为本轮硬关卡
- 相关文档: CONTEXT.md(术语与约束已更新)、docs/adr/0003(取代 0002)、docs/design/v1-api-checklist.md(网络段已更新)
