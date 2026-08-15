# Issue 02:音乐库存储与 DAO

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

用 relationalStore 建立 8 张物理表(7 张业务表: tracks / albums / artists / playlists / play_history / favorites / server_profiles,加 1 张关联表 playlist_tracks 承载歌单-音轨有序关联),并实现存储适配层的完整 CRUD 接口。所有 schema 变更收在存储适配层内,上层只见领域接口不见 SQL。

## Acceptance criteria

- [ ] 应用启动自动建库建表,重复启动幂等不报错
- [ ] 音轨以"沙箱相对路径"为唯一键,插入重复路径被数据库约束拒绝
- [ ] 音轨/专辑/艺术家/歌单/关联/收藏/历史/服务器 Profile 的 CRUD 经存储适配层可用(真机验证)
- [ ] 播放历史插入时按 500 条上限滚动淘汰最旧记录
- [ ] "我喜欢的音乐"作为系统保留歌单记录存在,删除接口对它失效

## Blocked by

- issue-01-project-scaffold
