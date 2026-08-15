# Issue 10:网络预留(服务器 Profile + /health 健康检查)

- 标签: `ready-for-agent`
- 父级: docs/PRD-v1-local-music-player.md

## What to build

网络预留的最小闭环(ADR-0002 契约):server_profiles 多配置管理(别名+URL+当前,一键切换);HTTP 适配层封装 http 请求;健康状态机纯逻辑(检查中→在线/离线,3s 超时,2xx 且 body 可解析=在线,启动时+每 15s+手动触发,失败静默);设置页提供配置与状态入口。**严禁出现任何业务端点调用**。

## Acceptance criteria

- [ ] 增/删/改服务器配置,多条并存并一键切换当前
- [ ] 健康状态机纯逻辑有 Hypium 单测:超时→离线、2xx→在线、非 2xx→离线、请求中→检查中
- [ ] 启动时+每 15s+手动刷新触发探活;失败静默,仅状态区显示在线/离线/检查中三态
- [ ] 连接状态变化不影响任何本地功能(离线时音乐库/播放一切照常)
- [ ] 代码中只出现 /health 一个端点,无任何 api-enhanced 业务端点调用

## Blocked by

- issue-01-project-scaffold
- issue-02-library-storage
