# 再漫画X iOS 适配版

基于 [funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua) 的 v2.4.0 功能代码，
上游基准提交为 `108c1e9`。iOS 适配版版本号为 **2.4.1 (24001)**。
保留原项目及其贡献者署名，源码继续使用仓库中的 GPL-3.0 许可证。

## 安装

面向 iPhone、iPad，最低系统版本设为 iOS / iPadOS 15.0，包含 iPadOS 16.7。
构建产物 `ZAI-X-iOS-2.4.1-unsigned.ipa` 需要先使用自己的证书签名，再安装。

1. 在本仓库的 [Releases](https://github.com/LxyveeX/ZAI-X-iOS/releases) 选择需要的预览版，从 Assets 下载 `.ipa`。
2. 把 `.ipa` 导入已有的 iOS 签名工具。
3. 选择自己的有效证书与描述文件，签名后安装。
4. 打开应用，登录再漫画账号；分类、订阅及阅读权限由服务端和账号状态决定。

应用标识为 `com.lxyveex.zaix`，可与旧版 ZAI-X 并存。
首次使用需要重新登录，本地下载、设置及未同步记录不会自动从旧版迁移。
账号中的订阅和已同步阅读进度会在登录后重新获取。

## 此次适配

- 保留上游分类、状态筛选、地区与题材组合筛选、专题、下载及双页阅读功能。
- 修复分类页首次加载的顺序问题：先确认入口标签属于状态、地区还是题材，再请求列表。
- 更新 iOS 工程至 15.0 最低版本，移除原作者开发团队及已过期的原生依赖锁文件。
- 采用 Flutter UIScene 生命周期，在引擎初始化后注册插件。
- 完成订阅通知原生任务注册；iOS 后台刷新由系统调度，设置页明确说明。
- 保存图片只申请“添加照片”权限；检查真实保存结果，并处理图片链接中的查询参数。
- 为链接分享、CBZ 文件导出提供 iPad 弹窗锚点，适配横竖屏和分屏。
- 使用独立的 iOS 更新源，避免跳转到上游 Android / Windows 安装包。
- 统一中英文系统环境下的应用名称。
- fork 中默认不运行上游每日索引抓取；应用继续读取上游索引。

未配置 AI 服务时，上游代码会隐藏 AI 搜索及 AI 答题入口；普通搜索与阅读功能独立运行。
音量键翻页沿用上游的 Android 实现，在 iOS 使用屏幕触控或键盘翻页。

## 构建与验证

使用 Flutter **3.47.2 / Dart 3.13.2**。保留 CocoaPods 集成以明确配置照片权限宏。
macOS 环境需安装 Xcode、CocoaPods 和一个可用的 iPad Simulator。

GitHub Actions 中运行 **Build iOS IPA**。该流程依次执行锁定依赖恢复、静态分析、
Flutter 测试、真机 Release 编译、IPA 结构与 arm64 检查、iPad 模拟器启动检查。
产物附 SHA-256、构建提交信息和模拟器截图。

构建成功后，**Publish iOS Release** 自动将同一份 IPA 及验证附件存入独立的
GitHub 预览版 Release。标签包含版本号、构建序号、运行 ID 与重跑次数，旧版本保留。
发布前核对来源提交、IPA SHA-256 与已上传附件；重复发布同一构建不会覆盖已有文件。
尚未完成真机测试的自动构建始终标为预览版，在 Releases 手动下载。

补发已有构建：在 Actions 选择 **Publish iOS Release → Run workflow**，填入
**Build iOS IPA** 页面 URL 最后的运行 ID；留空则选最近一次成功构建。
此操作复用仍未过期的 Actions 附件，无需重新编译。Actions 临时附件保留 30 天，
Release 附件不会随该临时附件到期而删除。

本地构建命令（将最后一项替换为自己的 GitHub 仓库）：

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test
flutter build ios --release --no-codesign --dart-define=ZAI_IOS_REPOSITORY=OWNER/REPO
python3 scripts/ios/package_ipa.py
```

模拟器启动检查只覆盖启动与进程存活。证书签名、账号登录、连续阅读、照片权限、
通知及后台行为需要在实际 iPhone / iPad 上验证。

## 仓库选择依据（2026-10-07）

| 来源 | 代码情况 | 结论 |
| --- | --- | --- |
| xiaoyaocz / zaimanhua | 此分支最新提交为 2025-03-18，SDK 与依赖较旧 | 作为原始项目追溯 |
| AliceRabbit / flutter_zai | 最新提交为 2026-07-28，Flutter 3.44.8，已配置 iOS 调试 CI；分类状态仍硬编码为 0，专题使用旧路径 | 构建整理较完整，功能修复覆盖较少 |
| funkeyyou / zaimanhua | 最新提交为 2026-10-03，v2.4.0 于 2026-10-02 发布；分类筛选、专题及平板阅读修复更多 | 选为 iOS 适配基础 |

以上是源码与工作流的核对结果；存在 iOS CI 配置本身不等于已发布可安装的 IPA。
