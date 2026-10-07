import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/app/single_instance.dart';
import 'package:zai_x/app/utils.dart';
import 'package:zai_x/models/version_model.dart';
import 'package:zai_x/requests/common/github_proxy.dart';
import 'package:zai_x/services/resumable_download.dart';
import 'package:zai_x/services/windows_self_update.dart';

/// App 内更新
///
/// Android：下载 APK 后直接唤起系统安装器；
/// Windows：下载 zip、核对 SHA-256 后解压，App 结束时由更新脚本覆盖安装资料夹
/// 并重新开启（见 [WindowsSelfUpdate]）。开发版、安装位置不能写入或缺少校验
/// 资讯时，退回下载 zip 后在档案总管里选取。
class AppUpdateService {
  static final RxBool downloading = false.obs;

  /// 0~1，-1 表示还不知道总大小
  static final RxDouble progress = (-1.0).obs;

  /// 进度框目前的步骤（简体原文，显示时再转换）
  static final RxString stage = "正在下载新版本".obs;

  /// 只有下载阶段可以取消
  static final RxBool cancellable = true.obs;
  static CancelToken? _cancelToken;

  /// 只有这两个平台会出正式包
  static bool get supported => Platform.isAndroid || Platform.isWindows;

  static Future<void> download(VersionModel version) async {
    if (downloading.value) {
      return;
    }
    if (version.downloadUrl.isEmpty) {
      SmartDialog.showToast("没有可下载的安装档".i18n);
      return;
    }
    if (!supported) {
      await launchUrlString(
        Platform.isIOS
            ? version.downloadUrl
            : githubProxyUrl(version.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    if (Platform.isAndroid && !await _ensureInstallPermission()) {
      return;
    }
    if (Platform.isWindows) {
      var updater = WindowsSelfUpdate.forCurrentApp();
      if (await _canSelfUpdate(updater, version)) {
        await _selfUpdate(updater, version);
        return;
      }
    }

    _beginDownload();
    try {
      var file = await _targetFile(version);
      if (await file.exists()) {
        await file.delete();
      }
      await file.parent.create(recursive: true);
      await _downloadUpdate(version, file);
      SmartDialog.dismiss();
      await _open(file);
    } on DioException catch (e) {
      SmartDialog.dismiss();
      if (CancelToken.isCancel(e)) {
        return;
      }
      await _fallbackToBrowser(version, e);
    } on UpdateIntegrityException catch (e) {
      SmartDialog.dismiss();
      Log.logPrint(e);
      SmartDialog.showToast("更新档校验失败，请重新下载".i18n);
    } catch (e) {
      SmartDialog.dismiss();
      Log.logPrint(e);
      SmartDialog.showToast("更新失败：${e.toString()}".i18n);
    } finally {
      _endDownload();
    }
  }

  /// Windows 能否直接覆盖安装
  static Future<bool> _canSelfUpdate(
    WindowsSelfUpdate updater,
    VersionModel version,
  ) async {
    // 开发版的执行档在 build 资料夹里，不做覆盖
    if (!kReleaseMode) {
      return false;
    }
    if (version.sha256.isEmpty ||
        !version.downloadUrl.toLowerCase().endsWith(".zip")) {
      return false;
    }
    var exe = p.basename(Platform.resolvedExecutable).toLowerCase();
    if (exe != WindowsSelfUpdate.exeName.toLowerCase() ||
        !updater.isInstalledBundle) {
      return false;
    }
    if (await updater.canWriteInstallDir()) {
      return true;
    }
    SmartDialog.showToast("安装位置无法写入，改为下载压缩档".i18n);
    return false;
  }

  /// Windows：下载、校验、解压，交给更新脚本后结束 App
  static Future<void> _selfUpdate(
    WindowsSelfUpdate updater,
    VersionModel version,
  ) async {
    _beginDownload();
    var launched = false;
    try {
      await updater.resetWorkDir();
      try {
        await _downloadUpdate(version, updater.zipFile);
      } on UpdateIntegrityException {
        rethrow;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          SmartDialog.dismiss();
          return;
        }
        throw _DownloadFailed(e);
      } catch (e) {
        throw _DownloadFailed(e);
      }
      cancellable.value = false;
      progress.value = -1;
      stage.value = "正在解压更新档";
      await updater.extract();
      stage.value = "即将重新启动以完成更新";
      await updater.launch(appPid: pid, version: version.version);
      launched = true;
    } on _DownloadFailed catch (e) {
      SmartDialog.dismiss();
      await _fallbackToBrowser(version, e.error);
    } on UpdateIntegrityException catch (e) {
      SmartDialog.dismiss();
      Log.logPrint(e);
      SmartDialog.showToast("更新档校验失败，请重新下载".i18n);
    } catch (e) {
      SmartDialog.dismiss();
      Log.logPrint(e);
      SmartDialog.showToast("更新失败：${e.toString()}".i18n);
    } finally {
      if (!launched) {
        _endDownload();
      }
    }
    if (!launched) {
      return;
    }
    // 留一点时间显示「即将重新启动」，并把 Hive 还没写完的资料写回磁碟
    await Future.delayed(const Duration(milliseconds: 800));
    try {
      await Hive.close().timeout(const Duration(seconds: 3));
    } catch (e) {
      Log.logPrint(e);
    }
    await quitApp();
  }

  /// Windows：显示上次覆盖更新的结果（启动时呼叫）
  static Future<void> showWindowsUpdateOutcome() async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      var outcome = await WindowsSelfUpdate.forCurrentApp().takeOutcome(
        currentVersion: Utils.packageInfo.version,
      );
      if (outcome == null) {
        return;
      }
      if (outcome.ok) {
        SmartDialog.showToast("${"已更新到".i18n} v${outcome.version}");
      } else {
        Log.logPrint("Windows update failed: ${outcome.detail}");
        SmartDialog.showToast("更新没有完成，已保留原来的版本".i18n);
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  static void cancel() {
    _cancelToken?.cancel();
    SmartDialog.dismiss();
  }

  static void _beginDownload() {
    downloading.value = true;
    progress.value = -1;
    stage.value = "正在下载新版本";
    cancellable.value = true;
    _cancelToken = CancelToken();
    _showProgress();
  }

  static void _endDownload() {
    downloading.value = false;
    cancellable.value = false;
    _cancelToken = null;
  }

  static void _onReceiveProgress(int received, int total) {
    // 重新连上后把「正在重新连接」换回下载中
    if (cancellable.value) {
      stage.value = "正在下载新版本";
    }
    progress.value = total > 0 ? received / total : -1;
  }

  static Future<void> _downloadUpdate(VersionModel version, File file) async {
    final sources = githubSources(version.downloadUrl);
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));
    try {
      for (var i = 0; i < sources.length; i++) {
        cancellable.value = true;
        stage.value = "正在下载新版本";
        try {
          await downloadWithResume(
            dio,
            sources[i],
            file,
            cancelToken: _cancelToken,
            expectedSize: version.size,
            // 代理连续失败两次就接回原站；已收到的部分仍可续传。
            maxAttempts: i == 0 && sources.length > 1 ? 2 : 6,
            onProgress: _onReceiveProgress,
            onRetry: (_) => stage.value = "网络不稳，正在重新连接",
          );
          if (version.sha256.isNotEmpty) {
            cancellable.value = false;
            progress.value = -1;
            stage.value = "正在校验更新档";
            await WindowsSelfUpdate.verifyDownload(
              file,
              sha256Hex: version.sha256,
              size: version.size,
            );
          }
          return;
        } catch (e) {
          if (_cancelToken?.isCancelled == true ||
              e is DioException && CancelToken.isCancel(e)) {
            rethrow;
          }
          if (e is UpdateIntegrityException && await file.exists()) {
            // 校验失败的档案不能接着用，从下一个来源重新下载。
            await file.delete();
          }
          if (i == sources.length - 1) rethrow;
          Log.logPrint(e);
        }
      }
    } finally {
      dio.close();
    }
  }

  static Future<void> _fallbackToBrowser(
    VersionModel version,
    Object error,
  ) async {
    Log.logPrint(error);
    SmartDialog.showToast("下载失败，改用浏览器下载".i18n);
    await launchUrlString(
      githubProxyUrl(version.downloadUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  /// 下载位置：Android 用 App 专属外部目录（安装器读得到），Windows 用下载资料夹
  static Future<File> _targetFile(VersionModel version) async {
    Directory? dir;
    if (Platform.isWindows) {
      dir = await getDownloadsDirectory();
    } else {
      dir = await getExternalStorageDirectory();
    }
    dir ??= await getApplicationSupportDirectory();
    var name = Platform.isAndroid
        ? "ZAI-X-${version.version}.apk"
        : "ZAI-X-${version.version}-windows-x64.zip";
    return File(p.join(dir.path, name));
  }

  static Future<void> _open(File file) async {
    if (Platform.isAndroid) {
      var result = await OpenFilex.open(
        file.path,
        type: "application/vnd.android.package-archive",
      );
      if (result.type != ResultType.done) {
        SmartDialog.showToast(result.message);
      }
      return;
    }
    try {
      await Process.run("explorer.exe", ["/select,${file.path}"]);
    } catch (e) {
      Log.logPrint(e);
    }
    SmartDialog.showToast("${"已下载到".i18n}：${file.path}");
  }

  /// Android 8 起要先允许「安装未知来源应用」
  static Future<bool> _ensureInstallPermission() async {
    try {
      var status = await Permission.requestInstallPackages.status;
      if (status.isGranted) {
        return true;
      }
      status = await Permission.requestInstallPackages.request();
      if (status.isGranted) {
        return true;
      }
      SmartDialog.showToast("需要允许安装未知来源应用才能直接更新".i18n);
      return false;
    } catch (e) {
      Log.logPrint(e);
      // 权限查询失败时不挡住流程，交给系统安装器自己提示
      return true;
    }
  }

  static void _showProgress() {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (_) => const UpdateProgressCard(),
    );
  }
}

/// 下载步骤失败（包含续传重试用完）
class _DownloadFailed implements Exception {
  const _DownloadFailed(this.error);
  final Object error;

  @override
  String toString() => error.toString();
}

/// 下载更新的进度框
///
/// SmartDialog 用一层透明 Material 包住内容，那层的预设文字是深色，
/// 深色主题下标题会和卡片融在一起，所以标题直接取 App 主题的样式。
class UpdateProgressCard extends StatelessWidget {
  const UpdateProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Get.theme;
    return Container(
      width: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(
            () => Text(
              AppUpdateService.stage.value.i18n,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 16),
          Obx(
            () => LinearProgressIndicator(
              value: AppUpdateService.progress.value < 0
                  ? null
                  : AppUpdateService.progress.value,
            ),
          ),
          const SizedBox(height: 8),
          Obx(
            () => Text(
              AppUpdateService.progress.value >= 0
                  ? "${(AppUpdateService.progress.value * 100).toStringAsFixed(0)}%"
                  : (AppUpdateService.cancellable.value ? "连接中..." : "请稍候...")
                        .i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Obx(
            () => AppUpdateService.cancellable.value
                ? TextButton(
                    onPressed: AppUpdateService.cancel,
                    child: Text("取消".i18n),
                  )
                : const SizedBox(height: 16),
          ),
        ],
      ),
    );
  }
}
