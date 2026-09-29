import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/requests/common/github_proxy.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';
import 'package:zai_x/services/local_storage_service.dart';

/// 索引的基本资讯（设定页显示用）
class ComicIndexInfo {
  const ComicIndexInfo({
    required this.version,
    required this.count,
    required this.generatedAt,
    required this.downloaded,
  });

  final int version;
  final int count;
  final String generatedAt;

  /// true=从 GitHub 更新下来的；false=App 内建的快照
  final bool downloaded;

  DateTime? get generatedTime => DateTime.tryParse(generatedAt)?.toLocal();
}

/// comic_index.json 的内容
class ComicIndexMeta {
  const ComicIndexMeta({
    required this.version,
    required this.count,
    required this.generatedAt,
    required this.bytes,
    required this.file,
  });

  factory ComicIndexMeta.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    final format = toInt(json['format']);
    final file = '${json['file'] ?? ComicIndexService.indexFileName}';
    if (format != 1 || !RegExp(r'^[\w.-]+$').hasMatch(file)) {
      throw FormatException('不支援的漫画索引：format=$format file=$file');
    }
    return ComicIndexMeta(
      version: toInt(json['version']),
      count: toInt(json['count']),
      generatedAt: '${json['generatedAt'] ?? ''}',
      bytes: toInt(json['bytes']),
      file: file,
    );
  }

  final int version;
  final int count;
  final String generatedAt;
  final int bytes;
  final String file;

  Map<String, dynamic> toJson() => {
        'format': 1,
        'version': version,
        'count': count,
        'generatedAt': generatedAt,
        'bytes': bytes,
        'file': file,
      };
}

enum ComicIndexUpdateResult { updated, upToDate, skipped, busy, failed }

