# Issue 11:设置页整合、主题与全局空状态打磨

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

设置页聚合所有已实现功能的入口(导入、重新扫描、移除管理、歌单管理、历史清空、服务器 Profile、连接状态);深浅色跟随系统的主题切换;全应用空状态统一风格(空库/空歌单/空队列/无歌词等)。

## Acceptance criteria

- [ ] 设置页包含并正确跳转所有已实现功能的入口
- [ ] 深浅色跟随系统切换即时生效,无页面硬编码颜色残留
- [ ] 各页空状态统一视觉风格与文案(空库/空歌单/空队列/无歌词)
- [ ] 设置页自身的空/异常状态(如无服务器配置)有合理展示

## Blocked by

- issue-04-library-views-scan
- issue-09-playlists-favorites-history
- ADR-0003-request-driven-connectivity
