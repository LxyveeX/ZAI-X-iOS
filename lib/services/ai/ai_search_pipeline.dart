import 'dart:async';

import 'package:dio/dio.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_search_engine.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';

/// AI 搜索取得作品资料的来源（App 里接官方接口与本地索引，测试与诊断可以换掉）
abstract interface class AiSearchBackend {
  /// 依题材等条件列出作品，[page] 从 0 起算；[tag] 为 null 时不限题材
  Future<List<AiWork>> filter(
    AiSearchKind kind,
    AiSearchPlan plan,
    AiTag? tag,
    int page,
  );

  /// 官方搜索，[page] 从 0 起算
  Future<List<AiWork>> search(AiSearchKind kind, String keyword, int page);

  /// 本地漫画索引（含神隐与下架作品），依比对等级与人气排序；
  /// 不支持（例如小说或索引关闭）时回传空清单
  Future<List<AiIndexHit>> index(AiSearchKind kind, String keyword, int limit);

  /// 作品详情：简介、题材、人气
  Future<AiWork> detail(AiSearchKind kind, int id);
}

/// 可以翻页的候选来源（关键词或题材）
class _Source {
  _Source.keyword(this.keyword) : tag = null;
  _Source.filter(this.tag) : keyword = null;

  final String? keyword;
  final AiTag? tag;

  /// 下一页，从 0 起算
  int next = 0;
  bool done = false;
}

/// 一次 AI 搜索的状态：已挑出的作品，以及「找更多作品」需要的候选池
class AiSearchRun {
  AiSearchRun._(this.kind, this.query, this.plan);

  final AiSearchKind kind;
  final String query;
  final AiSearchPlan plan;

  final List<AiCandidateHit> _hits = [];
  final List<_Source> _sources = [];
  final Set<int> _sent = {};
  final List<AiSearchResultItem> _items = [];
  int _pending = 0;
  int _rounds = 0;

  /// 目前为止挑出的作品
  List<AiSearchResultItem> get items => List.unmodifiable(_items);

  /// false：AI 挑选失败，[items] 是依条件排序的候选
  bool reranked = true;

  /// AI 已经读过几部作品
  int get seen => _sent.length;

  /// 还有没有没读过的候选
  bool get hasMore => _pending > 0 || _sources.any((s) => !s.done);
}

/// AI 搜索的流程：理解需求 → 找候选 → 补简介 → 分批挑选
///
/// 送给 AI 的只有使用者的描述，以及候选作品的书名、作者、题材、进度、人气与简介。
class AiSearchPipeline {
  AiSearchPipeline({
    required this.chat,
    required this.backend,
    this.onError,
  });

  final AiJsonChat chat;
  final AiSearchBackend backend;

  /// 个别请求失败时的记录（不会中断搜索）
  final void Function(Object error)? onError;

  static const int _pageSize = 20;

  /// 候选不够一轮时，最多再往下翻几次
  static const int _maxTopUps = 3;

  Future<AiSearchRun> start(
    String query,
    AiSearchKind kind,
    AiTagVocabulary vocab, {
    CancelToken? cancel,
    void Function(String stage)? onStage,
    void Function(AiSearchPlan plan)? onPlan,
  }) async {
    onStage?.call('正在理解你的需求…');
    // 条件与代表作分成两个请求同时送出：AI 输出越长越慢，拆开可以少等几秒
    final titlesFuture = chat
        .completeJson(
          system: AiSearchEngine.titlesSystemPrompt(kind),
          user: query,
          reasoningEffort: 'none',
          cancel: cancel,
        )
        .then<Map<String, dynamic>?>((json) => json, onError: (Object e) {
      // 代表作只是加分项，失败不影响搜索；取消则交给下面的条件请求处理
      if (e is! AiSearchCancelled) onError?.call(e);
      return null;
    });
    final json = await chat.completeJson(
      system: AiSearchEngine.planSystemPrompt(kind, vocab, DateTime.now()),
      user: query,
      // 整理条件不需要推理，关掉可以少等 1～2 秒
      reasoningEffort: 'none',
      cancel: cancel,
    );
    final titles = await titlesFuture;
    _throwIfCancelled(cancel);
    json['titles'] = titles?['titles'] ?? json['titles'];
    var plan = AiSearchEngine.parsePlan(json, vocab);
    if (plan.isEmpty) {
      // AI 没整理出任何条件，就拿原句当关键词搜
      plan = plan.copyWith(keywords: [query]);
    }
    onPlan?.call(plan);
    final run = AiSearchRun._(kind, query, plan);

    onStage?.call('正在寻找候选作品…');
    await _collect(run, cancel);
    await _round(run, cancel, onStage);
    return run;
  }

