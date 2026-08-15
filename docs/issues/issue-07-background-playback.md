# Issue 07:后台播控(AVSession + 长时任务)

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

AVSession 媒体会话:激活、同步媒体信息(标题/艺术家/封面/时长/进度)、处理系统播控命令(播放/暂停/上一首/下一首/跳转);audioPlayback 长时任务在播放时申请、停止时释放;锁屏与控制中心展示播控面板;耳机/蓝牙播控键生效。

## Acceptance criteria

- [ ] 切后台/锁屏后音乐持续播放
- [ ] 锁屏与控制中心显示封面/标题/上下首/暂停,命令正确作用于播放器
- [ ] 耳机线控与蓝牙播控键生效
- [ ] 开始播放时申请 audioPlayback 长时任务,播放停止/退出时正确释放
- [ ] 系统播控命令与队列域状态保持一致(切歌后系统面板信息同步更新)

## Blocked by

- issue-05-playback-core
