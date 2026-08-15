# Issue 08:本地歌词(.lrc)

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

读取音轨同目录同名 `.lrc` 文件,解析时间轴歌词,在正在播放页随播放滚动展示;无 `.lrc` 时隐藏歌词区(不报错);编码异常时优雅降级。

## Acceptance criteria

- [ ] 音轨同目录存在同名 .lrc 时,正在播放页显示歌词并基本同步滚动
- [ ] 无 .lrc 时歌词区隐藏,播放体验不受影响
- [ ] .lrc 编码异常/格式损坏时不崩溃,降级为不显示歌词

## Blocked by

- issue-05-playback-core
