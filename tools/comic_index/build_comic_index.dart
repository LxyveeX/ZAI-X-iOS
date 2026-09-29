// 产生「本地漫画索引」：让官方搜索接口找不到的漫画（神隐、版权下架等）也能在 App 里被搜到。
//
// 官方 /search/index 不会返回 hidden=1、多数 copyright=1 以及少量其他作品；
// 但只要带上官方 App 的版本参数 _v，/comic/detail/{id} 仍会返回这些作品的基本资料。
// 这个工具逐一读取详情，输出一份精简的 TSV（gzip）：App 内建一份快照，
// GitHub Actions（.github/workflows/comic_index.yml）每天增量更新到 comic-index 分支。
//
// 只用 dart: 标准库，不需要 pub get：
//   全量（本机第一次）：
//     dart run tools/comic_index/build_comic_index.dart \
//       --cache=%TEMP%/comic_index_raw.jsonl --out-dir=assets/comic_index --floor=89000
//   增量（CI 每天）：
//     dart build_comic_index.dart --previous=prev/comic_index.tsv.gz --rotate=7 \
//       --out-dir=out --skip-unchanged
//
// 参数：
//   --out-dir=DIR       输出 comic_index.tsv.gz 与 comic_index.json 的目录
//   --previous=PATH     前一版索引（tsv.gz）；给了就是增量模式，没重抓的作品沿用旧资料
//   --rotate=N          增量模式要重抓哪些旧 ID：0=只抓新 ID，1=全部重抓，
//                       N>1=新 ID 加上 id % N == slot 的那一份（每 N 天轮完一遍）
//   --slot=K            配合 --rotate，预设为「自 1970 年起的天数 % N」
//   --cache=PATH        原始资料缓存（JSONL，可中断续跑；增量模式不使用）
//   --start=N           起始 ID（预设 1）
//   --end=N             结束 ID（预设 0 = 自动：越过 floor 后连续 --stop-after 个空 ID 就停）
//   --floor=N           自动结束前至少要扫到的 ID（预设为前一版的 maxId）
//   --stop-after=N      自动结束的连续空 ID 数（预设 400）
//   --concurrency=N     同时请求数（预设 3，请勿调太高）
//   --delay-ms=N        每个请求结束后的等待时间（预设 0）
//   --refresh           忽略缓存内已抓过的 ID，全部重新抓（缓存会被覆盖）
//   --build-only        不联网，只用缓存（或前一版）重建输出档
//   --skip-unchanged    内容与前一版完全相同时不输出
//   --max-error-rate=R  失败比例超过 R 就不输出（预设 0.01）
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String kApiBase = 'https://v4api.zaimanhua.com/app/v1';

/// 官方 App 版本号；低于 2.2.x 时隐藏作品的详情会被当成「漫画不存在」。
/// 与 App 端 Api.APP_VERSION 保持一致。
const String kAppVersion = '2.3.8';

const String kIndexFileName = 'comic_index.tsv.gz';
const String kMetaFileName = 'comic_index.json';
const int kFormat = 1;

Future<void> main(List<String> argv) async {
  final args = _Args.parse(argv);
  final previous = args.previousPath == null
      ? null
      : await _Previous.load(args.previousPath!);
  if (previous != null) {
    stdout.writeln(
        '前一版索引：${previous.lines.length} 部，maxId ${previous.maxId}，version ${previous.version}。');
    if (args.cachePath != null) {
      stdout.writeln('增量模式不使用 --cache。');
      args.cachePath = null;
    }
  }
  final cache = _RawCache(args.cachePath);
  await cache.load(ignoreExisting: args.refresh);
  if (args.cachePath != null) {
    stdout.writeln('缓存内已有 ${cache.records.length} 笔（含空 ID）。');
  }

  final crawled = <int>{};
  if (!args.buildOnly) {
    var floor = args.floor;
    if (floor <= 0) {
      floor = previous?.maxId ?? await _previousMaxId(args.outDir);
    }
    final crawler = _Crawler(args, cache, floor: floor, previous: previous);
    await crawler.run();
    await cache.flush();
    crawled.addAll(crawler.crawledIds);
    final attempted =
        crawler.okCount + crawler.emptyCount + crawler.errorIds.length;
    final errorRate =
        attempted == 0 ? 0.0 : crawler.errorIds.length / attempted;
    stdout.writeln('本次抓取：有效 ${crawler.okCount}、空 ID ${crawler.emptyCount}、'
        '失败 ${crawler.errorIds.length}（${(errorRate * 100).toStringAsFixed(2)}%），'
        '扫到 ID ${crawler.lastIssuedId}。');
    if (errorRate > args.maxErrorRate) {
      stderr.writeln(
          '失败比例过高，不输出索引。失败 ID 例：${crawler.errorIds.take(20).join(",")}');
      exitCode = 2;
      return;
    }
  }

  // 合并：增量模式以前一版为底，只套用这次重抓到的结果（失败的维持旧资料）
  final lines = <int, String>{};
  if (previous != null) {
    lines.addAll(previous.lines);
  }
  for (final record in cache.records.values) {
    final id = record['id'] as int;
    if (id <= 0) continue;
    if (previous != null && !crawled.contains(id)) continue;
    if (record['x'] != null) {
      lines.remove(id);
    } else {
      lines[id] = indexLine(record);
    }
  }
  if (lines.length < 1000) {
    stderr.writeln('有效作品只有 ${lines.length} 笔，看起来不完整，不输出。');
    exitCode = 3;
    return;
  }
  if (args.skipUnchanged &&
      previous != null &&
      _sameLines(previous.lines, lines)) {
    stdout.writeln('内容与前一版相同，不输出。');
    return;
  }
  await _writeIndex(args.outDir, lines);
}