  /// 再读一批还没看过的候选，回传这次新挑出的作品
  Future<List<AiSearchResultItem>> more(
    AiSearchRun run, {
    CancelToken? cancel,
    void Function(String stage)? onStage,
  }) {
    onStage?.call('正在寻找更多作品…');
    return _round(run, cancel, onStage);
  }

  Future<void> _collect(AiSearchRun run, CancelToken? cancel) async {
    final plan = run.plan;
    for (final keyword in plan.keywords) {
      run._sources.add(_Source.keyword(keyword));
    }
    // 接口只有一个标签位：有题材用题材，没有才用受众
    final slots = plan.themes.isNotEmpty
        ? plan.themes
        : [if (plan.audience != null) plan.audience!];
    for (final tag in slots) {
      run._sources.add(_Source.filter(tag));
    }
    if (slots.isEmpty &&
        plan.hasFilters &&
        plan.titles.isEmpty &&
        plan.keywords.isEmpty) {
      run._sources.add(_Source.filter(null));
    }
    final jobs = <Future<List<AiCandidateHit>> Function()>[
      for (final title in plan.titles) () => _resolveTitle(run.kind, title),
      for (final source in run._sources) () => _fetch(run, source),
    ];
    var failures = 0;
    final results = await _pool(jobs, 6, cancel, onError: (e) {
      failures++;
      onError?.call(e);
    });
    _throwIfCancelled(cancel);
    if (jobs.isNotEmpty && failures == jobs.length) {
      throw AppError('无法取得候选作品，请检查网络后再试');
    }
    for (final list in results) {
      run._hits.addAll(list ?? const []);
    }
  }

  /// 找 AI 点名的作品：先查本地索引（有神隐作品与别名），再查官方搜索；
  /// 只收书名相同或相近的，画集、外传不算
  Future<List<AiCandidateHit>> _resolveTitle(
    AiSearchKind kind,
    String title,
  ) async {
    final hits = <AiCandidateHit>[];
    final ids = <int>{};
    void add(AiWork work, int level) {
      if (hits.length < 2 && ids.add(work.id)) {
        hits.add(AiCandidateHit(work, AiHitSource.title, level == 2 ? 0 : 1));
      }
    }

    var exact = false;
    try {
      for (final hit in await backend.index(kind, title, 8)) {
        final level = hit.tier <= 1
            ? 2
            : AiSearchEngine.titleMatch(title, hit.work.title);
        if (level == 0) continue;
        add(hit.work, level);
        if (level == 2) exact = true;
      }
    } catch (e) {
      onError?.call(e);
    }
    if (exact) return hits;
    try {
      final remote = await backend.search(kind, title, 0);
      for (final work in remote.take(10)) {
        final level =
            AiSearchEngine.titleMatch(title, work.title, aliases: work.aliases);
        if (level > 0) add(work, level);
      }
    } catch (e) {
      if (hits.isEmpty) rethrow;
      onError?.call(e);
    }
    hits.sort((a, b) => a.rank.compareTo(b.rank));
    return hits;
  }

  /// 取某个来源的下一页
  Future<List<AiCandidateHit>> _fetch(AiSearchRun run, _Source source) async {
    final page = source.next++;
    final offset = page * _pageSize;
    final tag = source.tag;
    final keyword = source.keyword;
    try {
      if (keyword == null) {
        final list = await backend.filter(run.kind, run.plan, tag, page);
        if (list.length < _pageSize) source.done = true;
        return [
          for (var i = 0; i < list.length; i++)
            AiCandidateHit(list[i], AiHitSource.filter, offset + i),
        ];
      }
      // 关键词同时查官方搜索与本地索引（索引依人气排序，也找得到神隐作品）
      Object? error;
      Future<List<T>> safe<T>(Future<List<T>> future) async {
        try {
          return await future;
        } catch (e) {
          error = e;
          return <T>[];
        }
      }

      final remoteFuture = safe(backend.search(run.kind, keyword, page));
      final localFuture =
          safe(backend.index(run.kind, keyword, offset + _pageSize));
      final remote = await remoteFuture;
      final local = (await localFuture).skip(offset).toList();
      if (remote.isEmpty && local.isEmpty && error != null) throw error!;
      if (error != null) onError?.call(error!);
      if (remote.length < _pageSize && local.length < _pageSize) {
        source.done = true;
      }
      return [
        for (var i = 0; i < remote.length; i++)
          AiCandidateHit(remote[i], AiHitSource.keyword, offset + i),
        for (var i = 0; i < local.length; i++)
          AiCandidateHit(local[i].work, AiHitSource.keyword, offset + i),
      ];
    } catch (e) {
      source.done = true;
      rethrow;
    }
  }

