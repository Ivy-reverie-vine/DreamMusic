# ADR-0002: 与 api-enhanced 的连接健康检查契约

- 日期: 2026-02-13
- 状态: **已被 ADR-0003 取代**(2026-08-16,用户拍板:不补 /health,改为请求驱动连接判定)
- 关联: docs/research/api-enhanced.md

## 背景

应用未来依赖自建的 api-enhanced 服务(跑在用户电脑上,经 Cloudflare Tunnel 域名暴露)。当前阶段只预留接口,但必须有一种机制判定"在线/离线",使应用在离线时完全退化为纯本地播放器。

已核实事实: api-enhanced 的 README **没有** `/health` 端点;默认 HTTP:3000;用户已本地克隆该仓库且允许我们修改它。

## 决策

1. 客户端契约固定为 `GET {baseUrl}/health`:
   - 超时 3s;2xx 且响应体可解析 → **在线**;超时/连接失败/非 2xx → **离线**;请求中 → **检查中**
   - 触发时机: 应用启动时 + 每 15s 定时 + 设置页手动刷新
   - 失败静默(仅状态区展示三态,不弹窗打扰)
2. 服务端: 由我们后续在 api-enhanced 本地 clone 中补一个极简 `GET /health` 端点(返回 JSON 即可,如 `{"code":200,"status":"ok"}`),与客户端契约对齐
3. 服务器配置支持多条 Profile(别名+URL),主=Cloudflare Tunnel 域名(HTTPS,公网证书,无需 caPath),备=局域网直连
4. 当前阶段只实现"配置管理 + HTTP 网关 + 健康检查",不调用 api-enhanced 任何业务端点

## 理由

- 轮询 + 静默三态是离线优先应用的标准降级姿势;15s 平衡实时性与耗电,3s 超时避免网络差时卡 UI
- 契约先行、端点后补: 客户端不假设 api-enhanced 已有任何端点(不编造 API);同时预留单一契约点,未来业务请求全部经同一网关(baseUrl + 鉴权策略)发出
- 公网证书方案避免了自签名证书在鸿蒙端的 `caPath` 导入与证书轮换负担

## 后果

- 若真机发现鸿蒙 NEXT 禁止明文 HTTP,局域网备选 Profile 需改为 HTTPS 反代或验证 cleartextTraffic 配置(记录于 docs/research/harmonyos-official-docs.md 待办清单)
- 未来接入业务端点时,所有请求必须复用此健康状态与 baseUrl,不得另起炉灶
