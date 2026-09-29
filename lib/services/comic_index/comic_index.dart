import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:zai_x/app/t2s_chars.g.dart';

/// 本地漫画索引的旗标位元，与 tools/comic_index/build_comic_index.dart 的
/// indexFlags 对应。
abstract final class ComicIndexFlags {
  /// hidden == 1：神隐，官方搜索与列表都不会出现
  static const int hidden = 1;

  /// hidden 为其他非 0 值（实测多数仍搜得到）
  static const int hiddenOther = 2;

  /// copyright == 1：实测九成以上官方搜索找不到
  static const int copyright = 4;

  /// 未登录时不能阅读
  static const int needPermission = 8;

  /// is_lock == 1
  static const int locked = 16;
}

/// 一笔本地索引的搜索结果
class ComicIndexHit {
  const ComicIndexHit({
    required this.id,
    required this.title,
    required this.authors,
    required this.flags,
    required this.status,
    required this.hot,
    required this.tier,
  });

  final int id;
  final String title;

  /// 以「/」分隔的作者
  final String authors;
  final int flags;

  /// 0=未知，1=连载中，2=已完结
  final int status;
  final int hot;

  /// 比对等级，越小越相关：
  /// 0 标题完全相同、1 别名完全相同、2 标题开头相同、3 标题包含、4 别名包含、5 作者
  final int tier;

  bool get isHidden => flags & ComicIndexFlags.hidden != 0;

  /// 官方搜索大概率找不到（神隐或 copyright=1）
  bool get likelyUnsearchable =>
      flags & (ComicIndexFlags.hidden | ComicIndexFlags.copyright) != 0;
}

/// 搜索比对用的文字正规化：繁转简（逐字）、全形转半形、英文转小写、去掉空白与标点。
/// 索引与关键字都经过同一个函式，所以简繁混打也能对上。
abstract final class ComicIndexText {
  static Uint16List? _table;

  static Uint16List get _t2s {
    var table = _table;
    if (table != null) return table;
    table = Uint16List(0x10000);
    final n = kT2sFrom.length < kT2sTo.length ? kT2sFrom.length : kT2sTo.length;
    for (var i = 0; i < n; i++) {
      table[kT2sFrom.codeUnitAt(i)] = kT2sTo.codeUnitAt(i);
    }
    return _table = table;
  }

  static final RegExp _space = RegExp(r'\s+');

  static String normalize(String input) {
    if (input.isEmpty) return input;
    final table = _t2s;
    final codes = Uint16List(input.length);
    var n = 0;
    for (var i = 0; i < input.length; i++) {
      var c = input.codeUnitAt(i);
      // 全形 ASCII（！～）转半形
      if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
      if (c < 0x80) {
        if (c >= 0x41 && c <= 0x5A) {
          c += 0x20;
        } else if (!(c >= 0x30 && c <= 0x39) && !(c >= 0x61 && c <= 0x7A)) {
          // ASCII 空白、标点与控制字元
          continue;
        }
      } else if (_isSeparator(c)) {
        continue;
      } else {
        if (c >= 0xC0 && c <= 0xDE && c != 0xD7) c += 0x20;
        final simplified = table[c];
        if (simplified != 0) c = simplified;
      }
      codes[n++] = c;
    }
    return String.fromCharCodes(codes, 0, n);
  }

  /// 以空白拆成多个关键字（全部都要命中）
  static List<String> tokens(String query) =>
      query.split(_space).map(normalize).where((t) => t.isNotEmpty).toList();

  static bool _isSeparator(int c) =>
      (c >= 0x80 && c <= 0xBF) ||
      c == 0xD7 ||
      c == 0xF7 ||
      (c >= 0x2000 && c <= 0x206F) || // 一般标点、各种空白
      (c >= 0x2190 && c <= 0x21FF) || // 箭头
      (c >= 0x2500 && c <= 0x27BF) || // 框线、几何图形、☆♡♪ 等符号
      (c >= 0x3000 &&
          c <= 0x303F &&
          c != 0x3005 &&
          c != 0x3006 &&
          c != 0x3007) ||
      c == 0x30FB || // 片假名中点
      (c >= 0xFE30 && c <= 0xFE6F) ||
      (c >= 0xFF5F && c <= 0xFF65);
}

