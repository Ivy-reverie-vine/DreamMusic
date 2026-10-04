# Issue #17：本地歌单快捷卡片

- 日期：2026-10-04（Asia/Shanghai）。
- Issue：[增加本地歌单快捷卡片](https://github.com/Ivy-reverie-vine/DreamMusic/issues/17)。
- 用户明确要求：“完成并关闭issue17,不需要你实机验收”。本轮以实现、主机逻辑检查和 API 23 编译为完成依据；实机验收跳过。
- 依赖 #15 已独立读回为 CLOSED。保留工作区已有修改；本轮未提交、未推送，不改 NightDream 或在线来源边界。

## 使用路径与实现

1. “我的 → 歌单 → 我喜欢的音乐/任一本地歌单 → 添加到桌面”：预览已选歌单，使用 ArkUI `AddFormMenuItem` 选择 2×2 或 2×4 并添加。Want 携带当前本地歌单 ID；从桌面直接添加的默认卡片解析本地固定收藏歌单。
2. 独立的 `PlaylistFormAbility`、配置和 ArkTS 静态卡片与音乐播控卡片共存。展示名称、曲目数量、最多三首歌曲的摘要和明确打开入口。空歌单正常打开；删除歌单显示失效说明；读取失败显示重试提示。初次异步读库前也携带正确目标 ID，避免点到默认收藏。
3. 每个 formId 单独保存绑定文件，原子替换；重复添加回调不重绑，默认收藏首次解析后也固定为数据库 ID。名称变化不影响绑定，同名新歌单不替代已删除目标。临时转正式、可见刷新、系统更新、移除和进程重启均复用同一绑定。移除期间尚未完成的读取不重新创建实例记录。
4. 展示直接读取本地 `LibraryStore` 的歌单、收藏与音轨，过滤已删除音轨的残留成员 ID。不依赖登录、网易云绑定、HTTP 或播放队列，也不缓存另一份歌单事实。LibraryStore 成功完成重命名、成员增删、收藏切换、歌曲删除和元数据编辑后通知刷新；发布方只查询并更新本歌单卡片，单实例失败不阻断其他实例，按实例串行更新。
5. 扩展 #15 `PlaybackLaunch` 的目的地契约，`EntryAbility.onCreate/onNewWant` 共用解析。主壳消费请求，进入既有“我的 → 歌单详情”，绕过启动登录覆盖层；不新增根入口，不改变队列或自动播放。页面等本地库初始化后按稳定 ID 打开，连续点击只完成最新请求；返回、卸载和手动改选取消迟到读取。已删除目标留在歌单列表并显示明确提示。返回顺序仍为详情 → 歌单列表 → 我的首页；回到首页正常恢复该区域的数据加载。

## 主机检查

执行真实 ArkTS 类和组件普通方法，Form Kit、SQLite、文件系统和平台 Ability 使用替身；以下均通过：

- `node scripts/check-playlist-forms.mjs`：自定义/默认收藏绑定、首次点击目标、重发回调、名称/成员/收藏/歌曲删除同步、空歌单、目标删除与同名替代、实例隔离、重启读取、临时转正式、可见刷新、异步移除、读取/更新失败、更新顺序；冷/热启动、无登录导航、连续请求、初始化期间手动改选、返回/卸载取消、失效 ID、我的首页恢复加载、LibraryStore 写入通知及刷新失败隔离。
- `node scripts/check-navigation.mjs`：四入口、子页面返回、覆盖层、重入和原有业务状态回归。
- `node scripts/check-system-playback.mjs`：#15 系统进入应用与 #16 播控运行时回归。
- `node scripts/check-music-forms.mjs`：已有桌面播控卡片实例与资源生命周期回归。
- `node scripts/check-entry-page.mjs`：唯一启动页保持 `pages/IndexV2`。
- `git diff --check`：通过。

未运行全量 Hypium；上述结果不代表真实 SQLite、桌面渲染、系统添加流程或设备点击验收。

## API 23 构建

```powershell
$env:DEVECO_SDK_HOME='D:\DreamMusic\.devEco-sdk-compat'
& 'D:\DevEco\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```

- 最终：`BUILD SUCCESSFUL in 25 s 596 ms`。CompileArkTS、PackageHap、PackingCheck、SignHap 完成；没有使用 `--no-type-check`。
- 保留已有弃用及可能抛异常警告；新文件的原生文件调用也有可能抛异常提示。
- 签名产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
- SHA256：`85F4AAB170320FB38F4CA05F23BB3C4B94CDD91581CF20C6D0760A4F28D68E66`。

## 官方依据与验收边界

- [OpenHarmony FormMenu / AddFormMenuItem](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ohos-arkui-advanced-formmenu.md)：应用内组件预览及加桌入口，自 API 12 支持。
- [卡片配置](https://github.com/openharmony/docs/blob/master/en/application-dev/form/arkts-ui-widget-configuration.md)：规格、静态卡片、可见通知及字体设置。
- 本机 HarmonyOS API 23 SDK `@ohos.arkui.advanced.FormMenu.d.ets`、`@ohos.app.form.formProvider.d.ts` 核实实际签名；`@kit.ArkUI` / `@kit.FormKit` 及配置由真实编译校验。

两种规格的桌面视觉、字体放大、系统加桌流程、冷/热启动原生点击、删除目标和离线实机使用，依用户授权全部跳过；没有设备截图或交互通过结论。
