# 账户凭证使用 HarmonyOS AssetStoreKit 保护存储

状态：已接受（2026-08-18）

DreamMusic 的 `dm_session` 与 `dm_api_key` 使用 HarmonyOS API 23 的 `@kit.AssetStoreKit` 保存，访问级别为 `DEVICE_FIRST_UNLOCKED`，不设置跨卸载持久化；普通 preferences 只保留非敏感账户状态。为保持 ArkUI `build()` 的同步读取边界，安全存储是唯一真源，应用启动时异步加载到内存缓存，登录、登出和 API Key 刷新时同步更新缓存并异步写入/删除安全资产。

