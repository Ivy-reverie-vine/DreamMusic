# Issue 13:次级页统一 + 专辑/艺术家详情子视图 + 功能缺口收尾

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1.1-visual-polish.md
- 设计权威: PRODUCT.md / DESIGN.md / PRD-v1.1 Design Tokens 初值表

## What to build

批2: 队列/歌单/设置三页统一到批1建立的视觉语言(token + SymbolGlyph + 阴影卡片 + 空状态);专辑/艺术家视图闭环为可点开的详情子视图;收尾剩余功能缺口。

## Acceptance criteria

- [ ] 队列页:行带封面缩略图与阴影、当前曲高亮、播放模式胶囊按钮、拖拽柄换 SymbolGlyph、空状态统一视觉
- [ ] 歌单页:歌单行(收藏心形/自建图标)、最近播放行、重命名浮层、空状态统一视觉,emoji 清零
- [ ] 设置页:卡片分组排版、行内控件统一(背景图/扫描/服务器/历史/主题),emoji 清零,无服务器配置时有合理空状态
- [ ] 专辑/艺术家详情:点击聚合视图行 → tab 内子视图列出该专辑/艺术家的音轨,可点播(点歌即来源列表成队列),返回手势/按钮可用;空详情不报错
- [ ] 功能缺口收尾:
  - 健康轮询归应用级(EntryAbility 启动即轮询,设置页仅手动刷新与状态展示,不再 stopPolling)
  - 随机播放洗牌序持久化(重启后延续上次洗牌周期,新周期首曲不复现上一周期末曲)
  - 断点进度:播放中每 15s + 切后台/销毁时落盘
  - 设置页"恢复默认主题" = 删除背景图文件并回退种子主题(重启后不再恢复取色)
- [ ] `hvigorw assembleHap` 编译通过 + Hypium 单测全绿(含洗牌持久化新增用例)
- [ ] 真机评审:用户确认批2效果后进入 issue-14

## Blocked by

- issue-12-visual-foundation-signature-pages
