# Issue #16：桌面音乐播控卡片

- 日期：2026-10-04（Asia/Shanghai）。
- Issue：https://github.com/Ivy-reverie-vine/DreamMusic/issues/16。
- 用户要求：“完成并关闭issue16,不需要你实机验收”。按客户端实现、主机检查和保留类型检查的 API 23 HAP 构建验收；不把主机替身或编译结果作为桌面实测证据。
- 依赖 #12、#15 已独立核实 CLOSED。原工作区已有大量未提交修改，本轮保留这些修改，不提交、不推送，不改 NightDream 或在线来源边界。

## 实现与边界

1. `MusicFormAbility` / `music_form_config.json` 注册一个静态 ArkTS 卡片，支持 2×2、2×4；`MusicCard.ets` 分别采用紧凑纵排和左封面布局。展示曲名、艺术家、统一封面、状态，以及独立播放/暂停、上一首和下一首按钮。空队列、加载、缺文件、需登录等状态禁用对应动作，保留点击歌曲/状态查看应用的入口。使用既有深色文字角色、封面取色和统一占位，字体随系统缩放。
2. 卡片按钮通过 `FormLink(action: call)` 调用 singleton `EntryAbility.callee`，后台进入现有 `PlayerViewModel` / `QueueViewModel`；没有创建第二个 AVPlayer、队列或播放 Extension。歌曲区域通过 `router` 沿用 #15 的 `dreammusic.destination=now-playing`，只导航，不自动播放。
3. `PlaybackRuntime` 合并应用启动、卡片冷启动和页面挂载的恢复请求。队列与断点只从原 `player_state` 恢复一次；先恢复再执行命令，之后页面挂载不会重置后台播放。串行处理卡片命令，显式播放与暂停具有幂等性；已有网络错误、文件缺失、定时暂停和重试语义继续由播放器处理。无当前曲时不执行切歌。
4. `PlayerViewModel` 的状态变化以及队列封面补齐/在线转本地变化发布到 `MusicFormPublisher`。元数据更新串行并校验版本，普通进度不刷新卡片或重新解码封面。封面由 `CoverArtService` 统一获取，96px JPEG 通过 `formImages` 文件描述符传递；每版图片使用独立 `memory://` key，更新完成后关闭 fd，旧请求归还 lease，不覆盖新歌曲。
5. 跨进程文件只存曲名、艺术家、状态、封面文件名等展示投影，不含队列、音频 URL 或凭据。应用原有进度回调至多每 15 秒刷新展示缓存存活时间，没有新增卡片计时器；卡片提供方读取超过 45 秒的 playing/preparing 快照时降级为“点按播放，恢复上次音乐”。这是提供方读取时的过期处理，不代表系统强杀后桌面能立即刷新。
6. 添加、刷新、可见性变化、临时转正式和重启读取同一投影；实际实例清单由 API 20 起提供的 `getPublishedRunningFormInfos` 获取，只更新本卡片的实例。删除后不保留实例刷新任务，单实例更新失败不阻断其余卡片。卡片进程不加载播放器、网络或第三方凭据。封面缓存只保留本功能的最近两版。

## 主机验证

执行真实 ArkTS 逻辑，Kit、音频、数据库、文件和图像边界按场景使用替身：

- `node scripts/check-music-forms.mjs`：两种规格配置、过期快照、按序多实例更新、移除与重启、空/错误状态、图片 fd 生命周期、旧封面迟到、同曲换图使用新 memory key、不随进度重复更新、销毁后不再发布。
- `node scripts/check-system-playback.mjs`：保留 #15 全部检查；新增卡片冷启动与断点、初始化合并、重复命令、真实 QueueViewModel/PlayerViewModel 的上一首/下一首、命令失败恢复、文件/网络错误边界、定时暂停、封面补齐推送、空队列与 EntryAbility 的 IPC 解析。
- `node scripts/check-covers.mjs`：统一封面、资源归还及旧请求隔离回归。
- `node scripts/check-playback-recovery.mjs`：现有播放恢复与过期请求回归。
- `node scripts/check-navigation.mjs`：四入口、来源返回与登录覆盖层回归。
- `node scripts/check-playback-interactions.mjs`：队列持久化、排序、重复操作回归。
- `node scripts/check-entry-page.mjs`：入口仍是 `pages/IndexV2`。
- `git diff --check`：通过。

未运行全量 Hypium。没有把上述检查称为真实 AVPlayer、SQLite、网络或桌面渲染验收。

## API 23 构建

```powershell
$env:DEVECO_SDK_HOME='D:\DreamMusic\.devEco-sdk-compat'
& 'D:\DevEco\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```

最终结果：`BUILD SUCCESSFUL in 27 s 654 ms`。CompileArkTS、PackageHap、PackingCheck、SignHap 完成；没有使用 `--no-type-check`。保留已有弃用/可能抛异常警告，新增图像 packing 也有弃用警告。

- 签名产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
- SHA256：`46D2BA203FA6333A4C7B085AFCA7B4C2B3C36057A2232FA880CAC8AD054955D6`。

## 官方依据

- Issue 的华为音乐卡片入口请求超时；交叉核对官方 OpenHarmony Form Kit 指导与本机 HarmonyOS API 23 SDK 声明及 schema。
- [call 后台启动与 callee 命令](https://github.com/openharmony/docs/blob/master/en/application-dev/form/arkts-ui-widget-event-call.md)。
- [静态 FormLink 的 router / call](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-container-formlink.md)。
- [卡片配置与尺寸](https://github.com/openharmony/docs/blob/master/en/application-dev/form/arkts-ui-widget-configuration.md)。
- [图片传递、fd 归还与 memory key 更新](https://github.com/openharmony/docs/blob/master/en/application-dev/form/arkts-ui-widget-image-update.md)。
- 本机 `@ohos.app.form.formProvider.d.ts` 确认实例查询 API 从 20 可用；`FormExtensionAbility`、`formInfo`、`@kit.FormKit`、`@kit.IPCKit` 及卡片 schema 由实际构建验证。

两种规格的桌面外观、系统字体放大实际布局、冷启动/多卡片点击、锁屏和真实后台调度，按用户本次授权跳过实机验收；没有设备截图或交互通过结论。
