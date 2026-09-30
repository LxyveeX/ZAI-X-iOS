import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_search_pipeline.dart';

/// 假 AI：整理需求时回固定条件；挑选时依书名决定 fit（0 表示不挑）
class _FakeChat implements AiJsonChat {
  _FakeChat(this.plan, {int Function(String title)? pick, this.failures = 0})
      : pick = pick ?? ((_) => 2);

  final Map<String, dynamic> plan;
  final int Function(String title) pick;

  /// 前几个挑选请求直接失败
  int failures;
  final List<String> rerankPrompts = [];

  @override
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required String user,
    String? reasoningEffort,
    CancelToken? cancel,
  }) async {
    if (system.contains('搜索助手')) return Map.of(plan);
    if (system.contains('选书助手')) return {'titles': plan['titles']};
    rerankPrompts.add(user);
    if (failures > 0) {
      failures--;
      throw Exception('rerank failed');
    }
    final results = <Map<String, dynamic>>[];
    for (final line in user.split('\n')) {
      final m = RegExp(r'^(\d+)\|([^|]*)\|').firstMatch(line);
      if (m == null) continue;
      final fit = pick(m.group(2)!.replaceFirst('★', ''));
      if (fit > 0) {
        results.add({'n': int.parse(m.group(1)!), 'fit': fit, 'reason': '理由'});
      }
    }
    return {'results': results};
  }
}

class _FakeBackend implements AiSearchBackend {
  _FakeBackend({
    this.filterPages = const {},
    this.searchResults = const {},
    this.indexResults = const {},
  });

  /// tagId → 各页作品
  final Map<int?, List<List<AiWork>>> filterPages;
  final Map<String, List<AiWork>> searchResults;
  final Map<String, List<AiIndexHit>> indexResults;
  final List<String> calls = [];

  @override
  Future<List<AiWork>> filter(
    AiSearchKind kind,
    AiSearchPlan plan,
    AiTag? tag,
    int page,
  ) async {
    calls.add('filter:${tag?.id}:$page');
    final pages = filterPages[tag?.id] ?? const [];
    return page < pages.length ? pages[page] : const [];
  }

  @override
  Future<List<AiWork>> search(
    AiSearchKind kind,
    String keyword,
    int page,
  ) async {
    calls.add('search:$keyword:$page');
    return page == 0 ? searchResults[keyword] ?? const [] : const [];
  }

  @override
  Future<List<AiIndexHit>> index(
    AiSearchKind kind,
    String keyword,
    int limit,
  ) async {
    calls.add('index:$keyword');
    return (indexResults[keyword] ?? const []).take(limit).toList();
  }

  @override
  Future<AiWork> detail(AiSearchKind kind, int id) async {
    calls.add('detail:$id');
    return AiWork(id: id, title: '', description: '简介$id');
  }
}

AiWork _w(int id, String title, {List<String> tags = const []}) =>
    AiWork(id: id, title: title, tags: tags);

List<AiWork> _page(int start, int count) => [
      for (var i = 0; i < count; i++)
        _w(start + i, '作品${start + i}', tags: const ['奇幻']),
    ];

Set<String> _titlesIn(String prompt) => {
      for (final line in prompt.split('\n'))
        if (RegExp(r'^\d+\|').hasMatch(line))
          line.split('|')[1].replaceFirst('★', ''),
    };

