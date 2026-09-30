import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_search_engine.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';

void main() {
  const vocab = AiTagVocabulary(
    themes: [
      AiTag(1, '校园'),
      AiTag(2, '爱情'),
      AiTag(3, '惊悚'),
      AiTag(4, '冒险'),
      AiTag(5, '奇幻'),
      AiTag(6, 'ゆり'),
    ],
    audiences: [AiTag(3262, '少年漫'), AiTag(3263, '少女漫')],
    zones: [AiTag(2304, '日本'), AiTag(2305, '韩国')],
    statuses: [AiTag(2309, '连载'), AiTag(2310, '完结')],
  );

  AiWork work(int id, List<String> tags, {String status = ''}) =>
      AiWork(id: id, title: '作品$id', tags: tags, status: status);

  group('AI reply parsing', () {
    test('accepts plain, fenced and wrapped JSON objects', () {
      expect(AiChatClient.decodeJsonObject('{"a":1}'), {'a': 1});
      expect(
        AiChatClient.decodeJsonObject('```json\n{"a":2}\n```'),
        {'a': 2},
      );
      expect(AiChatClient.decodeJsonObject('好的：{"a":3} 以上'), {'a': 3});
    });

    test('rejects replies without an object', () {
      expect(AiChatClient.decodeJsonObject(''), isNull);
      expect(AiChatClient.decodeJsonObject('[1,2]'), isNull);
      expect(AiChatClient.decodeJsonObject('抱歉，无法回答'), isNull);
    });

    test('reads message content from chat completions', () {
      expect(
        AiChatClient.contentOf({
          'choices': [
            {
              'message': {'content': '{"ok":true}'},
            },
          ],
        }),
        '{"ok":true}',
      );
      expect(
        AiChatClient.contentOf({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': '{"a"'},
                  {'type': 'text', 'text': ':1}'},
                ],
              },
            },
          ],
        }),
        '{"a":1}',
      );
      expect(AiChatClient.contentOf({'error': 'x'}), isNull);
    });
  });

  group('plan', () {
    test('maps names to tags and tolerates traditional characters', () {
      final plan = AiSearchEngine.parsePlan({
        'summary': '校园恋爱，已完结',
        'themes': ['校園', '爱情', '不存在的题材', '冒险', '奇幻'],
        'exclude_themes': ['驚悚', '校园'],
        'audience': '少女漫',
        'zone': '',
        'status': '已完結',
        'titles': ['辉夜大小姐想让我告白', '輝夜大小姐想讓我告白'],
        'keywords': '辉夜, 赤坂明',
        'sort': 'NEW',
      }, vocab);
      expect(plan.themes.map((e) => e.id), [1, 2, 4]);
      expect(plan.excludeThemes.map((e) => e.id), [3]);
      expect(plan.audience?.id, 3263);
      expect(plan.zone, isNull);
      expect(plan.status?.id, 2310);
      expect(plan.titles, ['辉夜大小姐想让我告白']);
      expect(plan.keywords, ['辉夜', '赤坂明']);
      expect(plan.preferNew, isTrue);
      expect(plan.conditions, ['校园、爱情、冒险', '少女漫', '完结', '不要：惊悚']);
    });

    test('keeps up to ten titles', () {
      final plan = AiSearchEngine.parsePlan({
        'titles': [for (var i = 0; i < 14; i++) '书$i'],
      }, vocab);
      expect(plan.titles.length, AiSearchEngine.maxTitles);
    });

    test('ambiguous or too short names are ignored', () {
      const tags = [AiTag(1, '爱情'), AiTag(2, '纯爱')];
      expect(AiSearchEngine.matchTag('爱', tags), isNull);
      expect(AiSearchEngine.matchTag('纯爱', tags)?.id, 2);
      expect(AiSearchEngine.matchTag('ゆり', vocab.themes)?.id, 6);
    });

    test('garbage fields give an empty plan', () {
      final plan =
          AiSearchEngine.parsePlan({'themes': 3, 'titles': null}, vocab);
      expect(plan.isEmpty, isTrue);
      expect(plan.copyWith(keywords: ['原句']).keywords, ['原句']);
    });

    test('prompt lists the tags and asks for many representative titles', () {
      final prompt = AiSearchEngine.planSystemPrompt(
        AiSearchKind.comic,
        vocab,
        DateTime(2026, 9, 30),
      );
      expect(prompt, contains('2026-09-30'));
      expect(prompt, contains('题材：校园、爱情、惊悚、冒险、奇幻、ゆり'));
      expect(prompt, contains('进度：连载、完结'));
      expect(prompt, contains('不是主角的性别'));
      expect(prompt, isNot(contains('"titles"')));
      final titles = AiSearchEngine.titlesSystemPrompt(AiSearchKind.comic);
      expect(titles, contains('8～10'));
      expect(titles, contains('{"titles":["书名"]}'));
      final novel = AiSearchEngine.planSystemPrompt(
        AiSearchKind.novel,
        const AiTagVocabulary(themes: [AiTag(1, '魔法')]),
        DateTime(2026, 9, 30),
      );
      expect(novel, contains('轻小说搜索助手'));
      expect(novel, isNot(contains('"zone"')));
    });
  });

  group('title match', () {
    test('same title or alias is exact', () {
      expect(AiSearchEngine.titleMatch('葬送的芙莉莲', '葬送的芙莉蓮'), 2);
      expect(AiSearchEngine.titleMatch('为美好的世界献上祝福', '为美好的世界献上祝福！'), 2);
      expect(
        AiSearchEngine.titleMatch('不过是蜘蛛什么的', '转生成蜘蛛又怎样',
            aliases: ['不过是蜘蛛什么的']),
        2,
      );
    });

    test('a few extra characters is close', () {
      expect(AiSearchEngine.titleMatch('咒术回战', '咒术回战 0'), 1);
      expect(AiSearchEngine.titleMatch('关于我转生变成史莱姆这档事 第二部', '关于我转生变成史莱姆这档事'), 1);
    });

    test('art books, spin-offs and other works do not count', () {
      expect(AiSearchEngine.titleMatch('葬送的芙莉莲', '葬送的芙莉莲 作品集 ~享受各种旅行的魔法~'), 0);
      expect(AiSearchEngine.titleMatch('迷宫饭', '迷宫饭 公式导览'), 0);
      expect(AiSearchEngine.titleMatch('迷宫饭', '妖精拼盘'), 0);
      expect(AiSearchEngine.titleMatch('', '迷宫饭'), 0);
    });
  });

  group('candidates', () {
    test('drop unwanted themes and prefer matching ones', () {
      const plan = AiSearchPlan(
        themes: [AiTag(1, '校园'), AiTag(2, '爱情')],
        excludeThemes: [AiTag(3, '惊悚')],
        status: AiTag(2310, '完结'),
      );
      final ranked = AiSearchEngine.rankCandidates(plan, [
        AiCandidateHit(work(1, ['校园']), AiHitSource.filter, 0),
        AiCandidateHit(
            work(2, ['校园', '爱情'], status: '已完结'), AiHitSource.filter, 5),
        AiCandidateHit(work(3, ['校园', '惊悚']), AiHitSource.filter, 1),
        AiCandidateHit(
            work(4, ['爱情', '校园'], status: '连载中'), AiHitSource.filter, 2),
        AiCandidateHit(work(5, ['冒险']), AiHitSource.filter, 3),
      ]);
      expect(ranked.map((e) => e.id), [2, 1, 4, 5]);
    });

    test('merge duplicates and let named titles float up', () {
      const plan = AiSearchPlan(titles: ['作品9']);
      final ranked = AiSearchEngine.rankCandidates(plan, [
        AiCandidateHit(work(8, []), AiHitSource.keyword, 0),
        AiCandidateHit(
          AiWork(id: 9, title: '作品9', cover: 'a.jpg'),
          AiHitSource.filter,
          30,
        ),
        AiCandidateHit(
          AiWork(id: 9, title: '作品9', tags: const ['奇幻']),
          AiHitSource.title,
          0,
        ),
        AiCandidateHit(work(0, []), AiHitSource.title, 0),
      ]);
      expect(ranked.map((e) => e.id), [9, 8]);
      expect(ranked.first.cover, 'a.jpg');
      expect(ranked.first.tags, ['奇幻']);
    });

    test('keyword and theme lists interleave, judged works are skipped', () {
      const plan = AiSearchPlan(themes: [AiTag(5, '奇幻')]);
      final hits = [
        for (var i = 0; i < 5; i++)
          AiCandidateHit(work(100 + i, []), AiHitSource.keyword, i),
        for (var i = 0; i < 5; i++)
          AiCandidateHit(work(200 + i, ['奇幻']), AiHitSource.filter, i),
      ];
      final ranked = AiSearchEngine.rankCandidates(plan, hits);
      expect(ranked.take(4).map((e) => e.id), [100, 200, 101, 201]);
      final rest = AiSearchEngine.rankCandidates(
        plan,
        hits,
        exclude: {200, 100},
        limit: 3,
      );
      expect(rest.map((e) => e.id), [101, 201, 102]);
    });

    test('batches interleave so each gets strong and weak candidates', () {
      final batches =
          AiSearchEngine.splitBatches([for (var i = 0; i < 7; i++) i], 3);
      expect(batches, [
        [0, 3, 6],
        [1, 4],
        [2, 5],
      ]);
      expect(AiSearchEngine.splitBatches(<int>[], 3), isEmpty);
    });
  });

  group('rerank', () {
    final candidates = [
      AiWork(
        id: 11,
        title: '甲|乙',
        authors: '作者A',
        tags: const ['校园'],
        status: '已完结',
        description: '<p>第一行\n第二行</p>',
        hot: 64457,
      ),
      AiWork(id: 12, title: '丙', description: '很长' * 100),
      AiWork(id: 13, title: '丁'),
    ];

    test('prompt puts each numbered candidate on one line', () {
      final prompt = AiSearchEngine.rerankUserPrompt(
        '想看校园',
        const AiSearchPlan(summary: '校园'),
        candidates,
        named: {13},
      );
      expect(prompt, contains('1|甲/乙|作者A|校园|已完结|6.4万|第一行 第二行'));
      expect(prompt, contains('3|★丁|'));
      final second =
          prompt.split('\n').where((line) => line.startsWith('2|')).single;
      expect(second, startsWith('2|丙|||||'));
      expect(second.length, lessThan(170));
    });

    test('map numbers back, read fit and skip invalid entries', () {
      final items = AiSearchEngine.parseRerank({
        'results': [
          {'n': 3, 'fit': 1, 'reason': '理由三'},
          {'n': '1', 'reason': '理由一'},
          {'n': 3, 'reason': '重复'},
          {'n': 9, 'reason': '超出'},
          {'n': 0},
          'x',
        ],
      }, candidates);
      expect(items.map((e) => e.work.id), [13, 11]);
      expect(items.first.reason, '理由三');
      expect(items.first.likely, isTrue);
      expect(items.last.fit, 2);
    });

    test('missing results means nothing matched', () {
      expect(AiSearchEngine.parseRerank({'foo': 1}, candidates), isEmpty);
    });

    test('batches merge by fit, then by position across batches', () {
      AiSearchResultItem item(int id, int fit) =>
          AiSearchResultItem(work: work(id, []), reason: '', fit: fit);
      final merged = AiSearchEngine.mergeBatches([
        [item(1, 2), item(2, 1), item(3, 2)],
        [item(4, 2), item(5, 1), item(1, 2)],
      ]);
      expect(merged.map((e) => e.work.id), [1, 4, 3, 2, 5]);
      final preferred = AiSearchEngine.mergeBatches([
        [item(1, 2), item(2, 1), item(3, 2)],
        [item(4, 2), item(5, 1)],
      ], preferred: {3, 5});
      expect(preferred.map((e) => e.work.id), [3, 1, 4, 5, 2]);
    });
  });

  test('popularity is written short', () {
    expect(AiSearchEngine.formatHot(0), '');
    expect(AiSearchEngine.formatHot(9876), '9876');
    expect(AiSearchEngine.formatHot(64457), '6.4万');
    expect(AiSearchEngine.formatHot(120000), '12万');
    expect(AiSearchEngine.formatHot(250000000), '2.5亿');
  });

  test('daily quota counts per day and resets the next day', () {
    var stored = '';
    final day = DateTime(2026, 9, 30, 10);
    for (var i = 0; i < 3; i++) {
      final result = AiSearchEngine.consumeQuota(stored, day, limit: 3);
      expect(result.allowed, isTrue);
      stored = result.stored;
    }
    expect(stored, '2026-09-30|3');
    final blocked = AiSearchEngine.consumeQuota(stored, day, limit: 3);
    expect(blocked.allowed, isFalse);
    final tomorrow = AiSearchEngine.consumeQuota(
      blocked.stored,
      DateTime(2026, 10, 1, 0, 5),
      limit: 3,
    );
    expect(tomorrow.allowed, isTrue);
    expect(tomorrow.stored, '2026-10-01|1');
    expect(AiSearchEngine.consumeQuota('乱码', day).allowed, isTrue);
  });

  test('keywords sent to search are simplified without other changes', () {
    expect(
      ComicIndexText.toSimplified('進擊的巨人 Attack'),
      '进击的巨人 Attack',
    );
  });
}
