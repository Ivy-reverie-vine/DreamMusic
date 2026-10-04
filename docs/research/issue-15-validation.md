# Issue #15：系统播控与音乐胶囊接入验证

- 日期：2026-10-04（Asia/Shanghai）。
- Issue：[完善系统播控与音乐胶囊体验](https://github.com/Ivy-reverie-vine/DreamMusic/issues/15)。
- 用户明确要求：“完成并关闭issue15,不需要你实机验收”。因此本轮以客户端实现、主机检查和 API 23 编译完成验收；设备系统 UI、音乐胶囊外观与实际点击行为跳过。
- 依赖 #12 已核实 CLOSED。保留原工作区未提交改动，本轮未提交、未推送，未修改 NightDream 或在线来源边界。

## 实现

1. `BackgroundPlayback` 继续复用已有 AVSession、CoverArtService、PlayerViewModel 和 QueueViewModel。元数据保留本地/在线音轨身份、曲名、艺术家、专辑、时长和封面；沿用封面请求版本、串行提交和 lease 归还机制。播放状态增加 ERROR 映射；状态写入串行并校验版本，状态/音轨/模式变化立即同步，普通进度保持一秒节流。
2. AVSession 的 `setLaunchAbility` 和 `audioPlayback` 通知共用 WantAgent。导航契约为 `EntryAbility` 的 Want 参数 `dreammusic.destination = now-playing`，可供后续桌面卡片复用。EntryAbility 显式使用 singleton，`onCreate` 与 `onNewWant` 共用目的地解析；`PlaybackLaunch` 在主壳未挂载时暂存请求，挂载后一次消费，已有主壳则直接派发。主壳切换到既有“正在播放”根入口并清理启动登录/绑定覆盖层，防止迟到的登录检查遮挡；普通启动的登录流程保持原语义。点击只导航，已有队列恢复仍以暂停态恢复，不自动播放。
3. 系统播放、暂停、停止、上一首、下一首、拖动进度统一排队进入现有播放器；异常被隔离，后续命令可继续。系统暂停使用显式 `pause()`，重复播放不会反向切换为暂停。拖动进度拒绝非有限数、限制在有效范围，立即更新系统位置和歌词位置；暂停/恢复态落盘位置，下次播放使用该位置。
4. 后台长时任务维护最新播放意图并串行执行 start/stop，异步调用完成后重新核对：启动未完成时暂停会随后停止，停止未完成时恢复会随后启动，同一运行状态不重复调用。会话初始化合并并发请求，失败销毁半初始化会话，前台恢复可以重试；播放早于初始化完成时保留后台任务意图。
5. 自然结束明确同步 COMPLETED，定时暂停沿用原来的显式暂停链。前台恢复重新核对定时暂停，并同步当前媒体状态和后台任务；后台切换保留现有进度落盘。恢复队列时补齐播放模式镜像。释放时等待初始化及已经提交的媒体信息/状态，停止长时任务、销毁会话并归还封面；销毁后的旧系统回调不执行。

## 主机检查

以下检查通过，执行实际 ArkTS 逻辑，Kit、音频、网络、存储边界使用替身：

- `node scripts/check-system-playback.mjs`：冷启动暂存/一次消费、前台/后台已有壳导航、未知目的地忽略、登录检查迟到、WantAgent 目的地、并发初始化、失败重试、初始化中销毁、start/stop 交错、播放状态写入串行、状态变化不受进度节流、系统命令贯通真实 QueueViewModel/PlayerViewModel、重复命令、seek 边界、恢复断点、自然结束、定时暂停、前后台生命周期调用与命令失败隔离。
- `node scripts/check-covers.mjs`：本地/在线/缺失封面、离线回退、快速切歌迟到结果、元数据顺序、进度不重复解码、在线转本地连续性和资源归还；替身同步补上 setLaunchAbility/WantAgentFlags。
- `node scripts/check-navigation.mjs`：四入口、原有来源返回策略和子页面返回回归。
- `node scripts/check-playback-recovery.mjs`：播放状态、恢复、失败重试、过期请求隔离回归。
- `node scripts/check-playback-interactions.mjs`：队列顺序/持久化/交互门禁回归。
- `node scripts/check-entry-page.mjs`：入口仍为 `pages/IndexV2`。
- `git diff --check`：通过。源码未引入 setBackgroundPlayMode 或 Live View API。

未执行全量 Hypium；主机替身不作为真实 AVPlayer、SQLite、网络或系统调度的设备证据。

## HAP 构建

进程级设置 `DEVECO_SDK_HOME=D:\DreamMusic\.devEco-sdk-compat`，运行：

```powershell
& 'D:\DevEco\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```

最终结果 `BUILD SUCCESSFUL in 16 s 962 ms`，保留 ArkTS 类型检查。CompileArkTS、PackageHap、PackingCheck、SignHap 全部完成；构建仍有弃用及可能抛异常警告。

- signed HAP：`entry/build/default/outputs/default/entry-default-signed.hap`。
- SHA256：`A9B8A381FB5A2A1A697D4E7658B302B301390061326B92ED2CACA9E3E9C901BC`。
- unsigned HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

## API 依据与设备边界

- [华为 AVSession 开发指导](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/using-avsession-developer-V13)：媒体信息、播放状态和 setLaunchAbility 启动入口。
- [华为 WantAgent API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/js-apis-app-ability-wantagent-V13)：START_ABILITY、Want 参数及 UPDATE_PRESENT_FLAG。
- 同时核对本机 API 23 SDK 的 `@ohos.multimedia.avsession.d.ts`（setLaunchAbility、ERROR 状态）、`@ohos.app.ability.wantAgent.d.ts`（UPDATE_PRESENT_FLAG）及 module schema（singleton），以实际 ArkTS 编译验证可用性。Issue 原官方链接读取超时，使用上述可检索官方资料与本机声明交叉核实。

锁屏、控制中心、音乐胶囊显示/点击、真实前后台调度与断点启动：按用户授权跳过实机验收，未记录设备截图或外观结论。实现使用平台 AVSession 接入，不承诺特定设备的胶囊展示形式或任意自绘灵动岛。
