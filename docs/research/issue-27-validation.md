# Issue #27 验收记录

日期：2026-10-05（Asia/Shanghai）。范围 T08：音乐平台失败后的 Bilibili 自动搜索、保守录音判定和共享预算回退。前置 #25/#26 已 CLOSED。本票不代表 #19/G4 全部完成，手动交互及真实音频/鸿蒙全链路验收属于后续工单。

## 验收对照

| 条件 | 实现与证据 |
| --- | --- |
| 常规成功不搜索，失败/阶段到期后共用10秒 | 复用音乐平台编排，失败后接续原始 deadline；默认7秒平台阶段、3秒预留。实际 HTTP 覆盖平台成功、提前耗尽与阶段超时接续B站、总超时及迟到full拒绝 |
| 原目录信息生成候选，保留BV/CID/P与证据 | 真实WBI搜索、pages枚举、具体引用；以原目录署名/版本/时长判定。真实search缺dt，使用原资源已核对ID的提供方详情时长补足。UP主只作为uploader |
| 不确定/额外片段/完整性未知不自动通过 | 原目录链接、唯一歌曲署名、原专辑音轨声明、精确分P标题与严格时长共同作为元数据证据；翻唱/Live/MV/Remix/谱例/变速等被拒，未提供非试听证据仍unknown；不取第一条B站结果兜底 |
| 来源可见、原资料稳定、失败返回手动候选 | 受控HTTP与实际ArkTS证明P2成功保留原目录/封面/歌词身份、实际显示Bilibili、非网易不下载；失败音轨保留完整候选、具体引用、完整性及拒绝理由。手动选择UI属#28 |
| 切歌取消，来源控制有效 | HTTP断开取消B站playurl，客户端切到本地后旧结果不覆盖；来源禁用/熔断/饱和/中途关闭不能继续，缺代理终止；取消不污染熔断计数 |
| 实际HTTP各终态与真实回退样本 | 真实业务HTTP与受控第三方回复覆盖平台成功、平台失败后B站P2成功、手动、无候选、总超时；真实提供方样本见下表，无已知BV直连或假响应混入真实记录 |

## 本轮真实网络

通过本地原api-enhanced服务 → 临时本地鉴权/SQLite → NightDream实际编排/adapters；仅启用网易与B站，QQ/酷狗未启用。搜索、URL、详情、nav/WBI与B站pages均为真实提供方HTTP。自动候选没有通过门禁，因此不请求其音频、不主动播放，不能宣称真实B站自动成功或整曲完整。

| 实际所选目录 | 观察 |
| --- | --- |
| 网易2652820720 · Lucky小爱 · 晴天(深情版) | 搜索“晴天 周杰伦”实际第一条是该独立版本，不是周杰伦原录音；仅点播自身。详情/音频278961ms、非试听字段，full/success，服务端497ms，HTTP501ms；仅请求网易search/URL/detail，没有B站HTTP。未在浏览器播放 |
| 网易18520488 · Rick Astley · Never Gonna Give You Up · Whenever You Need Somebody | 搜索dt缺失，原资源详情214018ms；URL返回20035ms试听，preview/explicit_trial。自动接续真实B站WBI搜索，读取5个视频的具体分P，服务端1196ms、HTTP1198ms、剩余8804ms，终态exhausted/bilibili_manual_candidates |

| 自动发现的具体候选 | 分P时长 | 拒绝理由 |
| --- | --- | --- |
| BV1qbHGzqEZm / CID32815582193 / P1 · 动态鼓谱 | 211000ms | 谱例/额外内容，不自动接受 |
| BV1KR4y1w7A3 / CID723641888 / P1 · sky studio琴谱 | 251000ms | 缺原目录录音关联；“完整版”字样不算证明 |
| BV1eb4y1U7kH / CID390123721 / P1 · 慢速降调/环绕 | 269000ms | 改变录音播放版本 |
| BV14g4y1m7dv / CID1407309523 / P1 · 二胡谱示范 | 223000ms | 谱例/表演不自动接受 |
| BV1xt4y1679q / CID285777816 / P1 · 8D环绕 | 203000ms | 处理后的不确定录音 |

可复查的脱敏JSON：[issue27-real-fallback.json](assets/issue27-real-fallback.json)。同时保留5条BV发现提示（尚未取得CID时也可报告），所以响应共10项候选记录；不是10段通过判定的音频。早期一次未选中指定原曲ID被记为目录搜索失败，一次B站返回空候选；没有用该结果冒充成功。稳定复查记录的是上表本轮结果，网络/曲库状态可变化。

判定政策是保守元数据与来源署名，不是音频指纹证明。B站通常不提供显式非试听证据；目前正常真实响应仍可能unknown，自动成功分支用受控第三方字段验证。尚未取得本轮真实同录音full成功，保留为G8验收缺口，不能把#26已知BV的历史播放当作自动匹配成功。

## 已通过与未执行

- NightDream：全量46个文件/265项通过，TypeScript/Vite生产构建通过；随后增加2个场景（搜索缺时长/不完整风险响应、录音元数据与来源中途变化），最终定向18项全部通过。没有把新增后的总数冒称为已重跑的全量结果。
- 实际ArkTS `check-automatic-playback.mjs`：音乐平台+B站full门禁、手动候选保存、实际来源文字、原目录/封面/歌词/队列身份、非网易下载隔离、B站解析中切到本地取消、迟到拒绝及原网易下载回归通过；Kit解码/客户端SQLite/下载是受控边界。
- `check-media-identity.mjs`、`check-audio-integrity.mjs`通过，包括旧v1、本地离线、unknown不送生产播放器及同资源恢复。
- API23 `assembleHap --no-daemon --stacktrace`：ArkTS检查、打包、签名成功（37.506秒），没有跳过类型检查或改签名配置。工程原有弃用/异常提示仍在。
- 签名HAP `entry/build/default/outputs/default/entry-default-signed.hap` SHA256：`444876C80AEBA33C4B080BB40DBB39693D5DCAF07F25B9F2F8C4C19F4148F165`。
- `hdc list targets`为空：未执行鸿蒙安装、AVPlayer、后台/锁屏、原生触摸和设备SQLite；未执行本轮浏览器自动回退音频解码。以上不由主机或构建结果替代。
- 两仓库`git diff --check`通过。临时账户/SQLite在夹具finally清理；真实取样服务、原始临时日志/JSON和issue文本收尾移除，只保留脚本及脱敏JSON。原有build-profile.json5与.scratch/保留、不提交。

运行配置与接口见同级NightDream `docs/bilibili-fallback.md`。按用户要求更新checklist/评论、关闭并独立回读CLOSED后，分别提交/push NightDream与DreamMusic本票文件，并核对远端master SHA。
