# PRD v1.1:视觉强化与动效落地(IvyReverieMusic Visual Polish)

- 阶段: to-prd(grill-with-docs → **to-prd** → to-issues → implement-review)
- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md(v1.1 不改变领域模型,只补视觉与动效)
- 依据: 用户评审结论(真机观察:视觉观感远低于 DESIGN.md 承诺、签名动效缺失)+ 代码验证清单(issue-00/01 多 AC 未闭环)
- 目标环境: HarmonyOS 6.1 / API 23 / ArkTS / 真机 phone(验收一律真机)
- 视觉权威: PRODUCT.md / DESIGN.md(本次把 DESIGN.md 全部"to be resolved"敲定并回填)

## Problem Statement

v1 功能层已全部落地(编译 ✅、Hypium 单测 ✅、MVVM 分层 ✅),但真机观感远低于 DESIGN.md 的"取色于景/深夜展厅"承诺:

- 列表页为纯文字行,无封面缩略图、无阴影、无弥散光影 → "封面如展品"未落地
- 底部导航玻璃底栏有模糊但无"沉浸光感"点击反馈(触点光晕)→ 用户实测点名的签名交互缺失
- 正在播放页无"黑胶展开"签名交互(设计稿悬置"原型阶段评审",本次评审落地)
- 全应用 emoji 当图标(♡ ♥ ＋ ✕ ≡ ✎ 🗑 🔊 ⏮ ⏭ 🌙 ☀️),不同设备渲染不一致,与"静谧克制"品牌冲突
- 五页标题全为 28 号粗体,违反 DESIGN.md"大标题只属于正在播放页曲名"
- 启动闪白(start_window_background #FFFFFF),与深夜主题冲突
- 部分功能 AC 未闭环(专辑/艺术家视图点不开、15s 轮询绑定设置页生命周期、随机洗牌序未持久化、断点进度仅暂停时落盘、启动恢复时封面取色/歌词不生效、"恢复默认主题"不持久、封面文件名同 basename 互相覆盖)

## Solution

一次"兑现 DESIGN.md"的视觉 pass,分三批真机评审交付:

### 批1 — 视觉地基 + 签名页(issue-12)

设计 token 体系、音乐库列表质感、正在播放页展品感、玻璃底栏沉浸光感、图标体系切换。

### 批2 — 次级页统一 + 详情子视图(issue-13)

队列/歌单/设置三页统一风格;专辑/艺术家详情子视图(顺手闭环 AC);功能缺口收尾。

### 批3 — 动效打磨 + 无障碍 + 文档回填(issue-14)

切歌渐变/点击反馈打磨、减弱动效降级、DESIGN.md/CONTEXT.md 回填、全页 emoji 清零。

## Design Tokens(初值,真机微调后回填 DESIGN.md)

所有数值集中在 `entry/src/main/ets/common/DesignTokens.ets`,页面禁止手写数字(颜色除外,颜色只准从 ThemeService 取)。

### 字阶(HarmonyOS Sans,dp)

| token | 字号/字重 | 用途 |
| :--- | :--- | :--- |
| display | 32 / 700 | **仅**正在播放页曲名 |
| title | 20 / 600 | 页面标题(音乐库/队列/歌单/设置) |
| body | 15 / 400 | 列表主文本 |
| bodyStrong | 15 / 500 | 当前曲/选中项 |
| label | 12 / 400 | 辅助文本/副标题 |
| caption | 11 / 400 | 时间码/角标 |

### 间距(4dp 栅格)

| token | 值 | 用途 |
| :--- | :--- | :--- |
| spaceXs | 4 | 图标与文字微距 |
| spaceSm | 8 | 行内元素间距 |
| spaceMd | 12 | 行内分组间距 |
| spaceLg | 16 | 卡片内间距/区块间距 |
| spaceXl | 20 | 页面 padding |
| spaceXxl | 24 | 区块大间距 |

### 圆角

| token | 值 | 用途 |
| :--- | :--- | :--- |
| radiusCard | 16 | 卡片/列表行 |
| radiusControl | 12 | 输入框/小控件 |
| radiusCapsule | 999 | 胶囊按钮/标签/进度灯带 |

### 阴影与光影(弥散优先,克制)

| token | 值 | 用途 |
| :--- | :--- | :--- |
| shadowCard | radius 20, color '#33000000', offset(0,6) | 列表卡片柔和阴影(深色下更淡) |
| shadowGlow | radius 48, color primary @ 33, offset(0,0) | 正在播放页封面光晕/展品感 |
| glowNowPlaying | 背景径向渐变 primary @ 18% → 透明 | 正在播放页弥散光影(scrimNowPlaying 之上) |

### 玻璃与蒙层

| token | 值 | 用途 |
| :--- | :--- | :--- |
| barBg | 深色 '#59000000' / 浅色 '#59FFFFFF' + BlurStyle.Thin | 玻璃底栏 |
| scrimList | 0.65(现状保留) | 列表页背景图蒙层 |
| scrimNowPlaying | 0.45(现状 token,本次真正启用) | 正在播放页背景图蒙层 |
| cardBg | 深色 '#12FFFFFF' / 浅色 '#0A000000' | 卡片底色(半透明白/黑,叠于蒙层之上) |

### 签名动效

| 动效 | 规格 | 减弱动效降级 |
| :--- | :--- | :--- |
| 黑胶翻开 | 500–600ms:封面 scale 0.92→1 + rotate 微倾(≤8°→0)+ 光晕渐亮;仅切歌/进入页时触发 | 纯淡入 200ms |
| 切歌取色渐变 | 500ms animateTo(现状保留,页面元素同步过渡) | 即显 |
| 触点光晕 | 点击处径向渐变圆(指尖半径)→ 300ms 缩放扩散 + 快速淡出 | 不显示 |
| 列表点击 | 行内 150ms 透明度 0.7→1 反馈 | 即显 |

## Implementation Decisions

1. **图标体系**: 全部 emoji → `SymbolGlyph`(官方系统符号,API 11+;着色随 ThemeService;播放/暂停/心形/加号/删除/更多均有对应符号;符号名以 SDK `id_defined.json` 逐一核实为准)
2. **沉浸光感**: 自绘触点光晕(按下亮起白光大圆 → 随指移动 → 松手 260ms 扩散淡出;浅色主题自动切黑色柔光;系统"减弱动效"时降级为无);官方 HDS 组件为实现期备选
3. **黑胶盘芯**: 封面(圆形)为盘芯标签,外圈深色盘体(同心圆 + 内圈高光描边),中央轴孔;不常驻旋转;切歌/进入页 550ms"翻开"(scale+rotateY 微倾+淡入)
4. **专辑/艺术家详情**: tab 内子视图(与歌单页 selected 同模式),不加路由栈,保持五页框架(PRD-v1 约束)
5. **主题**: 默认深色;设置页三态切换(深色/浅色/跟随系统),preferences 持久化;仅"跟随系统"响应系统深浅(真机反馈:跟随系统导致白底观感差,故默认深色)
6. **导入入口**: 仅"导入文件";文件夹选择移除(`DocumentSelectMode.FOLDER` 仅 2-in-1 设备支持,手机不可用)
7. **播放历史清空**: 入口仅在歌单页"最近播放";设置页不放置
8. **功能缺口修复**(批1/批2 内顺手完成):
   - 启动闪黑:`start_window_background` → '#0D0F10'
   - 启动恢复取色/歌词:Index 启动时先注入 handler 并 setContext,再 restore
   - 封面文件名冲突:提取时重名则追加序号(与导入规划器同策略)
   - 复制兼容:copyFileRobust(copyFileSync 失败回退 openSync 流式复制),导入/背景图失败原因上屏
   - 轮询全局化:轮询归 EntryAbility 生命周期,设置页只做手动刷新与状态展示
   - 随机洗牌序持久化:player_state 增加 shuffle_order/shuffle_pos/shuffle_steps 字段(旧数据自动迁移回退重建)
   - 断点定时落盘:播放中每 15s + 切后台/销毁时落盘(现有"暂停时落盘"保留)
   - "恢复默认主题" = 删除背景图文件 + applyDefault(持久生效)
9. **验收**: 每批结束 `hvigorw assembleHap` + Hypium 全绿 + 真机评审;全批完成回填 DESIGN.md(token 实值)与 CONTEXT.md

## Out of Scope(保持 v1 边界)

- api-enhanced 任何业务端点、流媒体、音效、歌词编辑、多设备
- 常驻黑胶旋转、大面积光效、霓虹/渐变文字(反 DESIGN.md)
- 非 phone 形态适配

## Further Notes

- AGENT.md 约束不变:所有系统能力基于 Kit 官方文档;改动按批次征得用户同意后实施
- 真机评审为硬关卡:每批完成必须由用户在真机确认,确认前不进入下一批
