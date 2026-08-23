# PRD：定时暂停

- 日期：2026-08-23
- 状态：已确认，待实现
- 关联：`CONTEXT.md`、`docs/adr/0008-sleep-timer-semantics.md`、`docs/functional-design.md`、`docs/TODO.md`

## Problem Statement

DreamMusic 主要用于静室、通勤和锁屏场景。用户可能希望在入睡、休息或离开设备前，让正在播放的音乐在一段时间后自动停止，但目前只能手动暂停，无法设定停止时间。

如果定时暂停依赖当前页面持续打开、只记录剩余时长，或通过切歌/恢复播放逻辑间接实现，就容易在后台、重启、手动暂停和自然结束等场景产生意外行为。用户需要一个低干扰、可预测、与账户和网络无关的本机播放器能力。

## Solution

在“我的 → 设置”中增加“定时暂停”。用户可以选择 30 分钟、60 分钟、120 分钟或关闭。设置页显示当前状态和剩余时间，其他页面不显示倒计时。

定时暂停以未来的截止时间为核心语义，而不是累计播放时长：

- 设置后立即开始倒计时；用户手动暂停不会暂停倒计时。
- 用户切歌、播放上一首/下一首、重新点播或歌曲自然结束，不会取消定时暂停。
- 没有当前歌曲时也可以设置；截止前开始播放仍会在截止时间暂停。
- 到期时若正在播放，则明确暂停当前播放器；若已经暂停或没有播放，则不自动恢复、不切歌、不修改队列。
- 到期后清除状态，暂停或后台资源释放失败也不重复触发。
- 应用进入后台、被销毁或重启后，未到期状态继续保留；已过期状态恢复时只清除，不补执行暂停。

剩余时间使用 `HH:MM:SS` 展示，仅在设置页可见时更新。定时暂停属于设备级播放器状态，不随 DreamMusic 登录、网易云绑定或服务器 Profile 改变。

## User Stories

1. As a DreamMusic 用户, I want to set a 30-minute sleep timer, so that music stops after a short rest period.
2. As a DreamMusic 用户, I want to set a 60-minute sleep timer, so that I can listen while falling asleep without manually stopping playback.
3. As a DreamMusic 用户, I want to set a 120-minute sleep timer, so that I can choose a longer listening window.
4. As a DreamMusic 用户, I want to turn the sleep timer off, so that playback returns to normal continuous behavior.
5. As a DreamMusic 用户, I want to see whether the timer is off or active in Settings, so that I know the current playback policy.
6. As a DreamMusic 用户, I want to see the remaining time as hours, minutes, and seconds, so that the stop point is unambiguous.
7. As a DreamMusic 用户, I want the timer to start immediately when I choose a duration, so that the setting has a clear and predictable meaning.
8. As a DreamMusic 用户, I want choosing a new duration to restart the countdown from now, so that I can extend or shorten the listening session deliberately.
9. As a DreamMusic 用户, I want to cancel an existing timer from the same selection panel, so that I do not need to navigate elsewhere.
10. As a DreamMusic 用户, I want to set a timer even when no song is currently selected, so that I can prepare the listening session before choosing music.
11. As a DreamMusic 用户, I want a song started before the deadline to stop at that deadline, so that the timer remains useful when playback starts later.
12. As a DreamMusic 用户, I want manually pausing playback to leave the timer running, so that the timer means “stop at this time” rather than “play for this many minutes.”
13. As a DreamMusic 用户, I want manually resuming playback before the deadline to respect the existing timer, so that resuming does not silently bypass my choice.
14. As a DreamMusic 用户, I want changing songs to preserve the timer, so that the stop time remains stable across the queue.
15. As a DreamMusic 用户, I want using next or previous to preserve the timer, so that system playback controls do not accidentally cancel it.
16. As a DreamMusic 用户, I want replaying a naturally completed queue item before the deadline to respect the timer, so that the deadline remains authoritative.
17. As a DreamMusic 用户, I want a naturally completed song not to cancel the timer, so that the setting remains available if I start another song.
18. As a DreamMusic 用户, I want an already-paused player at the deadline to remain paused, so that the timer never causes unexpected playback.
19. As a DreamMusic 用户, I want no queue changes when the timer expires, so that the timer controls playback state only.
20. As a DreamMusic 用户, I want no music-library files or metadata to be deleted when the timer expires, so that stopping playback is reversible and safe.
21. As a DreamMusic 用户, I want background playback resources to be released after the timer pauses playback, so that the device does not keep an unnecessary audio task active.
22. As a DreamMusic 用户, I want the system playback state to become paused after expiry, so that lock-screen and control-center controls reflect reality.
23. As a DreamMusic 用户, I want an active timer to survive leaving the Settings page, so that the feature is not tied to a visible UI.
24. As a DreamMusic 用户, I want an active timer to survive sending the app to the background, so that it works during normal locked-screen listening.
25. As a DreamMusic 用户, I want an active timer to survive an Ability destruction and restoration, so that lifecycle transitions do not silently cancel it.
26. As a DreamMusic 用户, I want a not-yet-expired timer to restore after app restart, so that the original deadline remains authoritative.
27. As a DreamMusic 用户, I want an expired timer to be cleared on restart without an extra pause action, so that stale state does not affect a new session.
28. As a DreamMusic 用户, I want the timer to use the device clock deadline, so that elapsed-time calculation remains correct after page changes and background periods.
29. As a DreamMusic 用户, I want the timer to remain unchanged when I log in or out, so that a local playback preference is not coupled to account state.
30. As a DreamMusic 用户, I want the timer to remain unchanged when I switch DreamMusic servers, so that network configuration does not affect local playback control.
31. As a DreamMusic 用户, I want the timer to work for local tracks, so that offline playback retains the same sleep behavior.
32. As a DreamMusic 用户, I want the timer to work for ordinary online playback, so that the feature does not depend on the source of the current track.
33. As a DreamMusic 用户, I want the timer to make no network requests, so that it remains available offline and does not add account requirements.
34. As a DreamMusic 用户, I want a failed pause or resource-release attempt not to trigger repeated actions, so that the player does not oscillate between states.
35. As a DreamMusic 用户, I want any expiry error to remain diagnosable, so that a real-device failure can be investigated without exposing raw technical details in the UI.
36. As a DreamMusic 用户, I want the timer controls to use the existing Settings interaction style, so that the feature feels native to the app.
37. As a DreamMusic 用户, I want the timer absent from the Now Playing page, queue page, resident player bar, and custom lock-screen UI, so that playback remains visually calm.
38. As a DreamMusic 用户, I want the timer to be represented as one device-level playback setting, so that it has one source of truth across pages and lifecycle events.