class _Args {
  String? cachePath;
  String? previousPath;
  String outDir = 'assets/comic_index';
  int start = 1;
  int end = 0;
  int floor = 0;
  int stopAfter = 400;
  int concurrency = 3;
  int delayMs = 0;
  int rotate = 0;
  int? slot;
  bool refresh = false;
  bool buildOnly = false;
  bool skipUnchanged = false;
  double maxErrorRate = 0.01;

  static _Args parse(List<String> argv) {
    final a = _Args();
    for (final raw in argv) {
      final i = raw.indexOf('=');
      final key = i < 0 ? raw : raw.substring(0, i);
      final value = i < 0 ? '' : raw.substring(i + 1);
      switch (key) {
        case '--cache':
          a.cachePath = value.isEmpty ? null : value;
        case '--previous':
          a.previousPath = value.isEmpty ? null : value;
        case '--out-dir':
          a.outDir = value;
        case '--start':
          a.start = int.parse(value);
        case '--end':
          a.end = int.parse(value);
        case '--floor':
          a.floor = int.parse(value);
        case '--stop-after':
          a.stopAfter = int.parse(value);
        case '--concurrency':
          a.concurrency = int.parse(value).clamp(1, 8);
        case '--delay-ms':
          a.delayMs = int.parse(value);
        case '--rotate':
          a.rotate = int.parse(value);
        case '--slot':
          a.slot = int.parse(value);
        case '--refresh':
          a.refresh = true;
        case '--build-only':
          a.buildOnly = true;
        case '--skip-unchanged':
          a.skipUnchanged = true;
        case '--max-error-rate':
          a.maxErrorRate = double.parse(value);
        default:
          stderr.writeln('未知参数：$raw');
          exit(64);
      }
    }
    return a;
  }

  /// 增量模式下，这个旧 ID 今天要不要重抓
  bool shouldRefresh(int id) {
    if (rotate == 1) return true;
    if (rotate <= 0) return false;
    final today =
        DateTime.now().toUtc().difference(DateTime.utc(1970)).inDays % rotate;
    return id % rotate == (slot ?? today);
  }
}

/// 前一版索引：id -> 原始 TSV 行
class _Previous {
  _Previous(this.version, this.maxId, this.lines);
  final int version;
  final int maxId;
  final Map<int, String> lines;

  static Future<_Previous> load(String path) async {
    final text = utf8.decode(gzip.decode(await File(path).readAsBytes()));
    final all = const LineSplitter().convert(text);
    if (all.isEmpty || !all.first.startsWith('#ZCI$kFormat\t')) {
      throw FormatException('不是漫画索引：$path');
    }
    final head = all.first.split('\t');
    final declared = int.tryParse(head.length > 3 ? head[3] : '') ?? -1;
    final lines = <int, String>{};
    var maxId = 0;
    for (final line in all.skip(1)) {
      if (line.isEmpty) continue;
      final id = int.parse(line.substring(0, line.indexOf('\t')));
      lines[id] = line;
      if (id > maxId) maxId = id;
    }
    if (declared >= 0 && declared != lines.length) {
      throw FormatException('前一版索引不完整：应有 $declared 部，实际 ${lines.length} 部');
    }
    return _Previous(int.tryParse(head[1]) ?? 0, maxId, lines);
  }
}

/// 原始资料：id -> 精简后的详情（空 ID 记成 {"id":n,"x":1}）
class _RawCache {
  _RawCache(this.path);
  final String? path;
  final Map<int, Map<String, dynamic>> records = {};
  final List<String> _pending = [];