/// 本地漫画索引（格式见 tools/comic_index/build_comic_index.dart）
///
/// 为了省记忆体，比对用的正规化文字全部串成一个大字串，
/// 每部作品一段：标题、\u0001别名…、\u0002作者(\u0003分隔)、\n。
class ComicIndex {
  ComicIndex._({
    required this.version,
    required this.generatedAt,
    required this.maxId,
    required Int32List ids,
    required Uint8List flags,
    required Uint8List status,
    required Int32List hot,
    required List<String> titles,
    required List<String> authors,
    required String blob,
    required Int32List starts,
  })  : _ids = ids,
        _flags = flags,
        _status = status,
        _hot = hot,
        _titles = titles,
        _authors = authors,
        _blob = blob,
        _starts = starts;

  static const String magic = '#ZCI1';

  static const int _sepAlias = 0x01;
  static const int _sepAuthor = 0x02;
  static const int _sepAuthorItem = 0x03;
  static const int _sepEntry = 0x0A;
  static final String _sepAliasText = String.fromCharCode(_sepAlias);
  static final String _sepAuthorText = String.fromCharCode(_sepAuthor);

  /// 产生时间，格式 yyyyMMddHHmm（UTC），越大越新
  final int version;

  /// ISO 8601 产生时间（UTC）
  final String generatedAt;
  final int maxId;

  final Int32List _ids;
  final Uint8List _flags;
  final Uint8List _status;
  final Int32List _hot;
  final List<String> _titles;
  final List<String> _authors;
  final String _blob;
  final Int32List _starts;

  int get length => _ids.length;

  DateTime? get generatedTime => DateTime.tryParse(generatedAt)?.toLocal();

  /// 解析 gzip 压缩的索引档
  factory ComicIndex.decodeGzip(List<int> bytes) =>
      ComicIndex.parse(utf8.decode(gzip.decode(bytes)));

  factory ComicIndex.parse(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) {
      throw const FormatException('漫画索引是空的');
    }
    final head = lines.first.split('\t');
    if (head.first != magic) {
      throw FormatException('不支援的漫画索引格式：${head.first}');
    }
    int headInt(int i) => head.length > i ? int.tryParse(head[i]) ?? 0 : 0;
    final version = headInt(1);
    final generatedAt = head.length > 2 ? head[2] : '';
    final declared = head.length > 3 ? int.tryParse(head[3]) : null;

    final capacity = lines.length - 1;
    final ids = Int32List(capacity);
    final flags = Uint8List(capacity);
    final status = Uint8List(capacity);
    final hot = Int32List(capacity);
    final titles = List<String>.filled(capacity, '');
    final authors = List<String>.filled(capacity, '');
    final starts = Int32List(capacity + 1);
    final blob = StringBuffer();

    var count = 0;
    var lastId = 0;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final f = line.split('\t');
      final id = int.tryParse(f[0]) ?? 0;
      if (id <= lastId || f.length < 2) {
        throw FormatException('漫画索引第 ${i + 1} 行有误');
      }
      lastId = id;
      int field(int k) => f.length > k ? int.tryParse(f[k]) ?? 0 : 0;
      ids[count] = id;
      titles[count] = f[1];
      authors[count] = f.length > 3 ? f[3] : '';
      flags[count] = field(4);
      status[count] = field(5);
      hot[count] = field(6);