  Future<List<AiSearchResultItem>> _round(
    AiSearchRun run,
    CancelToken? cancel,
    void Function(String stage)? onStage,
  ) async {
    var ranked = AiSearchEngine.rankCandidates(
      run.plan,
      run._hits,
      exclude: run._sent,
    );
    // 候选不够一轮时，从还有下一页的来源补
    for (var i = 0;
        i < _maxTopUps && ranked.length < AiSearchEngine.roundSize;
        i++) {
      final open = run._sources.where((s) => !s.done).toList();
      if (open.isEmpty) break;
      final results = await _pool(
        [for (final source in open) () => _fetch(run, source)],
        6,
        cancel,
        onError: onError,
      );
      _throwIfCancelled(cancel);
      for (final list in results) {
        run._hits.addAll(list ?? const []);
      }
      ranked = AiSearchEngine.rankCandidates(
        run.plan,
        run._hits,
        exclude: run._sent,
      );
    }
    final picked = ranked.take(AiSearchEngine.roundSize).toList();
    if (picked.isEmpty) {
      run._pending = 0;
      return const [];
    }

    onStage?.call('正在阅读 ${picked.length} 部作品的简介…');
    final works = await _enrich(run.kind, picked, cancel);
    _throwIfCancelled(cancel);

    onStage?.call('正在挑选最符合的作品…');
    final named = {
      for (final hit in run._hits)
        if (hit.source == AiHitSource.title) hit.work.id,
    };
    final batches = AiSearchEngine.splitBatches(works, AiSearchEngine.batchSize);
    final answers = await Future.wait([
      for (final batch in batches) _rerank(run, batch, named, cancel),
    ]);
    _throwIfCancelled(cancel);

    final done = <List<AiSearchResultItem>>[];
    for (var i = 0; i < batches.length; i++) {
      final answer = answers[i];
      // 失败的这批不算读过，留给下一轮
      if (answer == null) continue;
      done.add(answer);
      run._sent.addAll(batches[i].map((e) => e.id));
    }

    List<AiSearchResultItem> items;
    if (done.isNotEmpty) {
      final shown = run._items.map((e) => e.work.id).toSet();
      items = [
        for (final item in AiSearchEngine.mergeBatches(done, preferred: named))
          if (!shown.contains(item.work.id)) item,
      ];
    } else if (run._rounds == 0) {
      // 第一轮就挑选失败：先依条件列出候选，不整个报错
      run.reranked = false;
      run._sent.addAll(works.map((e) => e.id));
      items = [
        for (final work in works.take(AiSearchEngine.maxPicksPerBatch))
          AiSearchResultItem(work: work, reason: '', fit: 1),
      ];
    } else {
      throw AppError('AI 暂时无法挑选，请稍后再试');
    }
    run._items.addAll(items);
    run._rounds++;
    run._pending = AiSearchEngine.rankCandidates(
      run.plan,
      run._hits,
      exclude: run._sent,
    ).length;
    return items;
  }

  /// 一批候选交给 AI 挑选；失败回 null（取消会往外丢）
  Future<List<AiSearchResultItem>?> _rerank(
    AiSearchRun run,
    List<AiWork> batch,
    Set<int> named,
    CancelToken? cancel,
  ) async {
    try {
      final json = await chat.completeJson(
        system: AiSearchEngine.rerankSystemPrompt(run.kind),
        user: AiSearchEngine.rerankUserPrompt(
          run.query,
          run.plan,
          batch,
          named: named,
        ),
        // 挑选要判断「不要太虐」这类条件，留一点推理
        reasoningEffort: 'low',
        cancel: cancel,
      );
      return AiSearchEngine.parseRerank(json, batch);
    } on AiSearchCancelled {
      rethrow;
    } catch (e) {
      onError?.call(e);
      return null;
    }
  }

  /// 向详情接口补上简介、题材与人气（同时最多 8 个请求）；失败的保留原资料
  Future<List<AiWork>> _enrich(
    AiSearchKind kind,
    List<AiWork> works,
    CancelToken? cancel,
  ) async {
    final details = await _pool(
      [for (final work in works) () => backend.detail(kind, work.id)],
      8,
      cancel,
      onError: onError,
    );
    return [
      for (var i = 0; i < works.length; i++)
        details[i] == null ? works[i] : works[i].mergedWith(details[i]!),
    ];
  }

  static void _throwIfCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const AiSearchCancelled();
  }

  /// 同时执行最多 [concurrency] 个工作，结果依原顺序；失败的回 null
  static Future<List<T?>> _pool<T>(
    List<Future<T> Function()> jobs,
    int concurrency,
    CancelToken? cancel, {
    void Function(Object error)? onError,
  }) async {
    final results = List<T?>.filled(jobs.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < jobs.length && !(cancel?.isCancelled ?? false)) {
        final index = next++;
        try {
          results[index] = await jobs[index]();
        } catch (e) {
          onError?.call(e);
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < jobs.length; i++) worker(),
    ]);
    return results;
  }
}