  Future<void> load({required bool ignoreExisting}) async {
    final p = path;
    if (p == null) return;
    final file = File(p);
    if (!await file.exists()) return;
    if (ignoreExisting) {
      await file.delete();
      return;
    }
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final map = jsonDecode(line) as Map<String, dynamic>;
        records[map['id'] as int] = map;
      } catch (_) {
        // 中断时最后一行可能写一半，直接略过
      }
    }
  }

  void put(Map<String, dynamic> record) {
    records[record['id'] as int] = record;
    if (path != null) _pending.add(jsonEncode(record));
  }

  Future<void> flush() async {
    final p = path;
    if (p == null || _pending.isEmpty) return;
    final file = File(p);
    await file.parent.create(recursive: true);
    await file.writeAsString('${_pending.join('\n')}\n',
        mode: FileMode.append, encoding: utf8, flush: true);
    _pending.clear();
  }
}

class _Crawler {
  _Crawler(this.args, this.cache, {required this.floor, this.previous});
  final _Args args;
  final _RawCache cache;
  final int floor;
  final _Previous? previous;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'Dart/3.4 (dart:io)';

  int _next = 0;
  int lastIssuedId = 0;
  int _lastFoundId = 0;
  int okCount = 0;
  int emptyCount = 0;
  final List<int> errorIds = [];
  final Set<int> crawledIds = {};
  final Stopwatch _clock = Stopwatch();
  int _done = 0;

  Future<void> run() async {
    _next = args.start;
    _lastFoundId = cache.records.values
        .where((e) => e['x'] == null)
        .fold<int>(0, (m, e) => (e['id'] as int) > m ? e['id'] as int : m);
    final prev = previous;
    if (prev != null && prev.maxId > _lastFoundId) _lastFoundId = prev.maxId;
    _clock.start();
    stdout.writeln('开始抓取：start=${args.start} '
        'end=${args.end == 0 ? "auto" : args.end} floor=$floor 并发=${args.concurrency}'
        '${prev == null ? "" : " 增量 rotate=${args.rotate}"}');
    await Future.wait(List.generate(args.concurrency, (_) => _worker()));
    _http.close(force: true);
  }

  int? _take() {
    final prev = previous;
    while (true) {
      final id = _next;
      if (args.end > 0) {
        if (id > args.end) return null;
      } else if (id > floor && id > _lastFoundId + args.stopAfter) {
        return null;
      }
      _next++;
      if (prev != null) {
        // 增量：旧 ID 只在轮到时重抓，新 ID 全部要抓
        if (id <= prev.maxId && !args.shouldRefresh(id)) continue;
      } else {
        final cached = cache.records[id];
        if (cached != null) {
          if (cached['x'] == null && id > _lastFoundId) _lastFoundId = id;
          continue;
        }
      }
      lastIssuedId = id;
      return id;
    }
  }

  Future<void> _worker() async {
    while (true) {
      final id = _take();
      if (id == null) return;
      final record = await _fetchWithRetry(id);
      if (record == null) {
        errorIds.add(id);
      } else {
        cache.put(record);
        crawledIds.add(id);
        if (record['x'] == null) {
          okCount++;
          if (id > _lastFoundId) _lastFoundId = id;
        } else {
          emptyCount++;
        }
      }
      _done++;
      if (_done % 500 == 0) {
        await cache.flush();
        final rate = _done / (_clock.elapsedMilliseconds / 1000);
        stdout.writeln('进度：ID $id，已处理 $_done（${rate.toStringAsFixed(1)}/s），'
            '有效 $okCount、空 $emptyCount、失败 ${errorIds.length}');
      }
      if (args.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: args.delayMs));
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchWithRetry(int id) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
            Duration(milliseconds: 800 * (1 << attempt)));
      }
      try {
        return await _fetch(id);
      } catch (e) {
        if (attempt == 3) stderr.writeln('ID $id 失败：$e');
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _fetch(int id) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri =
        Uri.parse('$kApiBase/comic/detail/$id').replace(queryParameters: {
      'channel': 'android',
      'timestamp': '$ts',
      '_v': kAppVersion,
    });
    final request = await _http.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 25));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final errno = int.tryParse('${json['errno']}') ?? -1;
    if (errno == 2) return {'id': id, 'x': 1};
    if (errno != 0) throw StateError('errno=$errno ${json['errmsg']}');
    final data = (json['data'] as Map?)?['data'];
    if (data is! Map || (data['id'] ?? 0) == 0) return {'id': id, 'x': 1};
    return compactDetail(data.cast<String, dynamic>());
  }
}

