# Issue #23 验证记录

日期：2026-10-05（Asia/Shanghai）。范围：T04 同录音搜索结果合并及原平台来源展开。前置 #22 已关闭；本记录不代表 #19 总规格或自动换源、完整版播放、真实平台及真机验收已完成。

## 实现与验收对照

| #23 验收条件 | 本轮实现与证据 |
| --- | --- |
| 保留可用证据和平台引用，标题/时长不能单独证明匹配 | NightDream 保留完整标题、全部歌手、专辑、时长、版本副标题、可用原始标题，以及每项具体 mediaRef/三角色引用。严格政策同时要求标题、全部歌手集合、专辑一致和正数时长近似；缺任一证据独立显示 |
| 同名异曲、Live/翻唱/重录/伴奏/Remix/变速不误合并 | 20 组正反样本经过实际 HTTP/认证/SQLite/编排/adapters：2 组标准录音合并，包括歌手顺序相反；18 组反例独立，包括不同/缺歌手、少一位合作歌手、不同/缺专辑、缺时长、偏差、版本词、未知括号、副标题中隐藏的 Live、原标题中未解释的额外限定。纯逻辑补查组内成对匹配与歧义不取第一组 |
| 展开来源并点播，选定展示身份稳定 | 实际 ArkTS group/toggle/select 方法及 OnlineSearchView.playEntry 执行真实 HTTP 解析；从展开来源选择 QQ 后，播放器/队列保留选定目录、标题、全部歌手、歌词引用和实际来源。后到酷狗、分页、重试及来源优先级改变均不覆盖该选择；非网易不进入网易下载链 |
| 跨页/重试补来源不重复、不丢条目；候选可追溯 | 网关用户/关键词/limit 隔离的 searchSession 返回完整快照，按具体 mediaRef 去重，组 ID 取首次条目且不改变。客户端保存 selectedRef 与展开状态，93 项原条目对应 30 组合并结果及 3 条独立 Live。重复页不追加；丢响应重试可恢复快照；会话失效保留列表，显式重新搜索不改已点播条目 |
| 明确样本校准，未知保留，不取第一条兜底 | metadata-strict-v1：仅 NFKC/空白/大小写归一化，完整标题、全部歌手集合、专辑都相等，时长差 ≤ min(2000ms, 较短时长×1%)；版本/别名/未知括号拒绝自动合并。所有成员须成对匹配，防止链式时长漂移；可匹配多个组时独立保留 |
| 实际 HTTP 搜索与客户端展开/点播验证合并、反例、分页 | server/proxy.recording.test.js 使用真实业务 HTTP；扩展 scripts/check-aggregate-search.mjs，将实际 ArkTS API/搜索/组件普通交互方法/队列/播放器接入该网关。只替换第三方 HTTP、Kit 和客户端持久化/下载边界，没有替换业务匹配/编排。另用实际安装的 @meting/core 搜索 formatter 验证时长、QQ Live 副标题、酷狗被截掉的原文件名版本，经真实聚合 HTTP 形成三来源标准录音组及两条独立 Live |

## 已通过

- NightDream `npm test`：42 个文件 / 205 项全部通过。既有 Web 测试有可预期的本地 3000 端口拒绝日志，断言均通过。
- NightDream `npm run build`：TypeScript 与 Vite 生产构建通过。
- 定向 HTTP/身份/媒体契约/Meting：5 个文件 / 24 项通过。
- `node scripts/meting-runtime/check-recording-evidence.mjs`：实际安装 Meting formatter → 实际聚合 HTTP，通过；需先安装已锁定的 sidecar 依赖。
- 鸿蒙主机：`check-aggregate-search.mjs`、`check-media-identity.mjs`、`check-online-queue.mjs`、`check-playback-recovery.mjs` 通过；分别验证合并/展开/点播、三角色身份、网易入库边界、本地播放与迟到响应。
- API 23 `assembleHap --no-daemon --stacktrace`，完整 ArkTS 类型检查、打包与签名通过，未使用 `--no-type-check`；工程既有弃用/异常提示仍存在。
- 签名 HAP：`entry/build/default/outputs/default/entry-default-signed.hap`，SHA256 `35C7062E0187F0E7F5033BF350A4460F1BD7070B8510D6F8BCDFFBF2DAFAC689`。
- 本次修改 `git diff --check` 通过；HTTP 检查删除临时服务端 SQLite；构建临时日志收尾删除。

## 证据边界

匹配只依据严格元数据，不是声纹或音频指纹。缺证据不补猜测，不提高匹配率；相同元数据但平台未注明的版本差异仍需真实样本后续验证。本轮没有执行网易/QQ/酷狗真实网络搜索或真实音频，也不宣称匹配率、曲库覆盖、完整版或自动换源完成。

`hdc list targets` 本轮为空，没有执行 HarmonyOS 原生布局、触摸/键盘、AVPlayer 解码进度、后台/锁屏或设备 SQLite。主机 PLAYING 是受控 Kit 边界，HAP 构建不能替代真机验收；这些后续属于 G7/G8。

代码位于 DreamMusic 与同级 NightDream 两个仓库。按用户要求在关闭 #23 后提交并推送本票文件；原有 `build-profile.json5` 修改及 `.scratch/` 保留，不纳入提交。
