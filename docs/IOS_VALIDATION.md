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

## 待在 macOS 构建机完成

- Xcode 编译、CocoaPods 原生链接。
- Release 真机 arm64 文件及 IPA 结构检查。
- iPad 模拟器启动与截图检查。

## 待实际设备验证

- 使用用户证书签名安装，在 iPadOS 16.7 启动。
- 登录、书架同步、连续翻页、双页阅读、下载、分享和相册权限。
- 订阅通知与系统后台刷新。

Linux 上的 Dart / Flutter 测试不覆盖原生插件的 iOS 实际行为。
