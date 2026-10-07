# iOS 适配验证记录

日期：2026-10-07。上游：funkeyyou/zaimanhua，提交 `108c1e9`。
构建工具：Flutter 3.47.2、Dart 3.13.2。

## 已完成

- `flutter pub get --enforce-lockfile`：成功，使用上游锁定依赖。
- `flutter analyze --no-pub --no-fatal-infos`：通过；0 error、0 warning，13 条上游 info 提示。
- `flutter test --no-pub --reporter expanded`：225 项通过，5 项 Windows 专用测试按平台跳过。
- 新增的分类首次加载测试覆盖状态、地区、隐藏题材，验证首个请求等候筛选信息并使用正确参数。
- 新增的分享测试经过真实 share_plus 方法通道参数转换，检查链接和 CBZ 文件在 iPad 竖屏、横屏、分屏下的弹窗锚点。
- 新增的更新测试验证混合平台发布附件中选择 `.ipa`。
- 在线只读检查：分类接口 `errno=0`、37 项；完结筛选返回 5 项且状态均为“已完结”；日本与爱情组合筛选返回 5 项。
- iOS plist、工作流 YAML、Python 构建脚本语法检查通过。
- 图标文件存在且像素尺寸符合 Asset Catalog 声明。

## macOS / Xcode 验证已完成

[GitHub Actions 构建 #1](https://github.com/LxyveeX/ZAI-X-iOS/actions/runs/37649366765)
全部成功，实际构建提交为 `a0e3a0892776bb5eaf8bce0e3915f9e6ed686ffe`。

- macOS 上的静态分析与测试通过：225 项通过，5 项 Windows 专用测试跳过。
- Xcode 真机 Release 和模拟器 Debug 编译、CocoaPods 原生链接通过。
- IPA 为 27,599,391 字节，版本 2.4.1 (24001)，Bundle ID 为 `com.lxyveex.zaix`。
- IPA 结构、ZIP 完整性与 SHA-256 检查通过；支持 iPhone 与 iPad，最低系统版本 15.0。
- 对下载到本地的 IPA 再次检查 15 个 Mach-O 原生文件，全部为 iOS arm64，最低系统版本均不高于 15.0。
- iPad Pro 13-inch (M5) 模拟器成功安装、启动，进程在 15 秒后仍存活。
- 已人工查看启动截图：显示再漫画首页、网络封面和首次启动免责声明；未代用户接受声明。

IPA 的 SHA-256：

```text
9403844b37b5a64af4068568de618e807f442d089efc3618524133e19adf381c
```

## 待实际设备验证

- 使用用户证书签名安装，在 iPadOS 16.7 启动。
- 登录、书架同步、连续翻页、双页阅读、下载、分享和相册权限。
- 订阅通知与系统后台刷新。

模拟器验证覆盖首次启动；iPadOS 16.7 真机上的签名、账号操作和完整阅读流程仍需实机确认。
