# Issue #22 验证记录

日期：2026-10-05（Asia/Shanghai）。范围：T03 三平台聚合搜索、逐来源分页、部分失败展示；前置 #20 已关闭。本记录不表示 #19 总规格、同录音合并或自动换源已完成。

## 实现与验收对照

| #22 验收条件 | 本轮实现与证据 |
| --- | --- |
| 通过 NightDream 并发查询网易 / QQ / 酷狗并显示来源 | v2 `search?aggregate=true` 在现有 `MusicOrchestrator` 并发分派三个真实 adapter，沿用注册表、开关、并发及熔断；HTTP 测试用三来源同时开始的门闩验证并发。鸿蒙 `NetEaseApi` 仅访问网关，搜索行辅助文字先显示来源 |
| 单来源超时、拒绝、字段无效不影响其他结果；区分部分失败、正常空、全部失败 | HTTP 信封返回来源状态和聚合 `success/partial_failure/empty/all_failed`，无效条目不会被当作空结果或污染 Meting 缓存；25ms 受控超时、403/429/503、非法字段、零结果均有真实 HTTP 证据。客户端公开状态与提示分别消费，部分失败/加载与已有列表并存 |
| 逐来源分页；重试和重复页不重复追加；不虚构总数 | 网易 offset 与 Meting page 分别推进；失败停在本次页。后续请求只含需要查询的来源；客户端按具体 `mediaRef` 去重，保留跨平台独立条目。完整网关断线重试仍使用原请求页。响应无跨平台 total；Meting 的填满页仅意味着可能有下一页，不代表完整曲库 |
| 搜索不逐曲解析音频；可点播兼容路径 | HTTP 断言首次只发起三个搜索请求；点击真实 ArkTS `OnlineSearchView.streamAndPlay` 后才解析所选 QQ 引用，真实在线/队列/播放器状态进入 PLAYING，非网易音频不发起网易下载。旧 HTTP 身份、网易下载和本地播放回归保留 |
| 改词/取消拒绝旧响应；后到搜索不改所选歌曲 | 改词立即清列表并使旧 generation 失效，不等防抖结束。门闩控制旧响应迟到与页面退出；新列表、loading、队列 ID、目录引用和原曲名保持正确。快速输入后清空不再发请求；组件退出清理定时器 |
| 真实 HTTP 与客户端交互覆盖规定场景，第三方受控、业务聚合真实 | `NightDream/server/proxy.search.test.js` 使用实际 Express、认证、临时服务端 SQLite、注册表、编排和 adapters。`scripts/check-aggregate-search.mjs` 将实际 ArkTS `ApiClient/NetEaseApi/OnlineSearchViewModel`、组件普通交互方法及在线/队列/播放器逻辑接到同一 HTTP 入口，仅替换 Kit、客户端存储/下载与第三方 HTTP 边界 |

旧网关没有聚合契约时，鸿蒙保留旧单来源搜索及翻页，并仅报告真实查询的一个来源；该兼容分支也经客户端主机检查。未改生产来源开关、上游项目、匹配/换源或本地数据库结构。

## 已通过

- NightDream `npm test`：41 个文件 / 201 项；`npm run build`：TypeScript 与 Vite 生产构建通过。
- 最终边界修正后，定向重跑真实聚合/身份 HTTP、媒体契约与 Meting adapter：4 个文件 / 20 项通过。
- 鸿蒙主机：`node scripts/check-aggregate-search.mjs`、`check-media-identity.mjs`、`check-online-queue.mjs`、`check-playback-recovery.mjs` 均通过。
- API 23 完整 `assembleHap --no-daemon --stacktrace`，未使用 `--no-type-check`：ArkTS 类型检查、打包及签名通过，工程既有弃用/可能抛异常提示仍存在。
- 最终签名 HAP `entry/build/default/outputs/default/entry-default-signed.hap` SHA256：`D45B338B45D69A3FE9E5A4FA9101BFEA52B02915714A75538236A82D04B4EDE4`。
- 本次修改文件 `git diff --check` 通过。网关测试关闭服务并删除临时服务端数据库；构建临时日志完成记录后删除。

## 证据边界

本轮完成 #22 要求的受控真实业务链与客户端交互验证。没有执行真实网易 / QQ / 酷狗网络样本、HarmonyOS 原生搜索布局/键盘/触摸、AVPlayer 解码进度、后台/锁屏或设备 SQLite 验收；主机 PLAYING 由 Kit 边界产生，不作为真机音频成功证据。后续真实来源与设备验收属于 G7/G8。

仓库原有 `build-profile.json5` 改动与 `.scratch/` 保留，不纳入本次提交。服务端代码位于同级 NightDream 仓库，本次随鸿蒙改动一起提交并推送。
