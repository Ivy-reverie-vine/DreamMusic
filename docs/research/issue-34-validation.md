# Issue #34：真实来源与浏览器验收进展

日期：2026-10-06，Asia/Shanghai。**T15 的关键真实场景已完成。** 前置 #29、#31、#32 已读回 CLOSED；仅关闭本票，不修改父 #19 或 #35 真机验收。

## 最终验收

| 场景 | 结果 | 真实证据 |
| --- | --- | --- |
| 三平台聚合与普通完整版 | PASS | 首轮网易/QQ/酷狗均ok、同录音元数据合并；网易33984241实际播放至89.07068s ended，整文件3565236字节/FFmpeg解码通过 |
| 明确试听 → B站自动成功 | PASS | 网易18520488真实26827ms试听，随后真实WBI搜索发现BV1GJ411x7h7:137649199；没有指定BV替代搜索。原目录试听与候选约24秒指纹对齐，195个哈希，平均位差3.4923、P95=6，严格标题/版本/时长检查通过；4973ms返回bilibili_full_recording |
| 自动资源完整性与原生媒体 | PASS | 完整读取1167163字节并解码为212394.75ms实际PCM；浏览器duration212.393833s、playing/readyState4，进度持续推进。目录仍为网易18520488，实际音频引用为上述B站BV/CID，下载入口不转入旧网易链 |
| 自动拒绝 → 手动独立完整播放 | PASS | 搜索发现的BV1KR4y1w7A3:723641888因录音出处不足保持manual。选择阶段不请求playurl；明确确认后实际读取2108684字节，完整解码250602.833ms，浏览器完整播放至250.6025s ended。目录/播放改为独立B站身份，原曲歌词时间轴不应用 |
| 原平台同步歌词 | PASS | 首轮网易2652820720，原平台available/trusted、实际playing与高亮；样本是Lucky小爱的晴天(深情版)，不是周杰伦录音 |
| 真实缺词 → LRCLIB普通文本 | PASS | 网易1465951 / Ian Dury / Profoundly in Love with Pandora，原平台歌词确实为空；真实LRCLIB25549173，plain/uncertain，生产NowPlaying显示来源与静态提示，原生播放进度至69.518s继续推进 |
| 真实缺词 → LRCLIB同步 | PASS | 网易2673931252 / Sweet Gene Vincent，原平台仅有作词/作曲JSON头，无正文；清理元数据头后真实LRCLIB34577799，synced/trusted。原生playing、进度及整曲221.053333s结束记录；组件使用同步时间轴 |
| 真实歌词未命中 | PASS | 网易36578812 / I Want to Be Straight，原平台为空；真实LRCLIB get404后search候选校验无匹配。生产界面“暂无歌词”，音频仍playing、进度79.909s、readyState4，无媒体错误。不是合成不存在条目 |
| 实际公开音频的URL恢复 | PASS | 自动B站音频的本地短签名自然到期后，诊断页用cache-busting重载强制实际HTTP；旧代理返回404，生产PlayerProvider调用recover=true，3321ms重新解析相同BV/CID并完整检查，媒体新请求200、恢复到52.871s后推进至136.871s。恢复凭据保留原目录/实际引用，已验证音频SHA重新一致；不是本地WAV替身 |

最终证据在NightDream `docs/evidence/`：`issue34-complete-media-live.json`（手动整曲）、`issue34-real-lyrics-browser.json`（真实plain）、`issue34-lyrics-complete-live.json`（真实synced/missing）、`issue34-final-live.json`（自动成功及真实音频恢复）。`issue34-final-checkout-live.json`保留后续独立轮次遇到的B站v_voucher风控失败，不删除或改记成功。

对应截图：[自动匹配播放](assets/issue34-bilibili-auto-playing.png)、[手动播放](assets/issue34-bilibili-manual-playing.png)、[手动整曲结束](assets/issue34-bilibili-manual-ended.png)、[真实文本回退](assets/issue34-lrclib-real-plain.png)、[真实同步回退](assets/issue34-lrclib-real-synced.png)、[真实未命中且继续播放](assets/issue34-lrclib-real-missing.png)。自动恢复的HTTP及原生error/playing/位置序列以`issue34-final-live.json`为准。

## 修正与最终检查

