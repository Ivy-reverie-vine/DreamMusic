# 后端音乐获取方式扩展设计

## 1. 文档定位

本文为 NightDream 中间层增加音乐获取方式的设计方案，服务于后续接入 YouTube、YouTube Music、QQ 音乐、酷狗、酷我等来源。

本方案以当前源码为基准，不修改现有功能，不直接实现新来源。实现位置限定为：

```text
D:\DreamMusic\NightDream
```

DreamMusic HarmonyOS 客户端继续只访问 NightDream，不直接访问任何第三方音乐来源。

### 当前已确认的边界

- 当前主音乐接口是 NightDream 代理的 `api-enhanced`。
- 客户端通过 `/dreammusic/api/v1` 访问搜索、歌曲详情、歌词和普通播放地址。
- 普通播放继续使用 `/song/url/v1`。
- 服务端持久化下载继续使用 NightDream 的 `/auth/downloads` 任务接口，不与普通播放混用。
- NightDream 目前的 `server/proxy.js` 负责鉴权、白名单、Cookie 注入和上游转发。
- `server/downloadSource.js` 已经存在“原始下载地址 → 解锁地址 → 多平台匹配”的下载源兜底链，但它还是下载专用逻辑，不是全局音乐源调度器。
- 客户端不保存或传递第三方平台 Cookie；各音乐源的凭据、Cookie 和服务端配置只能留在 NightDream 或受控的后端服务中。

## 2. 目标与非目标

### 2.1 目标

1. 为 NightDream 增加统一的音乐源入口。
2. 让中间层能够按能力、优先级、可用性调度不同音乐源。
3. 保持现有 `api-enhanced` 行为和 HarmonyOS 客户端兼容。
4. 将搜索、详情、歌词、封面、普通播放地址和下载解析拆成可独立实现的能力。
5. 支持单一来源失败时的超时、降级、部分成功和恢复。
6. 让后续接入 YouTube 类来源时，不需要把来源逻辑写进客户端页面或播放器。

### 2.2 非目标

- 不在本阶段修改 HarmonyOS UI。
- 不把第三方平台的 Cookie 暴露给客户端。
- 不承诺所有来源都支持搜索、播放、歌词和下载的全部能力。
- 不通过绕过 DRM、访问控制或服务条款限制的方式获取音频。
- 不把“来源聚合”误认为“所有来源都能提供合法、稳定、可播放的 URL”。
- 不把服务端下载接口改造成客户端的普通播放接口。

## 3. GitHub 项目调研结论

本次调研只采用项目自身 GitHub 仓库、README、文档或 Wiki 作为主要依据。

