# v1 设计决策总表(grill-with-docs 产物)

> 来源: 12 问交互式访谈,逐条经用户确认。术语定义见 `CONTEXT.md`,依据见 `docs/adr/` 与 `docs/research/`。

## 决策清单

| # | 主题 | 决策 |
| :-: | :--- | :--- |
| 1 | 音乐文件模型 | 导入复制进应用沙箱(ADR-0001) |
| 2 | 后台播控 | v1 完整实现: AVSession + audioPlayback 长时任务 + 锁屏/控制中心播控 |
| 3 | 音频格式 | MP3 / AAC(M4A) / FLAC / WAV |
| 4 | 元数据 | 导入时用 AVMetadataExtractor 提取标题/艺术家/专辑/时长/封面 |
| 5 | 歌词 | v1 仅读音轨同目录同名 .lrc(有则显示);在线歌词留给 api-enhanced 阶段 |
| 6 | 数据库 | relationalStore **8 张物理表**(7 业务表: tracks / albums / artists / playlists / play_history / favorites / server_profiles + 1 关联表 playlist_tracks;server_profiles 为网络预留补充) |
| 7 | 去重与扫描 | 音轨唯一键=沙箱相对路径;启动时增量比对 + 设置页手动全量重扫 |
| 8 | 播放队列 | 持久化,重启恢复;四种播放模式(顺序/单曲循环/列表循环/随机);断点续播 |
| 9 | UI 页面 | 5 页: 音乐库(歌曲/专辑/艺术家)、正在播放、播放队列(拖拽排序)、歌单、设置 |
| 10 | 收藏/歌单/历史 | 收藏=单曲标记自动聚合进固定歌单"我喜欢的音乐";自建歌单可增删改;历史自动记录上限 500 条可清空 |
| 11 | 服务器配置 | 手动多 Profile(别名+URL)一键切换;主=Cloudflare Tunnel 域名(HTTPS 公网证书),备=局域网直连 |
| 12 | 健康检查 | `GET /health`,3s 超时,启动+15s 轮询+手动,三态(在线/离线/检查中)静默显示(ADR-0002) |
| 13 | 架构 | MVVM 五目录: model / service / viewmodel / components / common,依赖单向 |
| 14 | UI 细节 | 队列可拖拽排序;暂停按钮为不规则椭圆泡泡(IDEA.md) |

## 网络预留范围(v1 边界)

**做**: 服务器 Profile 管理、HTTP/HTTPS 网关封装、健康检查与连接状态管理。
**不做**: 任何 api-enhanced 业务端点调用(搜索/歌词/在线播放等),全部留给下一阶段。

## 待真机/后续核实项

1. ✅ AVPlayer 格式与能力: 以用户指定的 [Media Kit简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/media-kit-intro) 为准,实现时核对(基础四格式 MP3/AAC/FLAC/WAV 已多方印证)
2. ✅ 明文 HTTP: 由系统配置决定(用户已核实);LAN 备选 Profile 先支持 http://,真机不通再按官方配置调整
3. ❓ api-enhanced 本地 clone 路径(后续补 `/health` 端点用,需用户提供)
4. ❓ AVPlayer 是否支持非沙箱持久化 URI(不影响 v1 方案,仅作未来"免复制"优化调研)

## API 清单

完整 v1 系统 API 清单(全部 @kit.* 命名空间 + 官方出处)见 `docs/design/v1-api-checklist.md`。

## 下一步

按 pipeline 建议: `grill-with-docs → to-prd → to-issues → implement-review`。
当前 grill-with-docs 阶段完成;是否进入 to-prd(产出 `docs/PRD-*.md` 并据此切垂直切片 issue)由用户决定。