- B站无试听字段时增加完整AAC读取、FFprobe音频容器检查及FFmpeg整文件PCM解码；以实际样本数衡量时长，不能用容器声明、时间戳空洞、前段Range或用户同意证明full。显式试听仍先拒绝，截断/不完整/解码失败/超限/缺引擎仍未知；共享原来源/自动预算，临时文件由唯一目录清理。
- 自动录音判定增加原目录实际试听的Chromaprint音频证据；只取身份核对正确的明确试听，绑定目录引用，至少150个且足够多样的哈希，已声明试听位置附近最多1秒对齐偏差，平均位差≤4、P95≤8；另需标题/署名顺序、版本与目录/分P时长一致。Live、Cover、Remix、变速、对白/额外片段仍拒绝。普通MV标签只有声音证据通过时才可通过，不凭官方UP或关键词判定。回退所用试听不作为完整播放成功。
- 原目录搜索缺时长等字段时补取该引用详情；网易JSON元数据头没有正文时按missing继续LRCLIB，不把作曲信息作为歌词。同步/静态/空歌词均由生产组件显示。
- 新证据字段同步Web/ArkTS类型；自动恢复保存已确认文件摘要，再解析同一资源时须重新完整检查且摘要一致，变化则明确拒绝，不静默换源。
- NightDream全量54文件/335项通过；随后新增截断媒体与错资源试听两个反例，相关4文件/40项通过。首次全量发现T10旧断言把验证所选媒体的GET误当换源，修正为只允许该媒体地址，单项与全量复测通过；未放宽unknown/preview门禁。
- TypeScript/Vite build、诊断入口严格类型检查、JS语法及两仓库diff检查通过。ArkTS automatic-playback、catalog-lyrics、audio-integrity、URL-recovery主机检查通过；T05旧失败断言更新为T13的“两次恢复后失败”并检查次数、身份和零下载。
- API23 `assembleHap --no-daemon --stacktrace`的类型检查、打包及当前本机签名通过，62.838秒；没有跳过类型检查，保留既有警告。没有宣称真机AVPlayer/后台/锁屏、#35或父#19完成。Docker daemon未运行，容器构建未执行；Dockerfile已声明FFmpeg依赖，本轮引擎与浏览器在Windows主机验证。

## 时序和边界

自动解析4973ms以及第二轮2931ms均在10000ms总预算内；播放器交接到首个playing300ms，后续缓冲和恢复单独记录。手动解析1556ms，其中完整媒体检查1321ms，交接后424ms起播。诊断页预取歌词用于日志，点击到playing含搜索/歌词/登录，不能全部当作解析时间。

B站部分真实搜索仍返回HTTP200/code0/v_voucher且缺result，后续轮次明确记录exhausted / BILIBILI_SEARCH_INCOMPLETE。少量样本不代表来源稳定率或曲库覆盖率。自然到期的是本地代理签名；人为重载触发了失效，不声称B站上游自然过期成功率。早期受控410/WAV记录仍保留，并与本轮真实公开音频分开。

来源生产默认开关保持不变。复现见NightDream `docs/matching-live-validation.md`与`docs/bilibili-fallback.md`。临时服务、侧车、SQLite、媒体及不用的探针收尾清理；原有build-profile.json5/.scratch不纳入提交。

## 首轮历史结果（当时未完成，缺口现已补齐）

| 场景 | 结果 | 本轮证据与限制 |
| --- | --- | --- |
| 网易 / QQ / 酷狗聚合搜索 | PASS | 三来源均 `ok`；QQ 与酷狗“晴天 / 周杰伦 / 叶惠美 / 269000ms”合并，独立引用保留；Remix、其他歌手及证据不足条目保持独立。新 followup 报告保存专辑和时长，可按 `metadata-strict-v1` 复核 |
| 常规可靠完整版 | PASS | 网易33984241，Scheming Weasel (faster version) / Kevin MacLeod；目录与实际引用一致，提供方时长89070ms且明确非试听；生产 PlayerProvider/API/NowPlaying → 浏览器原生解码 |
| 整曲媒体与实际播放 | PASS | 浏览器从0播放到89.07068s，`ended=true`、无媒体错误；另作完整GET，HTTP200、3565236字节与Content-Length一致、SHA256 `f4d7bc55b5080f3d796d1608817fe720cda3bc39c4fa830809dd36d86c84971c`，FFmpeg `-xerror` 整文件解码退出0。不是Range前段检查 |
| 明确试听继续回退 | PASS | 网易18520488，Never Gonna Give You Up / Rick Astley；目录214018ms、实际26827ms、`provider_trial` → `preview / explicit_trial`；随后真实nav/WBI搜索及五个视频分P检查，未把试听送入播放成功分支 |
| B站自动匹配成功 | BLOCKED | 五个具体分P都因录音出处/声明缺失或鼓谱、变速等不同录音/额外片段被保留为manual，没有满足自动同录音与full的真实样本。没有已知BV直连替代自动匹配；未降低匹配或完整性标准 |
| 自动拒绝后手动选择 | PARTIAL / BLOCKED | 浏览器先选实际候选 `BV1KR4y1w7A3:723641888`，此时playurl调用数为0；明确确认后才真实请求view/playurl。返回独立B站目录/播放身份、空歌词身份、`lyricsMode=none`；251000ms分P / 250602ms资源，但缺明确非试听证据，仍为`unknown / missing_evidence`，停止解码。**手动选择已发生，真实完整候选播放未通过** |
| 原平台歌词与同步展示 | PASS | 真实搜索选网易2652820720，晴天(深情版) / Lucky小爱；实际音频来自该条目，原平台歌词`available / trusted`，LRCLIB skipped。原生playing、来源与歌词截图，进度推进、当前行高亮；不是周杰伦原录音 |
| 原平台缺词 → LRCLIB真实公开同步命中 | PARTIAL | 本轮真实LRCLIB：Rick Astley、晴天、七里香均同步命中，业务返回静态时间轴`uncertain`。沿用既有隔离采样器，**目录元数据和原平台缺词条件受控**；没有把此记录计为完整真实音频链路成功 |
| LRCLIB普通文本 | NOT EXECUTED | 本轮没有仅普通文本真实命中样本；既有受控测试不替代本票真实验收 |
| LRCLIB未命中 | PARTIAL | 合成不存在条目向真实LRCLIB发出get→404、search→空，返回missing。是明确标注的合成探针，不是实际曲库缺词成功证据 |
| 原生URL恢复 | PASS（受控故障） | 本轮重跑 #32 的生产播放器入口：实际HTTP410 → 强制重解析同一引用 → HTTP媒体字节 → `playing / readyState=4 / paused=false`，进度推进到33.937s。目录/实际身份保留、revision=1。提供方回复及410受控，90秒WAV是本地合成音频 |
| 公开来源自然过期恢复 | NOT EXECUTED | 未取得自然过期故障样本；不把受控410推导成公开平台恢复成功率 |
| B站搜索风控 | OBSERVED FAILURE | 单独一次真实调用HTTP200/code0，但data只有`v_voucher`、result缺失，返回`BILIBILI_SEARCH_INCOMPLETE`。另一次可取得候选；如实保留两轮，不推导为无结果或始终可用 |