| 项目 | 适合承担的职责 | 可复用价值 | 主要风险 | 结论 |
| --- | --- | --- | --- | --- |
| [Meting](https://github.com/metowolf/Meting) | 多平台搜索、歌曲/专辑/歌手/歌单/歌词/图片/URL 的统一调用层 | 已经抽象了多平台 provider 和相对统一的数据形状 | provider 仍受各平台接口、Cookie、地区和版权限制影响 | 可作为多平台适配器或参考，不直接替代 NightDream 网关 |
| [Meting-API](https://github.com/metowolf/Meting-API) | 将 Meting Core 包装为 HTTP API，提供 `server` 与 `type` 维度的路由 | 可参考缓存、认证、日志、跨平台路由方式 | 引入额外运行时和外部 API 依赖；其统一响应不能自动解决 DreamMusic 的 ID、鉴权和播放边界 | 适合做独立 POC 或隔离服务，不建议无审计直接嵌入核心 |
| [ytmusicapi](https://github.com/sigma67/ytmusicapi) | YouTube Music 搜索、歌曲元数据、专辑、歌手、歌单、歌词等 | 适合补充 YouTube Music 的搜索和元数据能力 | 非官方接口；Python 运行时；需要时会依赖浏览器请求头/Cookie，存在账号安全和维护成本 | 可作为独立 metadata/search 适配器；先不承担统一播放 |
| [ytmusicapi 浏览器认证文档](https://github.com/sigma67/ytmusicapi/blob/main/docs/source/setup/browser.rst) | 说明登录态请求头的使用方式 | 能帮助评估 YouTube Music 认证部署方式 | 浏览器请求头和 Cookie 是敏感凭据，不能进入客户端或普通日志 | 仅用于服务端部署评估，默认不启用用户 Cookie 透传 |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 多站点媒体信息提取和媒体地址解析 | 站点覆盖面广，支持搜索入口和多种 extractor 参数 | 站点变更频繁；YouTube 可能要求 PO Token；Cookie 使用不当可能导致账号封禁；合规边界复杂 | 可作为隔离的 resolver/worker，不应直接放进 Express 请求主链路 |
| [yt-dlp Extractors Wiki](https://github.com/yt-dlp/yt-dlp/wiki/Extractors) | 说明 YouTube extractor 的当前限制和运行注意事项 | 为 PO Token、Cookie、客户端类型等风险提供一手依据 | 可用格式和能力会随站点策略变化 | 接入前必须做可用性、合规和故障恢复验证 |
| [NeteaseCloudMusicApiEnhanced 类型定义](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/main/interface.d.ts) | 当前 api-enhanced 的调用契约参考 | 可确认 Cookie、代理、realIP、分页等请求配置边界 | 该接口只代表 NetEase 上游，不应成为所有来源的公共模型 | 保留为 `ApiEnhancedAdapter` 的上游契约，不向其他 adapter 泄漏 |

### 3.1 调研后的关键判断

Meting 更接近“多平台 API 抽象”，ytmusicapi 更接近“YouTube Music 元数据客户端”，yt-dlp 更接近“媒体提取器”。三者解决的问题不同，不能简单地选择一个作为所有能力的实现。

因此建议 NightDream 采用自己的来源适配器接口：

```text
NightDream 统一入口
    ├── ApiEnhancedAdapter       搜索/详情/歌词/普通播放
    ├── MetingAdapter             可选的多平台搜索或元数据
    ├── YouTubeMusicAdapter       可选的 YouTube Music 搜索/元数据
    └── YtDlpResolver              可隔离的媒体地址解析或下载解析
```

## 4. 总体架构

```text
HarmonyOS 客户端
        │
        │ 只访问 DreamMusic 公共 API
        ▼
NightDream 公共网关
  ├─ 鉴权、绑定状态、API Key、限流
  ├─ MusicSourceRegistry 来源注册表
  ├─ MusicOrchestrator 统一调度器
  ├─ Normalize / Deduplicate / Rank
  ├─ Cache / Timeout / Circuit Breaker
  └─ 统一错误与观测日志
        │
        ├── ApiEnhancedAdapter ── api-enhanced
        ├── MetingAdapter ─────── Meting 或独立 Meting-API
        ├── YouTubeMusicAdapter ─ ytmusicapi sidecar
        └── YtDlpResolver ─────── 隔离 worker / 子进程
```

### 4.1 核心原则

- 公共入口稳定，来源实现可替换。
- 来源选择只发生在 NightDream 服务端。
- 统一的是能力和领域模型，不是强行统一每个平台的原始 ID。
- 来源不可用时允许部分成功，但不应把来源内部异常原样返回给客户端。
- 搜索与媒体解析解耦：能搜到歌曲，不代表能获得播放 URL。
- 元数据来源与音频来源可以不同，但必须保留来源关联和可追踪性。
- api-enhanced 是当前默认来源，新增来源不能悄悄改变现有用户的播放结果。

## 5. 来源适配器设计

### 5.1 适配器职责

每个来源适配器只负责一个外部来源的协议、认证、字段转换和错误映射，不负责跨来源排序，也不负责客户端响应格式。

建议的内部接口如下，具体命名以 NightDream 现有 JavaScript 风格为准：

```js
export class MusicSourceAdapter {
  id = 'source-id';
  name = 'Source name';

  capabilities() {
    return {
      search: false,
      detail: false,
      lyric: false,
      cover: false,
      playback: false,
      downloadResolve: false,
    };
  }

  async search(query, context) {}
  async detail(refs, context) {}
  async lyric(ref, context) {}
  async cover(ref, context) {}
  async playback(ref, options, context) {}
  async resolveDownload(ref, options, context) {}
}
```

实际实现不应要求所有来源都实现所有方法。未实现能力必须通过 `capabilities()` 明确声明，由调度器决定是否降级或换源。

### 5.2 来源注册表

`MusicSourceRegistry` 负责：

- 注册启用的 adapter。
- 校验来源 ID 不重复。
- 按配置决定启用状态、优先级、能力和超时。
- 提供健康状态和熔断状态。
- 禁止请求代码直接 `import` 某一个平台实现。

建议配置形态：

```js
musicSources: {
  apiEnhanced: {
    enabled: true,
    priority: 100,
    timeoutMs: 5000,
    capabilities: ['search', 'detail', 'lyric', 'cover', 'playback'],
  },
  meting: {
    enabled: false,
    priority: 50,
    timeoutMs: 5000,
    capabilities: ['search', 'detail', 'lyric', 'cover'],
  },
  youtubeMusic: {
    enabled: false,
    priority: 30,
    timeoutMs: 8000,
    capabilities: ['search', 'detail', 'lyric'],
  },
  ytDlp: {
    enabled: false,
    priority: 20,
    timeoutMs: 15000,
    capabilities: ['playback', 'downloadResolve'],
  },
}
```

配置中的来源默认全部关闭，除 `apiEnhanced` 外必须经过单独 POC 和验收后再启用。

## 6. 统一调度流程

### 6.1 搜索流程

```text
客户端请求 /search
        │
        ▼
鉴权、限流、参数校验
        │
        ▼
MusicOrchestrator 选择支持 search 的来源
        │
        ├─ 按并发预算调用来源
        ├─ 单来源超时/失败隔离
        ├─ 统一字段
        ├─ 去重
        └─ 排序
        │
        ▼
保持客户端可消费的搜索响应
```

建议默认策略：

1. 先调用 api-enhanced，保证当前行为不变。
2. 新来源只在开启聚合搜索时参与，不因一个新来源失败而阻塞 api-enhanced。
3. 每个来源设置独立超时、并发数、限流和熔断。
4. 仅返回成功来源的结果；所有来源都失败时才返回统一的上游不可用错误。
5. 结果必须带内部来源信息，便于后续详情、歌词和播放地址继续沿用正确来源。

### 6.2 去重与排序

来源结果不能简单按返回顺序拼接。建议按以下信息计算匹配指纹：

```text
normalizedTitle
+ normalizedArtists
+ duration bucket
+ normalizedAlbum
```

其中标题、歌手和专辑需要进行大小写、空白、常见标点和版本标记归一化；时长使用容差，不要求各平台完全一致。

排序因素建议为：

1. 标题和歌手的精确匹配。
2. 来源优先级。
3. 是否具备当前请求需要的能力。
4. 音频可用性和 URL 解析成功率。
5. 结果来源的历史健康度。
6. 来源返回的相关性分数。

排序规则必须是可测试的纯函数，不能把排序逻辑散落在各个 adapter 中。

### 6.3 播放地址流程

搜索、详情和播放必须使用同一个“歌曲引用”，不能只把跨平台歌曲都强行转换成一个数字 ID。

建议内部引用：

```json
{
  "source": "api-enhanced",
  "sourceId": "123456",
  "kind": "song"
}
```

对新来源则可能是：

```json
{
  "source": "youtube-music",
  "sourceId": "youtube-video-or-track-id",
  "kind": "song"
}
```

当前客户端已经依赖 api-enhanced 的歌曲结构和数字 `id`。因此不能直接把新来源的字符串 ID 填入当前 `id` 字段。建议分两个阶段处理：

- 第一阶段：保留当前客户端公共响应和数字 ID，只在 NightDream 内部建立 `ApiEnhancedAdapter` 与调度器，为后续扩展打基础。
- 第二阶段：当客户端准备支持多来源后，引入版本化的 `source`、`sourceId` 或不透明 `mediaRef` 字段，并同步修改详情、歌词、封面和播放请求。

在客户端完成第二阶段之前，新来源可以先用于服务端 POC、搜索实验或下载解析实验，但不能假设当前播放器能够直接播放它。

## 7. 公共 API 兼容策略

### 7.1 当前接口保持不变

以下接口继续由 NightDream 统一承接：

- `/search`
- `/song/detail`
- `/song/url/v1`
- `/lyric/new`
- 现有个人歌单、喜欢列表和用户相关接口

`api-enhanced` 默认调用的返回形状不得因新增 adapter 而改变。

### 7.2 新来源字段建议

未来公共响应可增加可选字段，不立即删除已有字段：

```json
{
  "id": 123456,
  "name": "Song",
  "ar": [{"id": 1, "name": "Artist"}],
  "al": {"id": 2, "name": "Album", "picUrl": "..."},
  "dt": 240000,
  "dreamMusic": {
    "source": "api-enhanced",
    "sourceId": "123456",
    "capabilities": {
      "detail": true,
      "lyric": true,
      "playback": true,
      "downloadResolve": false
    }
  }
}
```

注意：字段名和是否采用嵌套结构需要在客户端改造前最终确认。若需要支持非数字 ID，建议使用新版本 API 或 `mediaRef`，不要破坏当前数值型 `id` 的语义。

### 7.3 错误契约

适配器内部统一映射为以下错误类别：

- `SOURCE_TIMEOUT`
- `SOURCE_RATE_LIMIT`
- `SOURCE_AUTH_REQUIRED`
- `SOURCE_UNAVAILABLE`
- `NO_MATCH`
- `NO_PLAYBACK`
- `NO_LYRIC`
- `UPSTREAM_INVALID_RESPONSE`

客户端继续接收当前网关的 HTTP 和业务错误边界，例如鉴权失败、限流和上游不可用。来源名称、请求 URL、Cookie、Token 和完整上游响应不得出现在客户端错误中，也不得写入普通日志。

## 8. YouTube 类来源的落地建议

### 8.1 推荐拆成两个能力

YouTube Music 的元数据搜索和实际媒体地址解析应该拆开：

```text
YouTubeMusicAdapter
  ├─ search
  ├─ detail
  ├─ lyric（若可用）
  └─ playlist metadata（后续评估）

YtDlpResolver
  ├─ resolve playback URL
  └─ resolve download URL（需单独审批）
```

`ytmusicapi` 是 Python 项目，若 NightDream 继续保持 Node.js 主服务，不建议在每个 HTTP 请求中临时启动 Python 进程。可选方案：

1. 独立 Python sidecar，通过内部 HTTP 或队列通信。
2. 独立 worker，负责搜索/元数据并写入短期缓存。
3. 仅在 POC 阶段使用本地命令或脚本，验收后再决定正式部署方式。

`yt-dlp` 同样不建议直接成为 Express 主线程中的长期同步依赖。媒体解析应放在受控 worker 或隔离子服务中，并设置短超时、并发上限、版本更新和故障降级。

### 8.2 YouTube 运行风险

根据 yt-dlp 的官方 Extractors Wiki，YouTube 的部分能力可能受到 PO Token、客户端类型和站点策略影响；账号 Cookie 使用不当还可能触发封禁风险。因此：

- 默认不要求用户提供 YouTube Cookie。
- 不在客户端保存、上传或展示第三方 Cookie。
- 不把 Cookie 写入日志、错误、缓存或任务详情。
- 不把“能搜索到”当成“可播放”。
- 不把失败归因于客户端；服务端记录来源、版本和可脱敏的错误分类。
- 接入前必须确认内容使用权、服务条款和部署地区的合规要求。
- 不设计绕过 DRM、访问控制或平台限制的流程。

## 9. Meting 的使用边界

Meting 可以显著减少多平台 adapter 的初始工作量，但不应让它成为 DreamMusic 的公共领域模型。原因是：

- Meting 的来源 ID 和字段仍然具有平台语义。
- 不同平台的播放、歌词、封面和登录要求并不一致。
- Meting-API 自身的缓存、认证和部署策略不等于 DreamMusic 的用户鉴权、API Key 和下载计费策略。
- 第三方聚合层故障时，NightDream 仍需能够识别来源失败并降级。

推荐把 Meting 放在隔离边界内：

```text
NightDream -> MetingAdapter -> Meting Core 或受控 Meting-API
```

NightDream 只接收经过校验的领域结果，不直接依赖 Meting 的公共 HTTP 响应结构。若后续发现 Meting 的运行时、许可证、稳定性或维护成本不可接受，应能只替换 `MetingAdapter`。

## 10. 建议的 NightDream 模块拆分

下面是建议结构，不要求一次性全部创建：

```text
server/
  music/
    sources/
      SourceRegistry.js
      ApiEnhancedAdapter.js
      MetingAdapter.js
      YouTubeMusicAdapter.js
      YtDlpResolver.js
    MusicOrchestrator.js
    normalize.js
    deduplicate.js
    rank.js
    errors.js
    cache.js
  proxy.js
  downloadSource.js
```

建议先把现有 `proxy.js` 中与 api-enhanced 音乐请求相关的逻辑抽成 `ApiEnhancedAdapter`，再由 `MusicOrchestrator` 调用。`downloadSource.js` 暂时保留原有下载责任；只有在多来源播放和下载的歌曲引用模型确定后，才决定是否将下载解析合并到统一 source registry。

## 11. 缓存、限流与故障隔离

### 11.1 缓存

- 搜索缓存按 `source + normalizedQuery + type + limit + offset` 分区。
- 继续遵守当前客户端和 NightDream 已有的短期缓存策略。
- 元数据可以使用比搜索更长的 TTL，但要能在账号切换、绑定变化和来源切换时失效。
- 播放 URL 只按其有效期做短缓存，不能长期保存过期地址。
- 失败结果只做很短的负缓存，避免临时故障被放大。
- 缓存值不得包含不必要的 Cookie、Token 或完整上游请求头。

### 11.2 限流

限流至少分三层：

1. NightDream 用户/IP 层限流。
2. 单来源并发和请求速率限制。
3. 媒体解析 worker 的任务并发限制。

来源返回 429 时，调度器应降低该来源的短期权重并触发熔断观察，不应立刻无限重试。

### 11.3 熔断

每个来源独立维护健康状态：

```text
closed  -> 正常调用
open    -> 暂停调用，快速降级
half-open -> 少量探测请求
```

熔断不能影响其他来源，也不能让 api-enhanced 的现有路径一起不可用。

## 12. 安全与合规

- 第三方凭据由 NightDream 服务端配置管理，不进入 ArkTS 客户端。
- 不接受客户端传入的任意上游 Cookie、代理地址或 extractor 参数。
- 只允许注册表中的来源 ID，拒绝用户把 URL 当来源参数传入。
- 日志脱敏：来源 ID 可以记录，Cookie、Token、签名、完整 URL 查询参数必须脱敏。
- 对外返回的媒体 URL 只在必要时返回，并尽量使用短有效期地址。
- 下载、缓存和转发必须遵守各来源服务条款、版权授权和部署地区法律要求。
- 新来源不能复用现有 NetEase Cookie 注入逻辑；每个 adapter 自己拥有认证上下文。

## 13. 测试方案

### 13.1 适配器契约测试

每个 adapter 都使用同一组契约测试，至少覆盖：

- 正常搜索和空结果。
- 字段缺失、类型异常和上游错误 JSON。
- 超时、429、认证失效和网络断开。
- 能力未实现时返回明确错误。
- 不泄漏 Cookie、Token 和上游请求头。

### 13.2 调度器测试

- api-enhanced 正常时保持现有返回。
- 一个来源超时时，其他来源仍能返回。
- 所有来源失败时返回统一上游错误。
- 相同歌曲跨来源去重。
- 不同版本、现场版、翻唱版不能被过度去重。
- 排序规则稳定且可重复。
- 熔断打开时不再调用对应来源。
- 缓存命中、过期和来源切换行为正确。

### 13.3 兼容测试

- 现有 HarmonyOS 搜索模型仍能解析 api-enhanced 的结果。
- `/song/url/v1` 的当前数字 ID 路径保持不变。
- 普通播放不会意外调用 `/auth/downloads`。
- `/auth/downloads` 的计费、失败退款和任务状态不被新搜索源改动。
- 绑定、API Key、Cookie 注入和 301 失效处理保持现状。

## 14. 分阶段实施顺序

### 阶段 0：契约和 POC

- 确认第一种新增来源。
- 确认是先做搜索/元数据，还是同时要求播放。
- 定义内部 `source + sourceId` 引用。
- 用假 adapter 验证调度、去重、排序、超时和部分失败。

### 阶段 1：抽取现有 api-enhanced

- 在不改变公共响应的情况下，创建 `ApiEnhancedAdapter`。
- 将 `proxy.js` 中的音乐路由调用迁移到 `MusicOrchestrator`。
- 保留鉴权、绑定、Cookie 注入和现有错误边界。
- 添加兼容回归测试。

### 阶段 2：接入第二个元数据来源

- 优先选择 Meting 或 YouTube Music 的搜索/元数据能力。
- 默认关闭生产流量，只在测试账号或内部开关启用。
- 验证跨来源去重、排序和来源引用。
- 暂不宣称新来源可播放。

### 阶段 3：接入媒体解析

- 以隔离 worker/sidecar 方式评估 yt-dlp 或其他 resolver。
- 验证 URL 有效期、并发、失败率、版本更新和合规性。
- 明确普通播放和服务端下载是否分别支持该来源。
- 只有在公共歌曲引用和客户端契约稳定后，才接入客户端播放。

### 阶段 4：客户端多来源契约

- 客户端显示来源标签或来源无感，由产品决定。
- 客户端模型支持 `sourceId/mediaRef`。
- 详情、歌词、封面、播放和下载都使用同一歌曲引用。
- 更新 API 文档、测试数据和真机验收用例。

## 15. 暂需确认的问题

以下问题会改变实现范围，建议在进入编码前确认：

1. 第一种新增来源优先做 YouTube/YouTube Music，还是优先通过 Meting 接入 QQ、酷狗、酷我等多平台？
2. 新来源第一阶段只需要搜索和元数据，还是必须同时支持普通播放？
3. 来源选择是否完全由 NightDream 自动调度，还是未来允许用户在客户端选择来源？
4. YouTube 来源是否允许配置服务端专用账号/认证信息？默认方案是不接收普通用户 Cookie。
5. 新来源是否需要支持 `/auth/downloads`，还是先限定为普通播放？

在这些问题确认前，建议只实施阶段 0 和阶段 1，不将新来源暴露给生产客户端。

## 16. 最终建议

NightDream 应新增“来源注册表 + 能力适配器 + 统一调度器”三层，而不是继续在 `proxy.js` 或 `downloadSource.js` 中追加平台分支。

推荐落地顺序为：

```text
抽取 api-enhanced
    → 用假来源验证统一调度
    → 接入第二个元数据来源
    → 独立验证媒体解析
    → 最后升级客户端歌曲引用和播放契约
```

当前最稳妥的默认策略是：api-enhanced 继续作为默认来源；Meting 或 ytmusicapi 先作为搜索/元数据实验；yt-dlp 作为隔离的媒体解析候选；任何来源都不能绕过 NightDream 的鉴权、限流、日志脱敏和普通播放/服务端下载边界。
