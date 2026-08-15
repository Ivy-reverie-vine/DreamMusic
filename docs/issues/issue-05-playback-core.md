# Issue 05:播放核心(AVPlayer + 正在播放页)

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

AVPlayer 会话适配层(create → setSource(沙箱路径) → prepare → play,状态事件收敛为领域事件);正在播放页:封面/标题/艺术家/专辑显示、播放/暂停/继续、进度实时刷新与拖拽跳转、音量调节;暂停按钮为不规则椭圆泡泡(非方正按钮)。此切片只要求单曲播放完整可用,队列与后台能力由后续切片叠加。

## Acceptance criteria

- [ ] 点击音乐库中的音轨即可播放其沙箱文件
- [ ] 播放/暂停/继续/进度跳转/音量调节正常,进度实时刷新
- [ ] 标题/艺术家/专辑/封面显示正确
- [ ] 暂停按钮是不规则椭圆泡泡造型
- [ ] 单曲播放结束状态正确收敛,并暴露"播放结束"领域事件(供队列切片消费)
- [ ] 播放器会话为适配层实现,上层经领域接口调用(为队列/后台切片预留挂点)

## Blocked by

- issue-02-library-storage
- issue-03-import-pipeline