## 时间与预算

- 完整样本第一轮聚合搜索2814ms，自动解析5ms（同一隔离上游进程此前取过该条目，可能命中上游缓存），报告总预算10000ms、音乐阶段7000ms；B站未执行。点击到原生playing3069ms包含登录、搜索、歌词预取和缓冲，不能全部计为音频解析。
- 真实试听第一轮搜索1338ms、自动解析1182ms；最终followup为搜索1497ms、解析1192ms，均进入实际B站搜索。manual具体资源解析206ms，结果unknown。
- 原平台歌词样本搜索3488ms、自动解析434ms；**URL交给生产播放器后到原生playing490ms**单独记录为媒体准备/缓冲。总点击到playing4771ms。后续媒体进度不算解析预算。
- 完整GET及离线解码3669ms是整曲检查时间，不计入自动解析/播放缓冲。上述只是少量样本，不能外推10秒性能或来源覆盖率。

## 耐久证据

NightDream 仓库 `docs/evidence/`：

- `issue34-live.json`：三平台搜索、完整样本原生playing→ended、整曲GET/解码、真实试听→B站五个具体分P拒绝。
- `issue34-followup-live.json`：保留合并依据的专辑/时长、原平台同步歌词、媒体交接后缓冲、实际手动选择解析与unknown。
- `issue34-manual-live.json`：单次真实B站风控响应，不能当作自动/手动播放成功。
- `issue34-lrclib-live.json`：真实公共LRCLIB + 受控原平台缺词条件；明确记录合成未命中探针。

本仓库原生截图：[实际播放](assets/issue34-live-playing.png)、[完整播放结束](assets/issue34-live-ended.png)、[试听回退拒绝](assets/issue34-live-trial.png)、[原平台歌词](assets/issue34-live-lyrics.png)、[手动待确认](assets/issue34-manual-selected.png)、[手动完整性未知](assets/issue34-manual-unknown.png)、[受控恢复](assets/issue34-controlled-recovery.png)。

受控恢复本轮JSON：[原生事件/进度](assets/issue34-controlled-recovery.json)、[业务与媒体HTTP](assets/issue34-controlled-http.json)。没有沿用旧单源截图作为本票新链路成功证据。

JSON按白名单保存身份、元数据、状态与耗时；账户凭据、恢复凭据、代理签名、媒体直链不写入。媒体请求路径用`[media path redacted]`代替。临时媒体文件、临时SQLite、侧车和验收服务收尾清理，既有build-profile.json5与.scratch保持原样。

## 本轮检查及完成条件

- NightDream `npm run build`通过；验收入口经实际Vite与浏览器执行。JS复现脚本语法检查通过。
- 相关自动回退、LRCLIB、播放器恢复回归：3文件 / 34项通过（两个worker）。受控测试的B站full分支不计入上述真实场景PASS。
- 本轮没有改HarmonyOS应用或网关业务判断，没有把主机测试当真机验收；#35设备验收不在本票范围。

上述为首轮历史边界，不代表最终状态；当时的真实B站与LRCLIB缺口已按本页开头的最终验收补齐。
