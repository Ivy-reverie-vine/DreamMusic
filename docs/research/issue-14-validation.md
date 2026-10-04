# Issue #14：四入口界面与返回收尾记录

- 日期：2026-10-04（Asia/Shanghai）。
- Issue：[完成四入口改版的真机视觉与返回验收](https://github.com/Ivy-reverie-vine/DreamMusic/issues/14)。
- 用户明确授权：“完成并关闭issue14,不需要你实机验收”。因此本轮以源码检查、主机逻辑检查及 HAP 构建完成收尾；原 issue 中的设备、字体、截图、键盘和边缘手势验收均跳过，不记为 PASS。
- 当前 GitHub 依赖 #9、#10、#11、#12、#13 已独立查询，均为 CLOSED。
- 保留 HarmonyOS 6.1 / API 23、四入口、随图取色、离线优先及 NightDream 统一入口，未修改后端和音乐来源。

## 修复内容

1. 主壳新增 `BackDispatcher`，音乐库、我的、歌单和设置按生命周期注册/注销返回处理。系统返回先关闭主壳登录/绑定，再由当前子组件关闭歌曲操作、认证弹层、重命名、消息编辑或详情，最后按既有策略返回我的首页、来源入口或交给系统。修复歌单组件自己声明 `onBackPress` 却未接入主壳的问题。
2. “我的”界面返回交给主壳，修复音乐库/正在播放进入设置后，界面返回和系统返回目标不一致的问题。子页面内重复进入设置保留最初来源入口。在线“全部歌单 → 歌单详情”返回全部列表；歌单列表补齐返回我的入口。
3. 歌单卸载与重新进入清理共享的详情选择；详情查询返回后核对选择身份，避免退出后迟到结果写回。切换一级入口沿用 `selectRoot`，复位子页面与来源。切换“我的”子页面收起消息编辑，进入统计页刷新；进入我的加载最近播放。
4. 账户统计摘要与详情区分未登录、加载、真实零、成功、失败无数据和上次成功数据。失败无数据不显示默认 0 或 1970 年同步时间；上次成功数据明确提示无法更新。账户与本机来源标识保留。
5. 公告、梦点流水分别增加加载、失败与重试状态，成功空数据才显示暂无内容。音乐库读取异常有提示及重试，使用 finally 结束加载，完整读取后才替换列表。
6. 设置及歌单内容使用标题以下的剩余高度；统计标题为刷新按钮留出空间，摘要纵向排列，设置说明按剩余宽度换行，历史艺术家长文本截断。消息输入采用既有 40/200 字上限。底部入口最小高度 48vp，光晕退出触摸命中，主壳卸载清理光晕定时器。沿用现有设计 token，已补充 DESIGN.md。

## 场景与证据边界

| 场景 | 本轮检查与结果 | 原生设备结果 |
| --- | --- | --- |
| 音乐库歌曲/专辑/艺术家、搜索、歌曲操作、空/加载/错误 | 源码检查；音乐库失败→重试、操作层→详情→搜索→系统返回的真实方法检查通过 | 跳过 |
| 正在播放、歌词、队列、迷你播放器 | 原有专项回归通过；主壳在正在播放入口不渲染迷你播放器，内容与常驻播控使用 Column 分配高度 | 跳过 |
| 我的、歌单/在线详情、历史、统计、账户、公告消息、设置 | 源码逐页检查；详情返回、重命名优先关闭、消息收起、退出重入、统计和读取状态检查通过 | 跳过 |
| 登录/启动绑定/设置绑定、音乐库及播放页进入设置 | 真实主壳及子组件方法检查通过；四个来源入口与六个我的子页面的返回组合均覆盖 | 跳过 |
| 状态栏、底部手势区、键盘、安全区、大字体与长文本观感 | 源码检查未主动扩展系统/键盘安全区；保留 ArkUI 默认键盘避让，修复明确的剩余高度、标题宽度与长文本问题 | 跳过，不宣称无遮挡或视觉通过 |
| 离线与数据来源 | 账户请求失败下本机统计仍可用，失败无快照/真实零/保留旧成功值检查通过；未改本地播放或来源边界 | 真实网络/SQLite/音频跳过 |

## 主机检查

- `node scripts/check-navigation.mjs`：通过。执行真实 Navigation、主壳/子组件普通方法与相关 ViewModel；覆盖来源返回、层级优先、入口复位、卸载注销、歌单重入/迟到查询、消息收起、统计不可用/真实零/旧值、公告流水失败与重试、音乐库失败恢复。Kit、网络、数据库边界采用替身，不模拟 ArkUI 生命周期调用顺序、点击或手势派发。
- 既有入口、播控/队列、播放恢复、封面、歌词、主题对比度检查全部通过：`check-entry-page.mjs`、`check-playback-interactions.mjs`、`check-playback-recovery.mjs`、`check-covers.mjs`、`check-lyrics.mjs`、`check-theme-contrast.mjs`。
- `git diff --check`：通过。未执行全量 Hypium 或设备测试。

## HAP 构建

进程级设置 `DEVECO_SDK_HOME=D:\DreamMusic\.devEco-sdk-compat`，执行：

```powershell
& 'D:\DevEco\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```

最终结果：`BUILD SUCCESSFUL in 15 s 492 ms`，保留 ArkTS 类型检查；CompileArkTS、PackageHap、PackingCheck、SignHap 全部完成。既有弃用与可能抛异常警告仍存在。

- signed HAP：`entry/build/default/outputs/default/entry-default-signed.hap`。
- SHA256：`1FD2CD954B21F03EEE28F7234741269D990907D9C76D716593B8EE3E263053D3`。
- unsigned HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`。
- 本轮未安装到设备，不记录设备型号、系统实测版本、字体或截图；未提交、未推送。保留原有工作区改动。

## API 依据

返回生命周期参考[华为自定义组件生命周期文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-page-custom-components-lifecycle)，网页正文读取受限。触摸命中参考[华为 hitTestBehavior 常见问题](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1131)。同时核对本机 API 23 SDK 的 `component/common.d.ts` 中 `hitTestBehavior(HitTestMode)`，以及 `@ohos.arkui.UIContext.d.ts` 中默认 `KeyboardAvoidMode.OFFSET` 声明，结合实际 ArkTS 编译核实可用性。

按用户指定范围完成并关闭 #14；关闭不代表未执行的真机视觉与返回场景已通过。
