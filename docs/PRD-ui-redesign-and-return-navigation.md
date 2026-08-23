# PRD：DreamMusic UI 信息架构重构与系统返回治理

状态：已实现，待真机验收
日期：2026-08-23
目标平台：HarmonyOS 6.1 / API 23 / ArkTS / phone

## Problem Statement

DreamMusic 当前仍使用五个底部入口：音乐库、正在播放、队列、歌单、我的。歌单、播放历史、账户业务和设置职责分散，导致个人内容入口重复；`我的` 页面目前只承载账户摘要和历史，歌单仍是独立 root 页面，设置仍通过 sheet 展示。

同时，应用主壳没有统一处理 HarmonyOS 的系统返回和边缘返回手势。当前页面切换只有 tab 下标，没有页面返回栈；用户在真机上从屏幕边缘滑动时，容易直接离开应用，而不是返回上一级内容。

账号统计、签到、公告、发消息和梦点相关操作也分散在设置或未完成的页面状态中，无法形成清晰的账户内容中心。播放统计还没有统一的读取编排和明确的“真实 0 / 未登录 / 加载失败”状态。

## Solution

将应用重构为四个一级入口：

1. 音乐库
2. 正在播放
3. 队列
4. 我的

“我的”成为个人内容与账户业务中心，首页顺序固定为：

账户摘要 → 播放统计 → 我的歌单 → 最近播放 → 设置

“我的”内部使用全页子状态，包括：

- 我的首页；
- 本地与在线歌单列表；
- 歌单详情；
- 播放历史详情；
- 播放统计详情；
- 账户详情；
- 公告与消息；
- 设置。

在应用入口统一接管 HarmonyOS 返回事件：先关闭覆盖层，再返回“我的”或其他内部子状态；只有已经处于 root 首页时才交给系统默认返回。系统边缘返回从其他一级入口深链进入的子页面时，应回到来源入口；从“我的”内部进入的子页面返回“我的”首页。

## User Stories

