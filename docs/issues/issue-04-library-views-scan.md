# Issue 04:音乐库三视图与扫描

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

音乐库页的歌曲/专辑/艺术家三个视图(数据全部来自数据库聚合);启动增量扫描与手动重扫(diff 语义:数据库快照 vs 沙箱目录清单);移除音轨的两种模式(仅移出音乐库 / 连同沙箱文件删除);空库与无结果空状态。扫描 diff 为纯逻辑进单测。

## Acceptance criteria

- [ ] 歌曲/专辑/艺术家三视图可切换浏览,列表可滚动点选
- [ ] 启动时自动增量扫描:新文件入库并提元数据,消失文件标记"文件缺失"(保留记录,不自动删)
- [ ] 设置页提供"重新扫描"手动触发
- [ ] 移除音轨两种模式均可用,操作后数据库与沙箱文件系统保持一致
- [ ] 空库/视图无结果时显示统一空状态引导(引导用户去导入)
- [ ] 扫描 diff 逻辑有 Hypium 单测

## Blocked by

- issue-02-library-storage
- issue-03-import-pipeline
