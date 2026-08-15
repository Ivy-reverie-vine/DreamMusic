# Issue 03:导入管线

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

端到端导入:系统选择器挑选音频文件/文件夹 → 格式白名单过滤(MP3/AAC(M4A)/FLAC/WAV)→ 复制进应用沙箱 → AVMetadataExtractor 提取标题/艺术家/专辑/时长/封面 → 按沙箱相对路径去重 → 入库,全程显示复制进度。白名单、去重与导入规划为纯逻辑,进入 Hypium 单测;选择器、复制与元数据提取为适配层,真机验证。

## Acceptance criteria

- [ ] 可经系统选择器挑选多个音频文件或整个文件夹
- [ ] 不支持的格式被拒绝并提示,不产生垃圾文件
- [ ] 导入过程可见进度,完成后音轨立即出现在音乐库
- [ ] 重复导入同一文件被跳过(去重按沙箱相对路径)
- [ ] 标题/艺术家/专辑/时长/封面提取入库,封面可显示
- [ ] 白名单/去重/导入规划逻辑有 Hypium 单测

## Blocked by

- issue-01-project-scaffold
- issue-02-library-storage
