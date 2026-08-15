# UI 参考调研笔记

> 用户审美参考来源与已确认的吸收决策。视觉权威见根目录 PRODUCT.md / DESIGN.md。

## 1. QQ 音乐鸿蒙版 "Air 设计"(用户表示喜欢其中一些优点)

| # | 特点 | 来源 | 决策 |
| :-: | :--- | :--- | :--- |
| 1 | 整体界面清爽、轻盈通透、大留白 | [DoNews](https://www.donews.com/news/detail/4/6655252.html)、[ZOL](https://news.zol.com.cn/1226/12263108.html) | ✅ 已含于 DESIGN.md(大留白+内容优先) |
| 2 | 玻璃拟态/毛玻璃质感 | [极客公园](https://w.geekpark.net/news/368283) | ✅ 已含于 DESIGN.md(毛玻璃质感背景) |
| 3 | 点开专辑像"翻开实体黑胶唱片",听歌仪式感 | [新浪用户反馈](https://www.sina.cn/news/detail/5328252043264474.html) | ✅ **用户授权我看着办**:采纳温和版(正在播放页封面轻微展开+微旋转),标注原型阶段评审 |
| 4 | **底部导航点击发光**:触点为中心、约一个指尖半径为半径泛起光晕,光随手指 | 用户实测观察;对应官方特性"沉浸光感" | ✅ 采纳:官方 [沉浸光感最佳实践](https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-spatiality-immersive)、[光效光源跟手](https://developer.huawei.com/consumer/cn/forum/topic/0203213193412845108) |
| 5 | **底部导航半透明模糊**:不遮内容,内容从底栏下透过可见 | 用户实测观察;同源沉浸光感能力 | ✅ 采纳:玻璃底栏,[HdsTabs 沉浸光感底部导航](https://ai6s.net/6a4a640d10ee7a33f2882a26.html)、[沉浸光感组件导航](https://bbs.itying.com/topic/6a2b9e2ab50553004baead69) |
| 6 | 银河音效 | [IT之家](https://www.ithome.com/0/875/704.htm) | ❌ 功能而非 UI,且属音效类,不在 v1 范围 |

## 2. 沉浸光感(官方特性,鸿蒙 6.x 新能力)

- 目标环境 HarmonyOS 6.1 / API 23 在覆盖范围内
- 实现时以官方最佳实践文档为准:`bpta-spatiality-immersive`(沉浸光感)
- 注意区分:我们只要**触点光晕 + 玻璃底栏**两种用法,不引入大面积光效(与 DESIGN.md 的克制原则一致)
- ❓ 待实现时核实:该特性的组件/接口名(如 HdsTabs、光感参数)与是否需要特性开关,以官方 API 参考为准,不凭社区帖猜测

## 3. 用户确认过的其他设计输入(见 DESIGN.md)

- 自定义背景图 + 随图取色 + 封面取色(品牌承诺)
- 鸿蒙五特质:大圆角卡片+柔和阴影+弥散光影 / 大留白+内容优先 / HarmonyOS Sans+清晰字阶 / 克制自然动效 / 毛玻璃质感背景
- 椭圆泡泡暂停按钮(IDEA.md)