1. As a 本地音乐用户, I want to see four stable root tabs, so that I can reach core playback areas without a separate song-list tab occupying navigation.
2. As a 用户, I want the “我的” tab to be a personal content hub, so that playlists, history, statistics, account actions, and settings have one predictable home.
3. As a 用户, I want the “我的” homepage ordered as account summary, statistics, playlists, recent history, settings, so that high-value personal content appears before low-frequency management.
4. As a 用户, I want local playlists and online NetEase playlists grouped inside “我的”, so that migrating navigation does not remove existing online library capabilities.
5. As a 用户, I want “我喜欢的音乐” to remain fixed and non-deletable, so that its current domain behavior is preserved after migration.
6. As a 用户, I want playlist and history details to open as full pages, so that long lists do not compete with the dashboard scroll or appear inside nested sheets.
7. As a 用户, I want settings to open as a full-page child state, so that system back and in-app back behave consistently.
8. As a 用户, I want settings to contain authentication, binding, theme/background, local library, server, and diagnostics, so that settings remains configuration and account-management space.
9. As a 用户, I want announcements to be outside settings, so that public information is not hidden among configuration controls.
10. As a 未登录用户, I want to read public announcements, so that public platform information is available without an account.
11. As a 未登录用户, I want check-in and message actions to show a login guide instead of failing silently, so that I understand why those actions are unavailable.
12. As a 已登录但未绑定用户, I want check-in and message actions to remain available, so that account actions are not incorrectly blocked by NetEase binding.
13. As a 已登录用户, I want a one-tap check-in action in the account summary, so that daily check-in does not require entering settings.
14. As a 已登录用户, I want check-in to disable duplicate taps and show the updated points/status, so that the idempotent operation is clear.
15. As a 用户, I want an “公告与消息” shortcut card below the account summary, so that I can find public announcements and account messaging without searching settings.
16. As a 用户, I want the homepage card to show announcement count and the newest title, so that the dashboard stays compact while the full page remains discoverable.
17. As a 用户, I want the full announcements-and-messaging page to show announcements first and a collapsed message form below, so that announcements remain the primary content.
18. As a 用户, I want the message form to show daily usage, remaining quota, and points before expansion, so that I understand the cost and limit before composing.
19. As a 用户, I want message submission to preserve the existing one-point charge, three-per-Shanghai-day limit, and failure-is-still-charged semantics, so that the UI matches server accounting.
20. As a 用户, I want account details to contain points balance, redeem code, and read-only recent point logs, so that points-related actions are separated from authentication settings.
21. As a 用户, I want account summary to show username, binding state, points, check-in status, message quota, and links to account details, announcements/messages, and settings, so that it stays useful without embedding forms.
22. As a 用户, I want account state changes to update across pages, so that login, logout, check-in, redeem, message send, and binding changes do not leave stale balances or binding labels.
23. As a 用户, I want account statistics to show account-level accumulated play time and played-song count, so that I can see cross-device listening history.
24. As a 用户, I want device statistics to show local play records, custom playlist count, and favorite count, so that I can understand this device separately from my account.
25. As a 用户, I want repeated local plays to count as separate play records, so that the device metric reflects playback events rather than distinct songs.
26. As a 用户, I want custom playlist count to exclude the fixed favorites playlist, so that playlist and favorite metrics do not double-count.
27. As a 用户, I want account and device statistics labeled by source, so that I do not confuse server totals with this-device data.
28. As a 用户, I want statistics details to show account source and last synchronization time, so that stale server data is understandable.
29. As a 未登录用户, I want device statistics to remain available, so that local playback history is not hidden behind account login.
30. As a 离线用户, I want local content and playback to remain usable while account statistics fail independently, so that network conditions do not block offline listening.
31. As a 用户, I want a real zero statistic to be distinguishable from unavailable data, so that an empty account is not confused with a failed request.
32. As a 用户, I want failed account statistics to retain the last successful in-memory value with a stale/unavailable indicator, so that temporary outages do not erase useful context.
33. As a 用户, I want account statistics to load on entering “我的” or statistics detail and refresh manually, so that the app avoids unnecessary polling.
34. As a 用户, I want account statistics to be read from the dedicated profile endpoint, so that login-gate identity checks and statistics loading remain separate concerns.
35. As a 用户, I want the page to render local data without waiting for the profile request, so that slow networks do not delay the “我的” page.
36. As a 用户, I want the system edge-back gesture to close an open overlay first, so that a gesture does not unexpectedly exit the app while a login/binding layer is visible.
37. As a 用户, I want the edge-back gesture from a “我的” child page to return to the correct parent, so that system navigation matches visible page hierarchy.
38. As a 用户, I want a deep-linked settings or account page to return to the originating root tab, so that I return to the context that sent me there.
39. As a 用户, I want selecting another root tab and returning to “我的” to land on the “我的” homepage, so that the root tab does not reopen an old settings/detail screen unexpectedly.
40. As a 用户, I want login success to preserve my source page and search context without automatically replaying the original operation, so that playback, downloads, or charged actions are never duplicated.
41. As a 用户, I want the resident mini-player and glass bottom navigation to remain available on “我的” child pages, so that playback controls are never buried by account content.
42. As a 真机验收人员, I want root-page edge back to use the system default behavior only after all app-level states are closed, so that the exit behavior is intentional and testable.

## Implementation Decisions

- The main shell owns root-tab selection, child navigation intent, source return context, and the single back-event policy.
- The root shell must register HarmonyOS entry-level back handling. The handler consumes the event while an overlay or app-managed child state can move backward; it delegates to the system only at an actual root state.
- Internal “我的” pages use explicit state rather than mixing independent booleans, sheets, and root tabs.
- Navigation transitions must carry a source context for deep links from the library, now-playing, or queue roots.
- Selecting another root tab clears the “我的” child state; selecting “我的” again shows its homepage.
- Settings, statistics, playlist details, history details, account details, and announcements/messages use full-page content with their own scroll region; bottom navigation and the resident player remain outside that region.
- Local and online playlist data remain separate sections and load independently. Online failure must not block local playlists or local playback.
- Account-level statistics are read through the authenticated profile contract. The existing login/identity endpoint remains responsible for gate and account-summary identity checks.
- A dedicated playback-statistics view model composes account statistics and local SQLite-derived statistics. The page does not call HTTP or database APIs directly.
- Account statistics state distinguishes unauthenticated, loading, successful zero, successful nonzero, stale-after-failure, and unavailable-after-failure.
- Account statistics are refreshed on entry and by an explicit detail-page refresh; there is no periodic polling and no persistence of account statistics in local preferences or SQLite.
- Local play records are derived from the existing play-history event rows. Repeated plays count separately; the metric is not named lifetime total because local history is capped at 500 rows.
- Local playlist count includes custom playlists only. The fixed favorites playlist is excluded; favorites are counted separately from the favorites table.
- The account snapshot is the shared source for username, binding state, dream points, check-in state, and daily message quota. Page-local copies must refresh from it after account actions.
- Check-in is a direct, idempotent account-summary action with loading and already-checked states.
- Public announcements remain visible when logged out. Check-in and messaging require DreamMusic authentication but do not require NetEase binding.
- “公告与消息” is one full-page child: announcements first, collapsed messaging form second. No read/unread state or badge is added in this scope.
- Account detail contains point balance, redeem code, and read-only recent point logs. Authentication, sessions, credentials, and NetEase binding remain in settings.
- Existing ordinary playback/download boundaries, NightDream source abstraction, offline-first behavior, and HarmonyOS Kit constraints remain unchanged.

