import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';

String _index(List<String> rows, {int? count}) =>
    '#ZCI1\t202609290000\t2026-09-29T00:00:00Z\t${count ?? rows.length}\t0\n'
    '${rows.join('\n')}\n';

void main() {
  group('ComicIndexText.normalize', () {
    test('繁简、全形、大小写与标点都会对齐', () {
      expect(ComicIndexText.normalize('汙穢不堪的你最可愛了'),
          ComicIndexText.normalize('污秽不堪的你最可爱了'));
      expect(ComicIndexText.normalize('頭髮乾燥'), '头发干燥');
      expect(ComicIndexText.normalize('什麼'), ComicIndexText.normalize('什么'));
      expect(ComicIndexText.normalize('ＡＢＣ　ｄｅｆ'), 'abcdef');
      expect(ComicIndexText.normalize('Re:ゼロ・から'), 'reゼロから');
      expect(ComicIndexText.normalize('海贼王剧场版 红发歌姬'), '海贼王剧场版红发歌姬');
      expect(ComicIndexText.normalize('時々'), '时々');
    });

    test('以空白拆成多个关键字', () {
      expect(ComicIndexText.tokens(' 海賊王　紅髮 '), ['海贼王', '红发']);
      expect(ComicIndexText.tokens('   '), isEmpty);
    });
  });

  group('ComicIndex', () {
    final index = ComicIndex.parse(_index([
      '4\t海贼王\t海盗王|OP|航海王\t尾田栄一郎\t25\t1\t3300',
      '10\t海贼王同人集\t\t某人\t4\t2\t10',
      '20\t坂田银时似乎想成为海贼王的样子\t\t作者甲\t0\t1\t500',
      '30\t别的作品\tOP 特别篇\t作者乙\t0\t1\t9000',
      '40\t随便一本\t\t海贼王研究会\t0\t2\t99999',
      '48894\t污秽不堪的你最可爱了\tきたない君がいちばんかわいい\tまにお\t9\t2\t42592',
    ]));

    test('依标题、别名、作者比对并排序', () {
      final hits = index.search('海賊王');
      expect(hits.map((e) => e.id).toList(), [4, 10, 20, 40]);
      expect(hits.map((e) => e.tier).toList(), [0, 2, 3, 5]);
    });

    test('别名完全相同排在标题包含之前', () {
      final hits = index.search('op');
      expect(hits.first.id, 4);
      expect(hits.first.tier, 1);
      expect(hits.map((e) => e.id), contains(30));
    });

    test('多个关键字须全部命中', () {
      expect(index.search('海贼王 样子').map((e) => e.id).toList(), [20]);
      expect(index.search('海贼王 不存在'), isEmpty);
    });

    test('日文原名与作者也能找到', () {
      expect(index.search('きたない君').single.id, 48894);
      expect(index.search('まにお').single.tier, 5);
    });

    test('lookup 与旗标', () {
      final hit = index.lookup(48894)!;
      expect(hit.isHidden, isTrue);
      expect(hit.likelyUnsearchable, isTrue);
      expect(index.lookup(20)!.likelyUnsearchable, isFalse);
      expect(index.lookup(10)!.likelyUnsearchable, isTrue);
      expect(index.lookup(5), isNull);
    });

    test('格式不对或笔数不符就拒绝', () {
      expect(() => ComicIndex.parse('hello\n1\ta\n'), throwsFormatException);
      expect(() => ComicIndex.parse(_index(['1\ta\t\t\t0\t0\t0'], count: 2)),
          throwsFormatException);
      expect(
          () => ComicIndex.parse(
              _index(['2\tb\t\t\t0\t0\t0', '1\ta\t\t\t0\t0\t0'])),
          throwsFormatException);
    });
  });

  group('ComicIndexMerge', () {
    ComicIndexHit hit(int id, int flags) => ComicIndexHit(
        id: id,
        title: '$id',
        authors: '',
        flags: flags,
        status: 0,
        hot: 0,
        tier: 0);
    final hits = [hit(1, 1), hit(2, 0), hit(3, 4), hit(4, 0)];

    test('官方结果还有下一页时只补神隐与版权作品', () {
      final result =
          ComicIndexMerge.missingFromRemote(hits, {3}, remoteComplete: false);
      expect(result.map((e) => e.id).toList(), [1]);
    });

    test('官方结果已完整时，本地有、官方没有的都补上', () {
      final result =
          ComicIndexMerge.missingFromRemote(hits, {2}, remoteComplete: true);
      expect(result.map((e) => e.id).toList(), [1, 3, 4]);
    });

    test('官方搜索失败时全部显示', () {
      final result = ComicIndexMerge.missingFromRemote(hits, const {},
          remoteComplete: false, remoteFailed: true);
      expect(result.length, 4);
    });
  });

  group('内建索引档', () {
    final file = File('assets/comic_index/comic_index.tsv.gz');
    final meta = jsonDecode(
        File('assets/comic_index/comic_index.json').readAsStringSync()) as Map;
    late final ComicIndex index;

    setUpAll(() {
      final watch = Stopwatch()..start();
      index = ComicIndex.decodeGzip(file.readAsBytesSync());
      // ignore: avoid_print
      print('解析 ${index.length} 部耗时 ${watch.elapsedMilliseconds} ms');
    });

    test('与 meta 一致', () {
      expect(index.length, meta['count']);
      expect(index.version, meta['version']);
      expect(index.length, greaterThan(50000));
    });

    test('issue #1 的例子与热门神隐作品都能找到', () {
      expect(index.search('污秽不堪的你最可爱了').first.id, 48894);
      expect(index.search('汙穢不堪的你最可愛了').first.id, 48894);
      final partial = index.search('污秽不堪').map((e) => e.id);
      expect(partial, containsAll([48894, 83748]));
      expect(index.search('海賊王').first.id, 4);
      expect(index.lookup(4)!.isHidden, isTrue);
      expect(index.search('進擊的巨人').first.title, contains('进击的巨人'));
    });

    test('搜索速度', () {
      final watch = Stopwatch()..start();
      for (final q in ['的', '恋爱', '海贼王', 'a', '魔法少女']) {
        index.search(q);
      }
      // ignore: avoid_print
      print('5 次搜索共 ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsedMilliseconds, lessThan(3000));
    });
  });
}
