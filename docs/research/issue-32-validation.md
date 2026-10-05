# Issue #32 验收记录

日期：2026-10-05（Asia/Shanghai）。范围 T13 / G7；前置 #27、#28、#30 已独立读回 CLOSED。

| 验收条件 | 结果与证据 |
| --- | --- |
| 地址过期/不可达后重新解析、重试有界 | 实际 HTTP 410 经生产 ArkTS PlayerSession 错误入口恢复；当前资源 URL 缓存强制失效；两次尝试共用 15 秒期限，持续失败与总超时进入重试/重新选择终态 |
| 手动资源稳定、自动仍守同录音 | 用户/实际引用绑定恢复凭据，不再依赖已失效的搜索页；只请求所选平台资源或原 BV/CID，自动 Bilibili 在重新解析时复查录音证据；已编辑 Live 资源被拒绝 |
| 目录/队列/实际身份与歌词 | 原队列对象、目录名/歌手/引用不变；真实音频/歌词角色仍可追溯；恢复后强制重取歌词适配，独立其他录音仍禁用原曲同步时间轴 |
| 切歌/取消、单一恢复、下载 | 重复原生 state/error/prepare 异常只发起一个恢复；旧会话回调按 request+session 隔离；切到本地或截止时间后迟到 HTTP 不起播；同次选择播放就绪钩子最多一次，不重复下载 |
| 真实 HTTP 到客户端的失效/成功/持续失败/切歌 | Express/认证/临时 SQLite/真实 adapter → 生产 ArkTS API/队列/PlayerSession → 实际媒体 HTTP 字节。浏览器生产 React PlayerProvider/API 使用原生 WAV 解码验证；没有另起下载路径，代理和直连沿用现有能力 |
| 完整受控失效到实际播放证据 | 旧地址真实 410，新地址原生 `playing`、readyState=4、paused=false，进度 0.039s → 33.103s；另一次播放完成 90s。持续失效为初次加两次恢复后终止；慢解析中取消后无迟到播放 |

## 验证与可复现入口

- HarmonyOS `assembleHap --no-daemon --stacktrace` 通过，包含 ArkTS 类型检查与本机签名，未关闭类型检查；保留原有告警。
- `check-url-recovery --record`、`check-playback-recovery`、`check-automatic-playback`、`check-manual-playback`、`check-other-recording`、`check-media-identity`、`check-catalog-lyrics` 通过。
- NightDream 全量 52 文件 / 322 项通过；默认高并发首次有一个既有短预算时序失败，单项及两 worker 全量复测通过，未改该断言。随后缓存/播放器相关 2 文件 / 10 项通过；TypeScript/Vite build 通过。
- 两仓库 `git diff --check` 通过。原有本机 `build-profile.json5` 和 `.scratch/` 不纳入提交。

实现、协议及复现命令见 NightDream `docs/playback-url-recovery.md`。主要耐久证据：

- [实际 ArkTS / HTTP / 媒体会话](assets/issue32-client-recovery.json)
- [原生浏览器事件、位置与持续失败/取消](assets/issue32-browser-recovery.json)
- [对应业务 HTTP：解析 → 410 → 强制重解析 → 可播放资源](assets/issue32-browser-http.json)
- [恢复到实际 playing 的截图](assets/issue32-native-recovery.jpg)
- [持续失败终态截图](assets/issue32-native-failure.jpg)

## 验收边界

样本为本地生成的 90 秒 PCM WAV；提供方响应与 URL 410 是**受控失效**，实际业务 HTTP、媒体字节与浏览器原生解码为真实执行。不能据此声称网易/QQ/Bilibili 自然过期恢复率或来源可用率。ArkTS 主机测试控制 HarmonyOS Kit 和持久化边界，不能替代真机 AVPlayer、设备 SQLite、后台或锁屏验收。后两项按 issue 原有分层设备验收单独证明；本票不表示 G7 其他工单、G8 或父 #19 完成。
