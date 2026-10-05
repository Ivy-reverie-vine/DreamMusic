# Issue #34：真实来源与浏览器验收进展

日期：2026-10-06，Asia/Shanghai。**本票未完成，必须保持 OPEN。** 前置 #29、#31、#32 已读回 CLOSED；未修改父 #19 或其他目标。

## 本轮逐场景结果

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

复现见 NightDream `docs/matching-live-validation.md`。继续关闭本票前，必须取得通过现有录音与完整性规则的**真实B站自动成功、手动完整音频播放**，补齐**LRCLIB普通文本及真实缺词回退的浏览器状态**。当前只有部分场景通过，按本票第六项要求不能关闭为全部完成。