void main() {
  const fantasy = AiTag(5848, '奇幻');
  const vocab = AiTagVocabulary(themes: [fantasy]);
  const themePlan = {
    'summary': '奇幻',
    'themes': ['奇幻'],
  };

  test('named titles resolve to the main work, not art books or spin-offs',
      () async {
    final backend = _FakeBackend(
      indexResults: {
        '葬送的芙莉莲': [
          AiIndexHit(_w(1, '葬送的芙莉莲'), 0),
          AiIndexHit(_w(2, '葬送的芙莉莲 作品集 ~享受各种旅行的魔法~'), 2),
        ],
      },
      searchResults: {
        '迷宫饭': [_w(3, '妖精拼盘'), _w(4, '迷宫饭 公式导览')],
      },
      filterPages: {
        fantasy.id: [_page(10, 20), _page(30, 10)],
      },
    );
    final chat = _FakeChat(
      {
        ...themePlan,
        'titles': ['葬送的芙莉莲', '迷宫饭'],
      },
      pick: (title) => title == '葬送的芙莉莲' ? 2 : 1,
    );
    final pipeline = AiSearchPipeline(chat: chat, backend: backend);
    final run = await pipeline.start('女主很强的奇幻冒险', AiSearchKind.comic, vocab);

    final sent = chat.rerankPrompts.expand(_titlesIn).toSet();
    expect(sent, contains('葬送的芙莉莲'));
    // AI 点名的作品在挑选时会加上 ★
    expect(chat.rerankPrompts.join('\n'), contains('|★葬送的芙莉莲|'));
    expect(sent.any((t) => t.contains('作品集')), isFalse);
    expect(sent, isNot(contains('妖精拼盘')));
    expect(sent, isNot(contains('迷宫饭 公式导览')));
    // 本地索引已找到本传，就不再查官方搜索
    expect(backend.calls, isNot(contains('search:葬送的芙莉莲:0')));

    expect(run.items.first.work.id, 1);
    expect(run.items.first.likely, isFalse);
    expect(run.items.skip(1).every((e) => e.likely), isTrue);
    expect(run.seen, 31);
    expect(run.hasMore, isFalse);
  });

  test('find more reads further pages and never re-sends judged works',
      () async {
    final backend = _FakeBackend(filterPages: {
      fantasy.id: [for (var p = 0; p < 5; p++) _page(100 + p * 20, 20)],
    });
    final chat = _FakeChat(themePlan);
    final pipeline = AiSearchPipeline(chat: chat, backend: backend);
    final run = await pipeline.start('奇幻', AiSearchKind.comic, vocab);
    expect(run.seen, 45);
    // 每批最多挑 10 部：3 批共 30 部
    expect(run.items.length, 30);
    expect(run.hasMore, isTrue);
    final firstRound = chat.rerankPrompts.expand(_titlesIn).toSet();
    chat.rerankPrompts.clear();

    final more = await pipeline.more(run);
    final secondRound = chat.rerankPrompts.expand(_titlesIn).toSet();
    expect(more, isNotEmpty);
    expect(firstRound.intersection(secondRound), isEmpty);
    expect(backend.calls, contains('filter:${fantasy.id}:3'));
    expect(run.seen, 90);
    expect(run.items.length, 60);
    expect(run.hasMore, isTrue);
  });

  test('a failed batch is not counted as read and returns next round',
      () async {
    final backend = _FakeBackend(filterPages: {
      fantasy.id: [for (var p = 0; p < 3; p++) _page(100 + p * 20, 20)],
    });
    final chat = _FakeChat(themePlan, failures: 1);
    final pipeline = AiSearchPipeline(chat: chat, backend: backend);
    final run = await pipeline.start('奇幻', AiSearchKind.comic, vocab);
    final failed = _titlesIn(chat.rerankPrompts.first);
    expect(run.seen, 30);
    expect(run.reranked, isTrue);
    expect(run.hasMore, isTrue);
    chat.rerankPrompts.clear();

    await pipeline.more(run);
    final retried = chat.rerankPrompts.expand(_titlesIn).toSet();
    expect(retried.containsAll(failed), isTrue);
    expect(run.seen, 60);
    expect(run.hasMore, isFalse);
  });

  test('if every batch fails at first, candidates are listed without picks',
      () async {
    final backend = _FakeBackend(filterPages: {
      fantasy.id: [_page(100, 20)],
    });
    final chat = _FakeChat(themePlan, failures: 99);
    final pipeline = AiSearchPipeline(chat: chat, backend: backend);
    final run = await pipeline.start('奇幻', AiSearchKind.comic, vocab);
    expect(run.reranked, isFalse);
    expect(run.items.length, 10);
    expect(run.items.every((e) => e.reason.isEmpty && e.likely), isTrue);
    expect(run.hasMore, isFalse);
  });

  test('when nothing is understood the sentence itself is searched', () async {
    const query = '某本书';
    final backend = _FakeBackend(searchResults: {
      query: [_w(7, '某本书')],
    });
    final chat = _FakeChat(const {});
    final pipeline = AiSearchPipeline(chat: chat, backend: backend);
    final run = await pipeline.start(query, AiSearchKind.novel, vocab);
    expect(backend.calls, contains('search:$query:0'));
    expect(run.items.map((e) => e.work.id), [7]);
    expect(run.items.single.work.description, '简介7');
  });
}
