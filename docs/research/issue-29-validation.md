# Issue #29 验收记录

日期：2026-10-05（Asia/Shanghai）。范围 T10：手动播放自动拒绝的其他/不确定录音及额外片段候选。前置 #27、#28 已 CLOSED。本票不代表 #19、G5 其他工单或 G8 完成。

## 验收对照

| 条件 | 实现及证据 |
| --- | --- |
| 候选显示版本、来源、额外片段，明确选择后才解析 | 正在播放/搜索失败共用 `SourceSelection`，具体分 P 显示标题、Bilibili/版本/P、视频名、拒绝原因与音频完整性；“选择候选”后仍无 playurl 请求，只有“确认播放此独立曲目”才调用统一网关。可取消选择，加载中禁用确认/选择 |
| 独立身份、资料和匹配证据 | 新瞬态 Track ID、所选资源 catalogRef/playbackRef，neteaseId=0。返回最新分 P 自己的标题/署名/视频名/封面/时长；不使用原曲或上传者冒充歌手。原库条目及收藏 ID 保留，手动候选拒绝原因/match.status 保持 manual，不生成已验证同录音绑定 |
| 匹配与完整性独立 | 网关按所选分 P 时长检查，不拿原曲时长衡量不同录音。100秒MV相对90秒原曲，受控完整音频可播放；preview/unknown/短片/失败均不交给Kit、不静默换到原曲或其他候选。完整性与用户录音选择分别记录 |
| 仅当前队列作用域 | QueueEngine 只替换当前位置，保持顺序、模式及洗牌索引。覆盖同一本地/收藏ID42重复出现、只替换第二项，邻项和原库资料不动。往返切歌保留该项选择；从搜索再点原曲新建条目并重新 automatic 解析 |
| 额外片段不套原曲时间轴 | 当前候选没有适配歌词：lyricsMode=none，清空 lines/activeIndex/lyricsRef/lyricsSource，更新revision，显示暂无歌词；不请求原曲歌词或猜MV偏移，迟到旧歌词不能恢复同步状态 |
| 候选选择、失败、切歌和真实演示 | 编译的实际控件回调串到ArkTS状态/API/队列/歌词与鉴权HTTP网关，覆盖确认/取消、身份切换、preview/unknown/短片/失败重试、重复队列隔离、重新搜索、慢音频取消和旧歌词迟到。另有真实网易搜索→自动B站拒绝→手动确认→真实playurl样本；没有新增独立B站浏览器或歌词编辑器 |

## 已通过

- NightDream `npm test`：48文件、281项通过，含新增7项其他录音HTTP测试。三组T08/T09/T10定向共32项通过；TypeScript/Vite `npm run build`通过。原有Controls测试localhost:3000连接提示不影响测试结果。
- `node scripts/check-other-recording.mjs --record`：实际Hvigor编译的 `SourceSelection` → 实际ArkTS播放器/队列/歌词/API → 实际Express鉴权/临时SQLite/编排/适配器。记录：[issue29-client-interactions.json](assets/issue29-client-interactions.json)。ArkUI渲染、Kit媒体、客户端存储/下载及第三方回复受控，不能代替设备布局、触摸或音频解码。
- 同录音选源、自动播放、媒体身份、音频完整性、在线队列/下载、拖拽/播控、播放恢复、歌词和系统歌词回归通过：`check-manual-playback`、`check-automatic-playback`、`check-media-identity`、`check-audio-integrity`、`check-online-queue`、`check-playback-interactions`、`check-playback-recovery`、`check-lyrics`、`check-desktop-lyrics`。
- 最终API23 `assembleHap --no-daemon --stacktrace`：ArkTS类型检查、打包和签名通过，25.159秒。最终签名HAP SHA256：`18E0116077DC53D9B5264F902C60B4BAA1BFDAFB322AF3643BCE8C9EB600156E`。沿用本机已有签名配置，未跳过类型检查；原有弃用/可能抛异常提示仍存在。
- 沿用ThemeService、15/12字阶、48vp控件和自然换行，界面静态检测器结果为空；依据用户禁止子Agent要求由本Agent复核并按实际实现补记既有DESIGN.md。编译控件树可见状态有证据，原生像素布局未验证。两仓库 `git diff --check`通过。

## 真实来源演示

运行 `node scripts/check-other-recording.mjs --live --record`，使用实际本地api-enhanced上游与真实Bilibili HTTP，没有第三方假回复。临时账户/SQLite只用于本地隔离鉴权；Kit和ArkUI边界受控，不能称为真实设备播放。

- 原目录：网易18520488，Never Gonna Give You Up / Rick Astley。实际自动解析拒绝后展示具体B站手动候选。
- 人工选中：[BV1KR4y1w7A3 / P1](https://www.bilibili.com/video/BV1KR4y1w7A3/)，CID723641888，标题“【sky光遇】 Never gonna give you up 完整版sky studio 整活专用 语瞳原创”；原因 `recording_provenance_missing`，match仍为manual，没有因标题含“完整版”而当作已确认同录音。
- 选择候选阶段不请求playurl；明确确认后请求该资源的view/playurl。独立目录/队列身份切换成功，neteaseId=0，旧同步歌词清空。
- 该分P时长251000ms，资源250602ms，缺显式非试听证据，`audioIntegrity=unknown / missing_evidence`；生产播放器正确停在 `ERROR / AUDIO_UNKNOWN`，没有进入媒体解码，也没有宣称full成功。真实调用13次。完整性拒绝与录音选择分别生效。
- 脱敏记录：[issue29-real-selection.json](assets/issue29-real-selection.json)，包含实际控件状态/归属/完整性与HTTP路径，不含账户凭证、媒体直链或代理签名。

本轮真实样本展示自动拒绝、人工选择和完整性拒绝；full独立候选的播放分支由受控第三方边界下的实际HTTP/ArkTS业务验证。没有本轮真实full整曲、浏览器媒体或鸿蒙设备播放证明；上述缺口留在G8，不拿#26历史播放替代本轮验收。

## 收尾与状态

`hdc list targets`为空，未执行安装、AVPlayer解码、原生布局/触摸、后台/锁屏与设备SQLite。来源默认关闭；没有改变原网易下载边界或新增跨源离线入库。

仅保留复现脚本和脱敏JSON。临时网关账户/SQLite由finally清理，本轮api-enhanced进程与构建/测试日志收尾清除；原有 `build-profile.json5` 和 `.scratch/multi-source-matching/` 保留、不提交。网关契约见NightDream `docs/manual-other-recordings.md`。按用户要求更新Issue清单/评论、关闭并独立回读CLOSED，再分别提交push两仓库本票文件，核对远端master SHA。
