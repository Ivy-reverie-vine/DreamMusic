# DreamMusic 功能类设计方案

## 1. 范围

本方案包含两部分：

1. 定时暂停功能；
2. HarmonyOS 特色能力的调研与后续选型。

本方案不改变现有音乐来源边界：客户端继续通过 NightDream 统一入口获取在线音乐，具体来源由 NightDream 调度。

定时暂停的客户端实现已落地；自动化构建与纯逻辑测试已通过，后台、锁屏、Ability 重启和资源释放仍需真机验收。

## 2. 定时暂停

### 2.1 用户入口

定时暂停只放在：

```text
我的 → 设置 → 定时暂停
```

定时暂停不在以下位置显示：

- 正在播放页；
- 底部常驻播放条；
- 锁屏或控制中心自定义 UI；
- 队列页；
- 其他页面。

设置页只显示当前定时暂停状态。未设置时显示“关闭”；已设置时显示剩余时间，例如“定时暂停 · 01:00:00”。

### 2.2 固定选项

第一版只提供三档，不提供自定义时长和指定时刻：

| 选项 | 行为 |
|---|---|
| 0.5h | 30 分钟后暂停 |
| 1h | 60 分钟后暂停 |
| 2h | 120 分钟后暂停 |

设置弹层或选择器应同时提供“关闭定时暂停”。重复选择某一档时，从当前时间重新开始计时。

### 2.3 播放行为

定时暂停到期后：

- 当前正在播放时，执行一次明确的暂停操作；
- 不自动切歌；
- 不修改队列；
- 不删除或清理音乐库文件；
- 停止 `audioPlayback` 长时任务；
- 清除定时暂停状态；
- 后续用户可以正常手动继续播放。

定时暂停使用墙上时钟计算截止时间，而不是依赖一个持续运行的前台计时器：

```text
deadlineMs = startMs + durationMs
remainingMs = max(0, deadlineMs - Date.now())
```

这样应用进入后台或页面离开后，恢复到前台仍能正确判断是否到期。

推荐语义：用户手动暂停时，定时暂停仍然继续倒计时。它表示“到这个时间停止播放”，而不是“累计播放这么长时间”。

### 2.4 模块设计

新增播放域模块：

```text
entry/src/main/ets/service/playback/SleepTimer.ets
```

模块对外保持小接口：

```ts
interface SleepTimerSnapshot {
  active: boolean;
  deadlineMs: number;
}

class SleepTimer {
  startAfter(durationMs: number, nowMs?: number): void;
  cancel(): void;
  remainingMs(nowMs?: number): number;
  restore(snapshot: SleepTimerSnapshot, nowMs?: number): void;
  consumeIfDue(nowMs?: number): boolean;
}
```

模块只负责截止时间、剩余时间、取消和恢复，不直接操作 ArkUI 或 AVPlayer。

到期通知由播放编排层接收：

```text
SleepTimer 到期
  → QueueViewModel / PlayerViewModel
  → PlayerViewModel.pause()
  → BackgroundPlayback 停止长时任务
```

播放器需要提供明确的 `pause()` 操作，不使用 `togglePause()` 作为定时暂停动作，避免到期时因当前状态变化而错误恢复播放。

### 2.5 持久化（已实现）

定时暂停状态复用现有 `player_state`，增加：

```text
sleep_timer_active
sleep_timer_deadline_ms
```

不新建独立数据库表。

实现已覆盖以下保存时机：

- 设置 0.5h、1h 或 2h；
- 关闭定时暂停；
- Ability 进入后台；
- Ability 销毁；
- 定时暂停到期。

启动恢复规则：

- `deadlineMs > Date.now()`：恢复倒计时；
- `deadlineMs <= Date.now()`：清除过期状态，不执行额外播放操作；
- 恢复后剩余时间只在“我的 → 设置”显示。

已有数据库通过幂等迁移补齐字段；恢复流程等待数据库初始化和队列重建，持久化写入按队列串行化，避免到期清理覆盖队列状态。