List<String> _tagNames(dynamic list) => list is List
    ? list
        .whereType<Map>()
        .map((e) => '${e['tag_name'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList()
    : const [];

int _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

/// 只留下索引与日后可能用到的栏位
Map<String, dynamic> compactDetail(Map<String, dynamic> d) => {
      'id': _int(d['id']),
      't': '${d['title'] ?? ''}'.trim(),
      'al': '${d['aliasName'] ?? ''}'.trim(),
      'rn': '${d['realName'] ?? ''}'.trim(),
      'au': _tagNames(d['authors']),
      'ty': _tagNames(d['types']),
      'st': _tagNames(d['status']),
      'c': '${d['cover'] ?? ''}',
      'lu': _int(d['last_updatetime']),
      'lc': '${d['last_update_chapter_name'] ?? ''}'.trim(),
      'h': _int(d['hidden']),
      'cr': _int(d['copyright']),
      'r': d['canRead'] == true ? 1 : 0,
      'nl': _int(d['is_need_login']),
      'lk': _int(d['is_lock']),
      'hot': _int(d['hot_num']),
    };

/// 旗标位元，与 App 端 ComicIndexFlags 对应
int indexFlags(Map<String, dynamic> e) {
  final hidden = _int(e['h']);
  var flags = 0;
  if (hidden == 1) flags |= 1;
  if (hidden != 0 && hidden != 1) flags |= 2;
  if (_int(e['cr']) == 1) flags |= 4;
  if (_int(e['r']) == 0) flags |= 8;
  if (_int(e['lk']) == 1) flags |= 16;
  return flags;
}

String _clean(String s) => s.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();

/// 别名：aliasName 以逗号/顿号分隔，realName 整个当一个；去掉与标题相同的
String indexAliases(Map<String, dynamic> e) {
  final title = _clean('${e['t'] ?? ''}');
  final out = <String>[];
  void add(String raw) {
    final v = _clean(raw).replaceAll('|', ' ');
    if (v.isEmpty || v == title || out.contains(v)) return;
    out.add(v);
  }

  for (final part in '${e['al'] ?? ''}'.split(RegExp(r'[,，、|]'))) {
    add(part);
  }
  add('${e['rn'] ?? ''}');
  var joined = out.join('|');
  if (joined.length > 160) {
    joined = joined.substring(0, 160);
  }
  return joined;
}

int indexStatus(Map<String, dynamic> e) {
  final st = (e['st'] as List?)?.join('/') ?? '';
  if (st.contains('连载')) return 1;
  if (st.contains('完结')) return 2;
  return 0;
}

/// 一行索引：id、标题、别名(|)、作者(/)、旗标、状态、热度
String indexLine(Map<String, dynamic> e) => [
      e['id'],
      _clean('${e['t'] ?? ''}'),
      indexAliases(e),
      _clean(((e['au'] as List?) ?? const []).join('/')),
      indexFlags(e),
      indexStatus(e),
      _int(e['hot']),
    ].join('\t');

bool _sameLines(Map<int, String> a, Map<int, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

Future<int> _previousMaxId(String outDir) async {
  final meta = File('$outDir/$kMetaFileName');
  if (!await meta.exists()) return 0;
  try {
    final map = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
    return _int(map['maxId']);
  } catch (_) {
    return 0;
  }
}

Future<void> _writeIndex(String outDir, Map<int, String> lines) async {
  final ids = lines.keys.toList()..sort();
  final now = DateTime.now().toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final version = int.parse('${now.year}${two(now.month)}${two(now.day)}'
      '${two(now.hour)}${two(now.minute)}');
  final maxId = ids.last;
  final generatedAt = now.toIso8601String();
  final sb = StringBuffer()
    ..write('#ZCI$kFormat\t$version\t$generatedAt\t${ids.length}\t$maxId\n');
  var hidden = 0, copyright = 0;
  for (final id in ids) {
    final line = lines[id]!;
    sb
      ..write(line)
      ..write('\n');
    final fields = line.split('\t');
    final flags = fields.length > 4 ? int.tryParse(fields[4]) ?? 0 : 0;
    if (flags & 1 != 0) hidden++;
    if (flags & 4 != 0) copyright++;
  }
  final raw = utf8.encode(sb.toString());
  final gz = GZipCodec(level: 9).encode(raw);
  await Directory(outDir).create(recursive: true);
  final indexFile = File('$outDir/$kIndexFileName');
  await indexFile.writeAsBytes(gz, flush: true);
  final meta = {
    'format': kFormat,
    'version': version,
    'generatedAt': generatedAt,
    'count': ids.length,
    'maxId': maxId,
    'bytes': gz.length,
    'file': kIndexFileName,
  };
  await File('$outDir/$kMetaFileName').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(meta)}\n',
      flush: true);
  stdout.writeln('已输出 ${indexFile.path}：${ids.length} 部'
      '（神隐 $hidden、版权 $copyright），'
      '原始 ${(raw.length / 1048576).toStringAsFixed(2)} MB，'
      'gzip ${(gz.length / 1048576).toStringAsFixed(2)} MB，'
      'maxId $maxId，version $version。');
}
