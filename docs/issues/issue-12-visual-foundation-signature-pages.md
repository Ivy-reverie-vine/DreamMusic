# Issue 12:视觉地基 + 签名页(音乐库/正在播放/玻璃底栏)

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1.1-visual-polish.md
- 设计权威: PRODUCT.md / DESIGN.md / PRD-v1.1 Design Tokens 初值表

## What to build

批1: 把 DESIGN.md 的"取色于景/深夜展厅"在签名页落地——设计 token 体系、音乐库列表质感(封面缩略图 + 柔和阴影)、正在播放页展品感(黑胶盘芯 + 翻开过渡 + 弥散光影 + 胶囊进度)、玻璃底栏沉浸光感(自绘触点光晕)、图标体系切换(SymbolGlyph),并顺手修复批1范围内的功能缺口。

## Acceptance criteria

- [ ] `DesignTokens.ets` 落地(字阶/间距/圆角/阴影/玻璃/蒙层),五页逐步改引 token,新代码零手写数字;`scrimNowPlaying` 真正启用
- [ ] 音乐库歌曲视图:行带 40dp 圆角封面缩略图(无封面时主色渐变占位)、柔和阴影卡片、当前正在播放行高亮;心形/加号/删除全部换 SymbolGlyph
- [ ] 正在播放页:封面为黑胶盘芯造型(盘体/内圈高光/轴孔);切歌与进入页时 500–600ms"翻开"过渡(scale+微倾+光晕渐亮);背景加弥散光影(封面主色径向渐变,叠加 scrimNowPlaying);进度条为胶囊灯带;控制按钮(上一首/下一首)换 SymbolGlyph;曲名用 display 字阶 32/700,页面无多余大标题
- [ ] 玻璃底栏:半透明模糊(barBg + BlurStyle.Thin),点击项泛起触点为中心约指尖半径的径向光晕,300ms 扩散淡出;导航图标/文字换 SymbolGlyph + 主题着色
- [ ] 全应用(批1涉及页面)无 emoji 图标残留
- [ ] 功能修复:启动闪黑(start_window_background 深色);启动恢复时封面取色与歌词立即生效(Index 先注入 handler 再 restore);封面文件名重名不互相覆盖
- [ ] 系统"减弱动效"开启时,翻开/光晕/渐变降级为即显/淡化(实现按官方设置读取 API 核实)
- [ ] `hvigorw assembleHap` 编译通过 + Hypium 单测全绿
- [ ] 真机评审:用户确认批1效果后进入 issue-13

## Blocked by

- 无(PRD-v1.1 已评审通过)
