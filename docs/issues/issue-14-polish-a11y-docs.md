# Issue 14:动效打磨 + 无障碍 + 文档回填

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1.1-visual-polish.md
- 设计权威: PRODUCT.md / DESIGN.md / PRD-v1.1 Design Tokens 初值表

## What to build

批3: 全应用动效一致性打磨(切歌渐变、列表点击反馈、页面切换过渡)、减弱动效适配收尾、文档回填(DESIGN.md token 实值、CONTEXT.md 新术语、PRD 验收对照),并做收尾质量门禁。

## Acceptance criteria

- [ ] 切歌取色渐变:主题色变化 500ms 过渡,且封面/控件/背景光晕同步过渡,无闪变
- [ ] 列表行点击反馈统一(150ms 透明度反馈);黑胶翻开/触点光晕在"减弱动效"开启时全部降级为即显/淡化,无残留动画
- [ ] 全应用 emoji 清零(全局 grep 复核:♡♥＋✕≡✎🗑🔊⏮⏭🌙☀等)
- [ ] 五页视觉一致性走查:字阶/间距/圆角/阴影均来自 token,无手写数字残留(颜色除外)
- [ ] 文档回填:
  - DESIGN.md:敲定全部"to be resolved"(字阶/间距栅格/圆角/阴影/模糊),回填实现实值,移除 SEED 注释
  - CONTEXT.md:新增"专辑详情/艺术家详情"术语(如已提前添加则校验一致)
  - 本 PRD 与 issue-12/13/14 验收清单打勾,记录真机评审结论
- [ ] `hvigorw assembleHap` 编译通过 + Hypium 全绿
- [ ] 真机终评:用户确认整体效果满意;遗留问题转为新 issue(如有)

## Blocked by

- issue-13-secondary-pages-detail-views
