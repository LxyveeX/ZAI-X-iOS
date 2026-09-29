import 'dart:io';

import 'package:dio/dio.dart';
import 'package:zai_x/models/version_model.dart';
import 'package:zai_x/requests/common/github_proxy.dart';

/// 通用的请求
class CommonRequest {
  CommonRequest({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
            ));

  final Dio _dio;

  /// 版本信息来源：本仓库的 GitHub Release
  static const String kRepo = "funkeyyou/zaimanhua";

  Future<VersionModel> checkUpdate() async {
    return await checkUpdateGithubRelease();
  }

  /// 检查更新：读取仓库最新的 Release
  Future<VersionModel> checkUpdateGithubRelease() async {
    final sources =
        githubSources("https://api.github.com/repos/$kRepo/releases/latest");
    for (var i = 0; i < sources.length; i++) {
      try {
        final result = await _dio.get(
          sources[i],
          queryParameters: {
            "ts": DateTime.now().millisecondsSinceEpoch,
          },
          options: Options(
            responseType: ResponseType.json,
            headers: const {
              "Accept": "application/vnd.github+json",
            },
          ),
        );
        final data = result.data;
        if (data is! Map ||
            !RegExp(r'^v?\d+\.\d+\.\d+$')
                .hasMatch(data["tag_name"]?.toString() ?? "")) {
          throw const FormatException('版本信息不完整');
        }
        return parseRelease(
          data,
          android: Platform.isAndroid,
          windows: Platform.isWindows,
        );
      } catch (_) {
        if (i == sources.length - 1) rethrow;
      }
    }
    throw StateError('没有可用的更新来源');
  }

  /// 把 Release 转换成版本信息
  ///
  /// tag 形如 v1.4.0；下载地址优先取当前平台对应的资源，并带上资源的
  /// SHA-256 与大小，供下载后校验。平台以参数传入方便测试。
  static VersionModel parseRelease(
    Map json, {
    required bool android,
    required bool windows,
  }) {
    var tag = (json["tag_name"] ?? "").toString();
    var version = tag.startsWith("v") ? tag.substring(1) : tag;
    var assets = (json["assets"] as List?) ?? const [];
    var downloadUrl = (json["html_url"] ?? "").toString();
    var sha256 = "";
    var size = 0;
    for (var item in assets) {
      var name = (item["name"] ?? "").toString().toLowerCase();
      var url = (item["browser_download_url"] ?? "").toString();
      if (url.isEmpty) continue;
      if ((android && name.endsWith(".apk")) ||
          (windows && name.endsWith(".zip"))) {
        downloadUrl = url;
        var digest = (item["digest"] ?? "").toString();
        if (digest.startsWith("sha256:")) {
          sha256 = digest.substring("sha256:".length).toLowerCase();
        }
        size = (item["size"] as num?)?.toInt() ?? 0;
        break;
      }
    }
    return VersionModel(
      version: version,
      versionNum: _parseVersionNum(version),
      versionDesc: (json["body"] ?? "").toString().trim(),
      downloadUrl: downloadUrl,
      sha256: sha256,
      size: size,
    );
  }

  /// 1.4.0 -> 10400，与 Utils.parseVersion 保持一致
  static int _parseVersionNum(String version) {
    var num = "";
    for (var item in version.split(".")) {
      var digits = item.replaceAll(RegExp(r'[^0-9]'), "");
      if (digits.isEmpty) digits = "0";
      num += digits.padLeft(2, "0");
    }
    return int.tryParse(num) ?? 0;
  }
}