### 2.6 UI 状态

设置页需要覆盖：

- 未设置；
- 已设置 0.5h；
- 已设置 1h；
- 已设置 2h；
- 剩余时间变化；
- 到期后自动回到“关闭”；
- 应用重启后恢复。

定时暂停的剩余时间不向其他页面暴露 UI。播放服务可以拥有状态，但页面展示范围固定为设置页。

### 2.7 测试与验收

新增纯逻辑测试：

```text
entry/src/test/SleepTimer.test.ets
```

覆盖：

- 三个固定时长分别转换为 1800000、3600000、7200000 毫秒；
- 重复选择会重新计算截止时间；
- 取消后状态为空闲；
- 剩余时间不会小于 0；
- 过期快照恢复后自动失效；
- 未过期快照可以恢复；
- 到期事件只处理一次；
- 手动暂停不改变定时暂停截止时间。

上述纯逻辑测试已加入 `SleepTimer.test.ets` 并通过 `hvigor test`。`assembleHap` 也已通过。以下仍需设备侧验收：本地音频与普通在线流、后台/锁屏到期、系统播控状态、Ability 销毁/重启恢复，以及 `audioPlayback` 长时任务释放。

### 2.8 当前实现映射

```text
SettingsPage
  → PlayerViewModel.setSleepTimer/cancelSleepTimer
  → SleepTimer（绝对 deadlineMs）
  → QueueViewModel 持久化 player_state
  → PlayerViewModel.pause()
  → BackgroundPlayback 同步暂停并停止长时任务
```

## 3. HarmonyOS 特色能力调研

### 3.1 设计原则

HarmonyOS 特色能力必须满足：

- 与音乐播放或本地音乐库直接相关；
- 通过 API 23 官方 Kit 文档核实后再实现；
- 不破坏离线播放；
- 不绕过当前 MVVM 和播放模块；
- 不把平台能力直接写进页面，优先放入独立模块或适配器；
- 每项能力先完成可行性验证和真机验收方案，再进入实现。

### 3.2 优先调研方向

#### P0：AVSession 播控增强

当前项目已经使用 AVSession 和 `audioPlayback` 长时任务。优先继续完善：

- 锁屏/控制中心的播放状态同步；
- 定时暂停后的系统播放状态；
- 当前曲目、封面、时长和进度同步；
- 耳机和蓝牙播控行为一致性。

该方向复用现有：

```text
entry/src/main/ets/service/playback/BackgroundPlayback.ets
```

#### P1：桌面卡片或服务卡片

在官方能力确认后评估只读展示和轻量控制：

- 当前歌曲封面、歌名、艺术家；
- 播放/暂停；
- 下一首；
- 打开 DreamMusic。

约束：卡片不直接请求 NightDream、不执行下载、不复制播放器逻辑，所有操作回到现有播放模块。

#### P1：系统快捷入口

评估提供以下快捷入口：

- 打开 DreamMusic；
- 继续播放；
- 打开正在播放页；
- 打开队列页；
- 打开“我的”页面。

快捷入口只负责启动或导航，不新增第二套播放状态。

### 3.3 调研输出

每项 HarmonyOS 能力在实施前需要记录：

- 对应官方 Kit 和 API 23 支持情况；
- 权限和配置要求；
- Ability/后台生命周期影响；
- 离线时的降级行为；
- 与现有播放器模块的接入 seam；
- Hypium 可测试部分；
- 真机验收步骤；
- 不采用该能力时的原因。

在完成调研和用户确认前，不新增具体平台 API，不修改模块配置，也不改变现有页面结构。

## 4. 推荐实施顺序

```text
SleepTimer 纯逻辑模块
  → player_state 持久化
  → PlayerViewModel 显式 pause()
  → 我的/设置页入口与状态展示
  → Hypium 测试
  → AVSession 定时暂停联动
  → HarmonyOS 特色能力官方调研
  → 选择一个能力制作真机原型
```

本方案当前只完成设计，不代表功能已经实现。
