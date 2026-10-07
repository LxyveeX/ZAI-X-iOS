# ZAI-X iOS · 个人自用适配

基于 [funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua) 的再漫画X，为个人 iPhone / iPad 使用补充平台适配与 IPA 构建。仓库保留公开 fork，按个人需要更新。

[下载 IPA](https://github.com/LxyveeX/ZAI-X-iOS/releases) · [安装说明](docs/IOS.md) · [验证记录](docs/IOS_VALIDATION.md) · [繁體中文](README.zh-TW.md) · [English](README.en.md)

> **当前为预览版，尚未完成真机测试。** 2.4.1 已通过 225 项测试、iOS Release 编译和 iPad 模拟器首次启动检查；iPadOS 16.7 实机上的签名安装、登录与完整阅读流程待验证。

## 下载与安装

1. 打开本仓库的 [Releases](https://github.com/LxyveeX/ZAI-X-iOS/releases)，选择需要的构建。
2. 在 **Assets** 中下载 `ZAI-X-iOS-版本号-unsigned.ipa`。
3. 导入自己的签名工具，使用有效证书与描述文件签名后安装。

支持 iPhone 与 iPad，最低系统要求为 **iOS / iPadOS 15.0**。应用标识为 `com.lxyveex.zaix`，可与旧版并存。首次使用需要重新登录；旧版的本地下载、设置和未同步记录不会自动迁移。

每次 **Build iOS IPA** 构建成功后，都会自动在 Releases 留存一份独立的预览版，附 IPA、SHA-256 校验值、构建信息和 iPad 启动截图。不同构建分别保留，重复执行同一次发布会复用对应版本。

预览版在 Releases 手动下载；当前 App 的“检查更新”只读取正式版。

## 这份适配做了什么

- 沿用上游的分类、专题、书架、下载及双页阅读功能，补充分类首次加载顺序修复。
- 更新 iOS 原生工程和插件注册，适配 iPad 分享弹窗、照片保存权限及订阅后台任务。
- 使用独立的 iOS 更新来源，生成供个人证书签名的 IPA。

普通搜索与阅读沿用上游实现。上游的私有 AI 服务配置未包含在本仓库构建中，相关入口保持隐藏。iOS 后台提醒由系统调度。

具体变化与构建方法见 [iOS 说明](docs/IOS.md)；已完成和待完成的验证见 [验证记录](docs/IOS_VALIDATION.md)。

## 来源与许可

- iOS 适配基础：[funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua)，上游 v2.4.0。
- 再漫画接口迁移：[Fusn126/ZAI_X](https://github.com/Fusn126/ZAI_X)。
- 原始项目：[xiaoyaocz/flutter_dmzj](https://github.com/xiaoyaocz/flutter_dmzj/tree/zaimanhua)。
- 保留原作者及贡献者署名，源码沿用 [GPL-3.0 许可证](LICENSE)。

完整上游介绍及 Android / Windows 版本见 [上游仓库](https://github.com/funkeyyou/zaimanhua)。本项目为社区第三方客户端；作品内容与图片的版权归相应权利人所有。
