# 项目技术约束

> 修改必须申请用户同意

## 1. 鸿蒙版本锁定

- 目标设备系统: HarmonyOS 6.1
- API Version: **API 23**
- API Kit: 遇到功能需求时，**必须**从对应 Kit 导入
- 权限声明: 网络请求, 后台长时任务, 媒体权限, 通知
- 开发语言: ArkTS
- 所有系统能力必须基于Kit文档

### 禁止事项

- 禁止使用Android API
- 禁止假设不存在的API

## 2. 开发环境

| 组件           | 版本               | 路径                                           |
| :------------- | :----------------- | :--------------------------------------------- |
| DevEco Studio  | 6.1.0.830          | `D:\DevEco`                                    |
| HarmonyOS SDK  | 6.1.0.105 (API 23) | `D:\DevEco\sdk\default`                        |
| Node.js        | v18.20.1           | `D:\DevEco\tools\node`                         |
| ohpm           | 6.1.1.830          | `D:\DevEco\tools\ohpm\bin`                     |
| hvigor         | 6.23.5             | `D:\DevEco\tools\hvigor\bin`                   |
| hdc            | 3.2.0c             | `D:\DevEco\sdk\default\openharmony\toolchains` |
| JBR (内置 JDK) | OpenJDK 21.0.8     | `D:\DevEco\jbr`  优先使用 DevEco 内置 JBR      |
| JAVA_HOME      | JDK 22             | `D:\tool\Java\jdk-22`                          |



## 3. 项目架构

- 手机前端: ArkTS + ArkUI
- 数据: SQLite
- 网络:@kit.NetworkKit
- 媒体:@kit.AudioKit

## 4.项目目标

开发私人本地音乐播放器,核心功能:

- 本地存储音乐,本地音乐扫描,可离线播放
- 标准音乐播放器功能
- 设计接口,连接我的电脑,拉取JSON文件和音乐文件,配合api-enhanced项目使用HTTPS方式接收

## 5.测试流程

编译测试使用`hvigorw assembleHap` 

对于鸿蒙API系统能力需要用户真机运行测试

