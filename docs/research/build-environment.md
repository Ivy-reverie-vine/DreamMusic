# 本机命令行构建环境(踩坑记录)

> 状态: ✅ 已验证可编译。DevEco Studio 可用时优先用 IDE;命令行构建用本文件配方。

## 结论性配方(Windows)

前置:
- JAVA_HOME = `D:\tool\Java\jdk-22`
- DEVECO_SDK_HOME = `D:\DevEco\sdk`
- NODE_PATH = `<项目>\.hvigor\shim\node_modules`(已建目录联接 → DevEco 自带 hvigor 包)
- PATH 前置 `D:\DevEco\tools\node`

命令(必须 `--no-daemon`,且执行环境需允许子进程 spawn):

```powershell
node D:\DevEco\tools\hvigor\hvigor\bin\hvigor.js --no-daemon assembleHap
```

## 踩过的坑

1. **项目根没有 hvigorw 包装脚本** → 直接 node 调 `D:\DevEco\tools\hvigor\hvigor\bin\hvigor.js`(包装器依赖的用户缓存损坏且 ACL 拒删)
2. **包装器缓存损坏**(`C:\Users\77354\.hvigor\...` ENOENT) → 绕过包装器,用 `.hvigor\shim\node_modules\@ohos\{hvigor,hvigor-ohos-plugin}` 目录联接 + NODE_PATH 注入
3. **`spawn EPERM`** → 两种来源:①hvigor 守护进程 fork(用 `--no-daemon` 解决);②CompileResource 资源编译器 spawn 子进程(执行环境必须放开子进程管道限制,即本环境需提权执行)
4. **module.json5 schema**:`backgroundModes` 是 **ability 级**字段(与 skills 同级),不是 module 级;`requestPermissions` 才是 module 级。官方 schema 位于 `D:\DevEco\sdk\default\hms\toolchains\modulecheck\module.json`,字段枚举以它为准
5. **未签名警告**:无 signingConfigs 时 HAP 未签名,仅影响真机安装(需 DevEco 配签名),不影响编译校验
6. **Hypium 依赖**:`ohpm install --all` 安装到 `oh_modules/`(CLI 构建前必须装过,否则本地单测无法 import `@ohos/hypium`)

## 测试命令

```powershell
node D:\DevEco\tools\hvigor\hvigor\bin\hvigor.js --no-daemon test
```