/// 本地漫画索引
///
/// 官方搜索不会返回神隐等作品，所以另外维护一份全站作品清单：
/// GitHub Actions 每天更新到仓库的 comic-index 分支，App 拉回来存在本机；
/// 另外内建一份快照，第一次使用或连不上 GitHub 时也能搜。
class ComicIndexService {
  ComicIndexService._({
    Dio? dio,
    Future<Directory> Function()? supportDirectory,
    DateTime Function()? clock,
    Future<bool> Function()? unmetered,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 30),
              ),
            ),
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _clock = clock ?? DateTime.now,
        _unmetered = unmetered ?? _isUnmetered {
    try {
      enabled.value =
          LocalStorageService.instance.getValue<bool>(_kEnabled, true);
    } catch (e) {
      Log.logPrint(e);
    }
  }

  static final ComicIndexService instance = ComicIndexService._();

  /// 测试用：替换网络、存放资料夹、时间与网络类型判断
  @visibleForTesting
  factory ComicIndexService.forTest({
    required Dio dio,
    required Future<Directory> Function() supportDirectory,
    required DateTime Function() clock,
    Future<bool> Function()? unmetered,
  }) =>
      ComicIndexService._(
        dio: dio,
        supportDirectory: supportDirectory,
        clock: clock,
        unmetered: unmetered ?? () async => true,
      );

  static const String assetPath = 'assets/comic_index/comic_index.tsv.gz';
  static const String assetMetaPath = 'assets/comic_index/comic_index.json';
  static const String indexFileName = 'comic_index.tsv.gz';
  static const String metaFileName = 'comic_index.json';

  static const String _githubRaw =
      'https://raw.githubusercontent.com/funkeyyou/zaimanhua/comic-index';

  /// 下载来源，依序尝试，前一个连不上或内容不对就换下一个：
  /// gh-proxy 加速 → GitHub 原站 → jsDelivr
  static const List<String> remoteBases = [
    '$githubProxyPrefix$_githubRaw',
    _githubRaw,
    'https://cdn.jsdelivr.net/gh/funkeyyou/zaimanhua@comic-index',
  ];

  /// 成功连上后，下次自动检查的最短间隔（资料每天更新一次）
  static const Duration checkInterval = Duration(hours: 24);

  /// 所有来源都连不上时，隔多久再自动重试
  static const Duration retryInterval = Duration(hours: 2);

  /// 单一来源读 meta、下载索引的时间上限，超过就换下一个来源
  static const Duration metaTimeout = Duration(seconds: 15);
  static const Duration downloadTimeout = Duration(minutes: 2);

  /// 下载档案大小上限，防止异常内容
  static const int maxDownloadBytes = 30 * 1024 * 1024;

  static const String _kEnabled = 'ComicIndexEnabled';

  /// 上次成功连上来源（已是最新或更新成功）的时间
  static const String _kLastCheck = 'ComicIndexLastCheck';

  /// 上次所有来源都连不上的时间
  static const String _kLastFailure = 'ComicIndexLastFailure';

  /// 搜索时是否附上本地索引的结果
  final RxBool enabled = true.obs;
  final Rx<ComicIndexInfo?> info = Rx<ComicIndexInfo?>(null);
  final RxBool updating = false.obs;

  ComicIndex? _index;
  Future<ComicIndex?>? _loading;

  final Dio _dio;
  final Future<Directory> Function() _supportDirectory;
  final DateTime Function() _clock;
  final Future<bool> Function() _unmetered;

  void setEnabled(bool value) {
    enabled.value = value;
    LocalStorageService.instance.setValue(_kEnabled, value);
  }

  /// 搜索本地索引；未启用或载入失败时返回空列表
  Future<List<ComicIndexHit>> search(String keyword, {int limit = 300}) async {
    if (!enabled.value) return const [];
    final index = await load();
    return index?.search(keyword, limit: limit) ?? const [];
  }

  /// 载入索引（较新的下载档优先，失败就用内建快照），解析在背景 isolate 进行
  Future<ComicIndex?> load() {
    final loaded = _index;
    if (loaded != null) return Future.value(loaded);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<ComicIndex?> _load() async {
    final bundled = await _bundledMeta();
    final local = await _localMeta();
    if (local != null && local.version > (bundled?.version ?? 0)) {
      try {
        final bytes = await (await _localFile(indexFileName)).readAsBytes();
        final index = await Isolate.run(() => ComicIndex.decodeGzip(bytes));
        _adopt(index, downloaded: true);
        return _index;
      } catch (e) {
        Log.logPrint(e);
        await _deleteDownloaded();
      }
    }
    try {
      final data = await rootBundle.load(assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final index = await Isolate.run(() => ComicIndex.decodeGzip(bytes));
      _adopt(index, downloaded: false);
      return _index;
    } catch (e) {
      Log.logPrint(e);
      return _index;
    }
  }

  /// 只读 meta，不解析整份索引（设定页用）
  Future<ComicIndexInfo?> loadInfo() async {
    if (_index != null) return info.value;
    final bundled = await _bundledMeta();
    final local = await _localMeta();
    final useLocal = local != null && local.version > (bundled?.version ?? 0);
    final meta = useLocal ? local : bundled;
    if (meta != null && _index == null) {
      info.value = ComicIndexInfo(
        version: meta.version,
        count: meta.count,
        generatedAt: meta.generatedAt,
        downloaded: useLocal,
      );
    }
    return info.value;
  }

  /// 检查 GitHub 上有没有较新的索引
  ///
  /// 自动检查（[force] 为 false）：成功连上后 [checkInterval] 内不再检查；
  /// 所有来源都连不上时，过 [retryInterval] 再试；手机只在 Wi-Fi 或有线网络时下载。
  /// 手动更新不受这些限制。
  Future<ComicIndexUpdateResult> refresh({bool force = false}) async {
    if (updating.value) return ComicIndexUpdateResult.busy;
    final storage = LocalStorageService.instance;
    if (!force) {
      if (!enabled.value) return ComicIndexUpdateResult.skipped;
      final due = isAutoCheckDue(
        now: _clock(),
        lastSuccess: storage.getValue<int>(_kLastCheck, 0),
        lastFailure: storage.getValue<int>(_kLastFailure, 0),
      );
      if (!due || !await _unmetered()) return ComicIndexUpdateResult.skipped;
    }
    updating.value = true;
    try {
      final result = await _checkSources();
      // 真的连上（已是最新或更新成功）才开始计算 24 小时；全部失败就晚点再试
      final finishedAt = _clock().millisecondsSinceEpoch;
      if (result == ComicIndexUpdateResult.failed) {
        await storage.setValue(_kLastFailure, finishedAt);
      } else {
        await storage.setValue(_kLastCheck, finishedAt);
        await storage.removeValue(_kLastFailure);
      }
      return result;
    } finally {
      updating.value = false;
    }
  }

  /// 现在是否该自动检查：距上次成功满 [checkInterval]，且距上次全部失败满 [retryInterval]。
  /// 纪录的时间比现在还晚（调过系统时间）就当作已经过了，避免卡住不再检查。
  @visibleForTesting
  static bool isAutoCheckDue({
    required DateTime now,
    required int lastSuccess,
    required int lastFailure,
  }) {
    final ms = now.millisecondsSinceEpoch;
    bool passed(int since, Duration wait) =>
        since > ms || ms - since >= wait.inMilliseconds;
    return passed(lastSuccess, checkInterval) &&
        passed(lastFailure, retryInterval);
  }

  /// 依序尝试各个来源；已是最新或更新成功就停
  Future<ComicIndexUpdateResult> _checkSources() async {
    final current = (await loadInfo())?.version ?? 0;
    for (final base in remoteBases) {
      try {
        final meta = await _fetchMeta('$base/$metaFileName');
        if (meta.version <= current) return ComicIndexUpdateResult.upToDate;
        final bytes = await _fetchBytes('$base/${meta.file}');
        if (meta.bytes > 0 && bytes.length != meta.bytes) {
          throw const FormatException('漫画索引大小不符');
        }
        final index = await Isolate.run(() => ComicIndex.decodeGzip(bytes));
        if (index.version != meta.version || index.length != meta.count) {
          throw const FormatException('漫画索引版本不符');
        }
        await _saveDownloaded(bytes, meta);
        _adopt(index, downloaded: true);
        return ComicIndexUpdateResult.updated;
      } catch (e) {
        Log.logPrint(e);
      }
    }
    return ComicIndexUpdateResult.failed;
  }

  void _adopt(ComicIndex index, {required bool downloaded}) {
    final current = _index;
    if (current != null && current.version >= index.version) return;
    _index = index;
    info.value = ComicIndexInfo(
      version: index.version,
      count: index.length,
      generatedAt: index.generatedAt,
      downloaded: downloaded,
    );
  }

  Future<ComicIndexMeta?> _bundledMeta() async {
    try {
      final text = await rootBundle.loadString(assetMetaPath);
      return ComicIndexMeta.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (e) {
      Log.logPrint(e);
      return null;
    }
  }

  Future<ComicIndexMeta?> _localMeta() async {
    try {
      final metaFile = await _localFile(metaFileName);
      final indexFile = await _localFile(indexFileName);
      if (!await metaFile.exists() || !await indexFile.exists()) return null;
      return ComicIndexMeta.fromJson(
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>);
    } catch (e) {
      Log.logPrint(e);
      return null;
    }
  }

  Future<File> _localFile(String name) async {
    final dir = await _supportDirectory();
    return File(p.join(dir.path, 'comic_index', name));
  }

  Future<void> _saveDownloaded(List<int> bytes, ComicIndexMeta meta) async {
    final indexFile = await _localFile(indexFileName);
    final metaFile = await _localFile(metaFileName);
    await indexFile.parent.create(recursive: true);
    // 先写暂存档再改名，避免写到一半被中断留下坏档
    final tmp = File('${indexFile.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await indexFile.exists()) await indexFile.delete();
    await tmp.rename(indexFile.path);
    await metaFile.writeAsString(jsonEncode(meta.toJson()), flush: true);
  }

  Future<void> _deleteDownloaded() async {
    for (final name in [indexFileName, metaFileName]) {
      try {
        final file = await _localFile(name);
        if (await file.exists()) await file.delete();
      } catch (e) {
        Log.logPrint(e);
      }
    }
  }

  Future<ComicIndexMeta> _fetchMeta(String url) async {
    final text = await _get<String>(
      url,
      ResponseType.plain,
      metaTimeout,
      // 每分钟换一次参数，避开 CDN 与代理的旧快取
      query: {'t': _clock().millisecondsSinceEpoch ~/ 60000},
    );
    return ComicIndexMeta.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<List<int>> _fetchBytes(String url) async {
    final data =
        await _get<List<int>>(url, ResponseType.bytes, downloadTimeout);
    if (data.isEmpty) {
      throw const FormatException('漫画索引下载失败');
    }
    return data;
  }

  /// 读取单一档案；超过 [limit] 或 [maxDownloadBytes] 就中止，交给下一个来源
  Future<T> _get<T>(
    String url,
    ResponseType type,
    Duration limit, {
    Map<String, dynamic>? query,
  }) async {
    final cancel = CancelToken();
    final timer = Timer(limit, () => cancel.cancel('漫画索引下载超时'));
    try {
      final response = await _dio.get<T>(
        url,
        queryParameters: query,
        cancelToken: cancel,
        options: Options(responseType: type),
        onReceiveProgress: (received, total) {
          if (received > maxDownloadBytes || total > maxDownloadBytes) {
            cancel.cancel('漫画索引档案过大');
          }
        },
      );
      final data = response.data;
      if (data == null) throw const FormatException('漫画索引下载失败');
      return data;
    } finally {
      timer.cancel();
    }
  }

  static Future<bool> _isUnmetered() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return true;
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet);
    } catch (e) {
      Log.logPrint(e);
      return false;
    }
  }
}