## Testing Decisions

- Tests assert external behavior at the highest available seam: the app-shell back-state policy, view-model state transitions, service contract mapping, and real-device gesture behavior. They should not assert private component implementation details.
- Add pure logic coverage for the app-shell back policy: overlay first, child-to-parent, deep-link-to-source, root delegation, and root-tab reset.
- Add view-model coverage for local statistic derivation, custom-playlist exclusion, favorite count, 500-row play-history semantics, and account-statistic state transitions.
- Add service/API contract coverage for profile statistics, public announcements, check-in, redeem, and message result/quotas, including authentication and unbound-account cases.
- Add cross-page state coverage proving that login/logout, check-in, redeem, message send, and binding changes refresh account summary and dependent online state.
- Add HarmonyOS Hypium or equivalent system-level coverage where possible for entry-level back dispatch and overlay dismissal; the root edge-back behavior requires real-device acceptance because gesture dispatch is system-owned.
- Real-device acceptance must cover: edge back from every “我的” child page; edge back with login/binding/message overlays; deep link from library to settings/account detail; root-page back; bottom-tab switching; mini-player visibility; offline profile failure; and login success without automatic replay.
- Run the existing pure-logic test suite and the HarmonyOS HAP build after implementation. UI and system gesture acceptance cannot be replaced by a successful compile.

## Out of Scope

- Extending the implementation beyond the UI information architecture, account-content placement, playback statistics, and return policy defined in this PRD.
- Adding a fifth data source, changing NightDream source dispatch, or exposing source-specific APIs to the client.
- Changing ordinary playback or server-side download semantics.
- Adding timer playback, new HarmonyOS feature cards, social features, comments, rankings, charts, trend analysis, or sharing.
- Adding announcement read/unread state, notification badges, or a notification center.
- Persisting account statistics locally.
- Counting lifetime local play time without a new explicit data model.
- Adding Android APIs, Android storage/navigation assumptions, or undocumented HarmonyOS APIs.

## Implementation Record

- `EntryAbility.ets` now loads `IndexV2.ets`; the root shell has four tabs and owns the entry-level `onBackPress` policy.
- `MyPageV2.ets` provides the “我的” overview and full-page child states for playlists, history, statistics, account details, announcements, and settings. Announcements, check-in, and messaging are no longer placed inside settings.
- `Navigation.ets` centralizes root-tab selection, child-page entry, source return context, and overlay → child → source-root → system back resolution.
- `PlaybackStatsViewModel.ets` composes account statistics from `GET /auth/profile` with local `play_history`, `playlists`, and `favorites` aggregates.
- Automated pure-logic tests, Hypium tests, HAP build, and `git diff --check` passed. HarmonyOS edge-back and visual acceptance on a real device remain pending.

## Further Notes

- The server-side profile contract and authentication-only behavior for check-in/message were verified against the current NightDream source before this PRD was written.
- The implementation should preserve the project’s existing glass navigation, dynamic theme, resident mini-player, offline-first behavior, and HarmonyOS ArkUI visual system.
- The remaining delivery step is real-device acceptance: edge back from every “我的” child page, overlays, deep links, root-page back, bottom-tab switching, mini-player visibility, and offline account-statistics failure.
