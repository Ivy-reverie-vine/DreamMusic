# Issue #18：系统桌面歌词

- 日期：2026-10-04（Asia/Shanghai）。
- Issue：[接入系统桌面歌词](https://github.com/Ivy-reverie-vine/DreamMusic/issues/18)。
- 用户已明确选择“跳过真机验收，验证通过后关闭”。本次以实现、主机检查和 API 23 编译为完成依据；没有桌面渲染或真机交互通过结论。
- 保留工作区原有修改，本次未提交、未推送；不修改 NightDream 或音乐来源边界。

## 实现与验收对应

1. `DesktopLyrics` 使用 `@kit.AVSessionKit` 的 API 23：`isDesktopLyricSupported`、`enableDesktopLyric`、`setDesktopLyricVisible`、`setDesktopLyricState({ isLocked })`。读取可见/锁定状态，使用会话控制器监听开启状态，会话自身监听可见/锁定变化。
2. “我的 → 设置 → 播放”提供默认关闭的系统桌面歌词开关，以及开启后的显示和位置锁定控制。Preferences 独立保存开启、显示、锁定意愿；系统修改回写，自动隐藏不覆盖用户对下一首的显示意愿。暂时异常提供原位重试，存储失败明确说明未保存。
3. 播放运行时初始化既有 `LyricsViewModel`，页面尚未挂载时也可工作；只消费其本地 LRC/在线 LRC/YRC 解析结果，不重复请求另一份歌词。时间轴以毫秒精度转换为标准 LRC，填入 `AVMetadata.lyric`；复用已有 AVSession 播放状态与位置更新，支持拖动、暂停、恢复。
4. 元数据在封面下载之前提交，歌词和封面共用有版本保护的写队列。切歌立即清旧歌词；旧在线请求不能覆盖新音轨，空歌词/加载失败不会保留上一首。元数据成功提交后才允许显示，播放错误/空播放器隐藏窗口。
5. 桌面能力异步附着到现有后台播放会话，不阻塞音频或长时任务。系统写入串行、重新创建会话恢复意愿；注销三个监听并销毁控制器，再关闭桌面歌词、销毁播放会话。迟到的探测、歌词、封面或回调不能恢复已释放会话。
6. 不支持设备只显示不可用说明，不注册监听或反复调用；原生暂时错误抑制自动重试，用户主动重试才恢复。没有 Android 悬浮窗、额外歌词计时器或悬浮倒计时；定时暂停仍仅在设置页。

## 已通过的主机检查

- `node scripts/check-desktop-lyrics.mjs`：执行真实桌面歌词服务、设置 ViewModel、歌词 ViewModel、播放 Runtime、BackgroundPlayback。覆盖默认关闭、保存/重启恢复、系统反馈、自动隐藏与用户隐藏区分、快速变更、延迟原生写入、暂时失败重试、探测失败恢复、不支持设备、存储失败、重复附着、监听/控制器释放、过期探测、LRC/YRC、冷运行时、封面迟到、拖动/暂停/恢复、切歌晚回包、无歌词与失败清理。
- `node scripts/check-lyrics.mjs`：现有歌词跟随、手动浏览、定位、加载/空/失败状态与过期请求回归。
- `node scripts/check-system-playback.mjs`：现有系统播控、冷/热启动、队列/定时暂停、卡片 Runtime 回归。
- `node scripts/check-covers.mjs`：封面资源归还、元数据写入顺序、进度不等待封面、旧结果淘汰回归。
- `git diff --check`：通过。

AVSession、Preferences、文件、网络等为主机替身；这些检查不代表真实存储落盘、原生桌面窗口或设备后台表现。

## API 23 构建

```powershell
$env:DEVECO_SDK_HOME='D:\DreamMusic\.devEco-sdk-compat'
& 'D:\DevEco\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```

- 最终 `BUILD SUCCESSFUL in 19 s 459 ms`，含 CompileArkTS、PackageHap、PackingCheck、SignHap；未使用 `--no-type-check`。
- 首次构建遇到 `.hvigor/outputs/build-logs/build.log` 的 EBUSY 日志轮转错误；确认无残留 Hvigor 进程后重跑成功。未修改 SDK 或构建配置。
- 存在既有弃用/可能抛异常警告，新原生调用也有可能抛异常提示，调用边界已捕获。
- 签名产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
- SHA256：`1CD3D0197380A92F12A1E201B53D5B234EFE262F1C4370167A2E9723D63535AD`。

## 官方依据和真机边界

- [华为 AVSession API 参考](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-avsession-avsession#enabledesktoplyric23)：本轮网页抓取超时，不把未读到的页面正文当作已核验材料。
- [华为 AVSession 错误码](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/errorcode-avsession)：已读取，确认 6600110 表示未开启、6600111 表示设备不支持，并要求通过 `isDesktopLyricSupported` 查询。
- 本地 `D:\DevEco\sdk\default\openharmony\ets\api\@ohos.multimedia.avsession.d.ts` 核对 API 23 的实际签名、监听配对、控制器销毁以及 `AVMetadata.lyric` 标准歌词格式；以上 Kit 导入与调用经真实 API 23 编译校验。
- 初始 `hdc list targets` 为 `[Empty]`。桌面显示、移动/锁定、切歌、前后台、系统关闭回写、系统重启恢复和不同设备不支持时的表现，按用户授权跳过。本次没有截图或设备安装记录。