## Implementation Decisions

- Add a small pure playback-domain timer module responsible for starting, cancelling, restoring, checking expiry, and calculating remaining time. It must not depend on ArkUI, AVPlayer, network services, or account state.
- Use the existing playback orchestration seam as the highest-level integration point. The timer must trigger an explicit pause operation rather than reusing a toggle operation.
- Keep queue ownership in the queue layer and playback/session ownership in the player layer. Expiry must not call next-track, mutate queue order, or alter library records.
- Reuse the existing player-state persistence mechanism. Add idempotent persistence support for timer active/deadline state and preserve compatibility with existing installations that have no timer fields.
- Store an absolute deadline derived from the current wall clock. Remaining time is calculated from the deadline at read/check time and is never persisted as a decrementing counter.
- Detect expiry through multiple existing lifecycle/heartbeat opportunities: playback progress, an in-process deadline trigger, foreground recovery, and application startup recovery. Every path must perform the same deadline comparison and single-expiry guard.
- Make expiry cleanup idempotent. Clear persisted timer state even if pausing or background-resource release reports an error; retain a user-safe diagnostic state/log for investigation.
- Add a Settings-only presentation using the existing Settings row and sheet interaction pattern. The visible state is off or active with remaining `HH:MM:SS`.
- Do not change NightDream routes, API contracts, authentication, online source selection, ordinary streaming, or client download boundaries.
- Do not add a separate network timer, account timer, notification service, or custom lock-screen UI.

## Testing Decisions

Good tests verify externally observable timer behavior and state transitions, not the private choice of timer primitive or ArkUI implementation details.

- Add pure Hypium coverage for the timer domain: fixed-duration conversion, start, restart, cancel, remaining-time clamping, future snapshot restoration, expired snapshot restoration, and one-time expiry.
- Cover behavior where manual pause does not alter the deadline, track changes do not cancel the timer, and no current track is still a valid timer state.
- Cover persistence compatibility for a player state without timer fields and round-trip restoration for an active timer.
- Use existing queue/player behavior tests as prior art for deterministic state-machine assertions; keep timer assertions independent from real media playback.
- Perform device-level validation for ordinary local playback, ordinary online playback, background playback, lock-screen/control-center state, foreground/background transitions, Ability destruction/restart, and resource release.
- Verify that expiry does not change queue order, current track identity, library records, online source behavior, or account state.
- Verify error paths once on device: pause failure or background-task release failure must not cause repeated expiry actions.

## Out of Scope

- Custom durations, arbitrary clock times, recurring schedules, alarms, notifications, or calendar integration.
- A play-for-duration mode that pauses after accumulated playback time.
- Timer controls on the Now Playing page, queue page, resident player bar, lock screen, or control center.
- Automatic next-track behavior, queue mutation, playlist mutation, library cleanup, or metadata changes at expiry.
- Any NightDream, api-enhanced, YouTube, source-adapter, account, binding, API-key, or network contract change.
- A server-side timer or cross-device synchronization.
- Media session features beyond reflecting the existing paused playback state.
- A new persistence table or a second source of truth for player state.

## Further Notes

- This PRD operationalizes the previously agreed design in `docs/functional-design.md`; the feature is not implemented yet.
- The existing worktree contains unrelated user changes and deletions. Implementation must preserve them and modify only the approved feature seams.
- The current source still contains ordinary online playback followed by client-side download-to-library behavior. This PRD intentionally does not reinterpret or change that existing boundary.
- The next delivery phase should break this PRD into vertical issues: pure timer domain, persistence/lifecycle integration, Settings UI, player/background integration, automated coverage, and device acceptance.
