# Issue 01:工程骨架与导航脚手架

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

搭建应用的地基:MVVM 五目录骨架(model/service/viewmodel/components/common)、Navigation 五页空壳(音乐库/正在播放/播放队列/歌单/设置)、Hypium 本地测试关卡、模块级权限与后台任务声明。此切片完成后,后续所有切片都有"编译+测试+可导航页面"的落点。五页骨架与组件库必须**复用 issue-00 的主题服务与 DESIGN.md token**,不得硬编码颜色。

## Acceptance criteria

- [ ] `hvigorw assembleHap` 编译通过
- [ ] 应用启动进入音乐库页,可导航到全部五个页面(空页即可)
- [ ] 五页骨架使用主题服务取色(DESIGN.md 角色),无硬编码颜色
- [ ] Hypium 本地单元测试可执行(模板测试替换为最小真测试,验证测试关卡)
- [ ] module.json5 声明 `ohos.permission.INTERNET`、`ohos.permission.KEEP_BACKGROUND_RUNNING` 与 `backgroundModes: ["audioPlayback"]`
- [ ] 目录与依赖方向约定落地(新增代码只能按 view → viewmodel → service → model 单向依赖)

## Blocked by

- issue-00-ui-design-foundation
