import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:zai_x/services/comic_index/comic_index_service.dart';
import 'package:zai_x/services/local_storage_service.dart';

const _raw =
    'https://raw.githubusercontent.com/funkeyyou/zaimanhua/comic-index';
const _proxy =
    'https://gh-proxy.com/https://raw.githubusercontent.com/funkeyyou/zaimanhua/comic-index';
const _jsdelivr = 'https://cdn.jsdelivr.net/gh/funkeyyou/zaimanhua@comic-index';

/// 比 App 内建快照新的版本
const _version = 209912312359;

/// 依网址前缀回应档案；表里没有的来源一律当作连不上
class _FakeSources implements HttpClientAdapter {
  final Map<String, Map<String, List<int>>> files = {};
  final List<String> requests = [];

  List<String> get paths => requests.map((u) => u.split('?').first).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requests.add(url);
    for (final entry in files.entries) {
      if (url.startsWith('${entry.key}/')) {
        final name = url.substring(entry.key.length + 1).split('?').first;
        final body = entry.value[name];
        if (body == null) return ResponseBody.fromString('not found', 404);
        return ResponseBody.fromBytes(body, 200);
      }
    }
    throw const SocketException('模拟连不上');
  }

  @override
  void close({bool force = false}) {}
}

List<int> _index() => gzip.encode(utf8.encode(
      '#ZCI1\t$_version\t2099-12-31T23:59:00Z\t2\t20\n'
      '10\t测试作品\t\t作者甲\t1\t2\t5\n'
      '20\t另一部\t\t作者乙\t0\t1\t3\n',
    ));

List<int> _meta(List<int> gz) => utf8.encode(jsonEncode({
      'format': 1,
      'version': _version,
      'generatedAt': '2099-12-31T23:59:00Z',
      'count': 2,
      'maxId': 20,
      'bytes': gz.length,
      'file': 'comic_index.tsv.gz',
    }));

Map<String, List<int>> _files(List<int> gz, {List<int>? data}) => {
      'comic_index.json': _meta(gz),
      'comic_index.tsv.gz': data ?? gz,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStorageService storage;
  late _FakeSources sources;
  late DateTime now;
  late ComicIndexService service;

  setUp(() async {
    Get.testMode = true;
    dir = await Directory.systemTemp.createTemp('zmh-comic-index-');
    storage = LocalStorageService();
    storage.settingsBox =
        await Hive.openBox('comic-index-settings', path: dir.path);
    Get.put<LocalStorageService>(storage);
    sources = _FakeSources();
    now = DateTime.utc(2026, 9, 29, 12);
    service = ComicIndexService.forTest(
      dio: Dio()..httpClientAdapter = sources,
      supportDirectory: () async => dir,
      clock: () => now,
    );
  });

  tearDown(() async {
    Get.reset();
    await storage.settingsBox.close();
    await dir.delete(recursive: true);
  });

  test('自动检查的时机：成功后隔 24 小时，全部失败后隔 2 小时', () {
    final t = DateTime.utc(2026, 9, 29, 12);
    final ms = t.millisecondsSinceEpoch;
    const hour = 3600 * 1000;
    bool due(int success, int failure) => ComicIndexService.isAutoCheckDue(
        now: t, lastSuccess: success, lastFailure: failure);

    expect(due(0, 0), isTrue);
    expect(due(ms - 23 * hour, 0), isFalse);
    expect(due(ms - 24 * hour, 0), isTrue);
    expect(due(0, ms - 1 * hour), isFalse);
    expect(due(0, ms - 2 * hour), isTrue);
    // 调过系统时间、纪录比现在还晚：不能因此一直不检查
    expect(due(ms + 5 * hour, ms + 5 * hour), isTrue);
  });

  test('默认优先使用 gh-proxy，成功后才开始计时', () async {
    final gz = _index();
    sources.files[_proxy] = _files(gz);

    expect(await service.refresh(), ComicIndexUpdateResult.updated);
    expect(sources.paths, [
      '$_proxy/comic_index.json',
      '$_proxy/comic_index.tsv.gz',
    ]);
    expect(service.info.value?.version, _version);
    expect(service.info.value?.downloaded, isTrue);
    expect((await service.load())?.lookup(10)?.isHidden, isTrue);
    expect(File('${dir.path}/comic_index/comic_index.tsv.gz').readAsBytesSync(),
        gz);

    // 成功后 24 小时内不再自动检查
    sources.requests.clear();
    now = now.add(const Duration(hours: 23));
    expect(await service.refresh(), ComicIndexUpdateResult.skipped);
    expect(sources.requests, isEmpty);
  });

  test('所有来源都连不上：不开始计时，2 小时后再试', () async {
    expect(await service.refresh(), ComicIndexUpdateResult.failed);
    expect(sources.paths, [
      '$_proxy/comic_index.json',
      '$_raw/comic_index.json',
      '$_jsdelivr/comic_index.json',
    ]);

    sources.requests.clear();
    now = now.add(const Duration(hours: 1));
    expect(await service.refresh(), ComicIndexUpdateResult.skipped);
    expect(sources.requests, isEmpty);

    // 失败没有占用 24 小时的额度：2 小时后就会再试，这次 GitHub 通了
    final gz = _index();
    sources.files[_raw] = _files(gz);
    now = now.add(const Duration(hours: 1, minutes: 1));
    expect(await service.refresh(), ComicIndexUpdateResult.updated);
    expect(sources.paths, [
      '$_proxy/comic_index.json',
      '$_raw/comic_index.json',
      '$_raw/comic_index.tsv.gz',
    ]);
  });

  test('来源给的档案不完整就换下一个来源', () async {
    final gz = _index();
    sources.files[_proxy] = _files(gz, data: gz.sublist(0, gz.length ~/ 2));
    sources.files[_raw] = _files(gz);

    expect(await service.refresh(), ComicIndexUpdateResult.updated);
    expect(sources.paths.last, '$_raw/comic_index.tsv.gz');
  });

  test('已是最新也算连上；手动检查不受时间限制', () async {
    final gz = _index();
    sources.files[_proxy] = _files(gz);
    expect(await service.refresh(), ComicIndexUpdateResult.updated);

    sources.requests.clear();
    expect(await service.refresh(), ComicIndexUpdateResult.skipped);
    expect(await service.refresh(force: true), ComicIndexUpdateResult.upToDate);
    expect(sources.paths, ['$_proxy/comic_index.json']);
  });
}