      starts[count] = blob.length;
      blob.write(ComicIndexText.normalize(f[1]));
      if (f.length > 2 && f[2].isNotEmpty) {
        for (final alias in f[2].split('|')) {
          final a = ComicIndexText.normalize(alias);
          if (a.isEmpty) continue;
          blob
            ..writeCharCode(_sepAlias)
            ..write(a);
        }
      }
      blob.writeCharCode(_sepAuthor);
      var firstAuthor = true;
      for (final author in authors[count].split('/')) {
        final a = ComicIndexText.normalize(author);
        if (a.isEmpty) continue;
        if (!firstAuthor) blob.writeCharCode(_sepAuthorItem);
        blob.write(a);
        firstAuthor = false;
      }
      blob.writeCharCode(_sepEntry);
      count++;
    }
    if (declared != null && declared != count) {
      throw FormatException('漫画索引不完整：应有 $declared 部，实际 $count 部');
    }
    starts[count] = blob.length;
    return ComicIndex._(
      version: version,
      generatedAt: generatedAt,
      maxId: lastId,
      ids: Int32List.fromList(Int32List.sublistView(ids, 0, count)),
      flags: Uint8List.fromList(Uint8List.sublistView(flags, 0, count)),
      status: Uint8List.fromList(Uint8List.sublistView(status, 0, count)),
      hot: Int32List.fromList(Int32List.sublistView(hot, 0, count)),
      titles: titles.sublist(0, count),
      authors: authors.sublist(0, count),
      blob: blob.toString(),
      starts: Int32List.fromList(Int32List.sublistView(starts, 0, count + 1)),
    );
  }

  /// 依作品 ID 查一笔（主要给测试与诊断用）
  ComicIndexHit? lookup(int id) {
    var lo = 0, hi = _ids.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = _ids[mid];
      if (v == id) return _hit(mid, 0);
      if (v < id) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  /// 搜索标题、别名与作者；以空白分隔的多个关键字须全部命中。
  /// 结果依比对等级排序，同等级时热度高、较新的在前。
  List<ComicIndexHit> search(String query, {int limit = 300}) {
    final tokens = ComicIndexText.tokens(query);
    if (tokens.isEmpty || _ids.isEmpty) return const [];
    final joined = tokens.join();
    final ordered = [...tokens]..sort((a, b) => b.length.compareTo(a.length));
    final primary = ordered.first;
    final rest = ordered.sublist(1);

    final entries = <int>[];
    final tiers = <int>[];
    var from = 0;
    while (true) {
      final at = _blob.indexOf(primary, from);
      if (at < 0) break;
      final e = _entryAt(at);
      final start = _starts[e];
      final end = _starts[e + 1];
      // 一部作品只看第一个命中位置；标题排在最前面，所以它就是最好的栏位
      from = end;
      if (rest.isNotEmpty) {
        final segment = _blob.substring(start, end);
        if (!rest.every(segment.contains)) continue;
      }
      entries.add(e);
      tiers.add(_tier(start, end, at, primary, joined));
    }

    final order = List<int>.generate(entries.length, (i) => i);
    order.sort((a, b) {
      final byTier = tiers[a] - tiers[b];
      if (byTier != 0) return byTier;
      final byHot = _hot[entries[b]] - _hot[entries[a]];
      if (byHot != 0) return byHot;
      return _ids[entries[b]] - _ids[entries[a]];
    });
    return [
      for (final i in order.take(limit)) _hit(entries[i], tiers[i]),
    ];
  }

  int _tier(int start, int end, int at, String primary, String joined) {
    var titleEnd = start;
    while (titleEnd < end) {
      final c = _blob.codeUnitAt(titleEnd);
      if (c == _sepAlias || c == _sepAuthor) break;
      titleEnd++;
    }
    final authorStart = _blob.indexOf(_sepAuthorText, titleEnd);
    final title = _blob.substring(start, titleEnd);
    if (title == joined) return 0;
    if (titleEnd < authorStart &&
        _blob
            .substring(titleEnd + 1, authorStart)
            .split(_sepAliasText)
            .contains(joined)) {
      return 1;
    }
    if (at < titleEnd) return title.startsWith(primary) ? 2 : 3;
    if (at < authorStart) return 4;
    return 5;
  }

  int _entryAt(int pos) {
    var lo = 0, hi = _ids.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= pos) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  ComicIndexHit _hit(int e, int tier) => ComicIndexHit(
        id: _ids[e],
        title: _titles[e],
        authors: _authors[e],
        flags: _flags[e],
        status: _status[e],
        hot: _hot[e],
        tier: tier,
      );
}

/// 决定哪些本地命中要显示在「官方搜索未收录」区块
abstract final class ComicIndexMerge {
  /// * [remoteIds] 官方搜索已返回的作品
  /// * [remoteComplete] 官方搜索没有下一页了（结果集完整）：此时本地有、官方没有的都算
  /// * [remoteFailed] 官方搜索失败（例如离线）：本地结果全部显示
  ///
  /// 其余情况只显示神隐或 copyright=1 的作品，避免把官方后面几页会出现的作品提前塞进来。
  static List<ComicIndexHit> missingFromRemote(
    List<ComicIndexHit> hits,
    Set<int> remoteIds, {
    required bool remoteComplete,
    bool remoteFailed = false,
  }) =>
      [
        for (final hit in hits)
          if (!remoteIds.contains(hit.id) &&
              (remoteComplete || remoteFailed || hit.likelyUnsearchable))
            hit,
      ];
}
