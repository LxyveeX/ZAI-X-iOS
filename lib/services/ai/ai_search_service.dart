import 'dart:async';

import 'package:dio/dio.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/models/comic/comic_tag_table.g.dart';
import 'package:zai_x/requests/comic_request.dart';
import 'package:zai_x/requests/novel_request.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_search_engine.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_service_config.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';
import 'package:zai_x/services/comic_index/comic_index_service.dart';
import 'package:zai_x/services/local_storage_service.dart';

/// AI 搜索：理解描述 → 站内找候选 → 读简介挑选
///
/// 送给 AI 的只有使用者的描述，以及候选作品的书名、作者、题材、进度与简介。
class AiSearchService {
  AiSearchService._(AiServiceConfig? config)
      : _client = config == null ? null : AiChatClient(config);

  static final AiSearchService instance =
      AiSearchService._(AiServiceConfig.current);

  final AiChatClient? _client;
  final ComicRequest _comic = ComicRequest();
  final NovelRequest _novel = NovelRequest();

  /// 这个建置有没有内建 AI 服务
  bool get available => _client != null;

  final Map<AiSearchKind, AiTagVocabulary> _vocabularies = {};
  final Map<String, AiWork> _details = {};
  final Map<String, (DateTime, AiSearchOutcome)> _recent = {};

  static const int _detailCacheSize = 300;
  static const int _recentCacheSize = 20;
  static const Duration _recentTtl = Duration(minutes: 30);

  Future<AiSearchOutcome> search(
    String query,
    AiSearchKind kind, {
    CancelToken? cancel,
    void Function(String stage)? onStage,
    void Function(AiSearchPlan plan)? onPlan,
  }) async {
    final client = _client;
    if (client == null) {
      throw AppError('这个版本没有内建 AI 服务');
    }
    final text = query.trim();
    final input = text.length > AiSearchEngine.queryLimit
        ? text.substring(0, AiSearchEngine.queryLimit)
        : text;
    // 同一段描述半小时内直接用上次的结果，不再花一次额度
    final cacheKey = '${kind.name}|${ComicIndexText.normalize(input)}';
    final cached = _recent[cacheKey];
    if (cached != null && DateTime.now().difference(cached.$1) < _recentTtl) {
      onPlan?.call(cached.$2.plan);
      return cached.$2;
    }
    await _consumeQuota();

    onStage?.call('正在理解你的需求…');
    final vocab = await _vocabulary(kind);
    _throwIfCancelled(cancel);
    final planJson = await client.completeJson(
      system: AiSearchEngine.planSystemPrompt(kind, vocab, DateTime.now()),
      user: input,
      // 整理条件不需要推理，关掉可以少等 1～2 秒
      reasoningEffort: 'none',
      cancel: cancel,
    );
    var plan = AiSearchEngine.parsePlan(planJson, vocab);
    if (plan.isEmpty) {
      // AI 没整理出任何条件，就拿原句当关键词搜
      plan = plan.copyWith(keywords: [input]);
    }
    onPlan?.call(plan);

    onStage?.call('正在寻找候选作品…');
    final hits = await _collect(kind, plan, cancel);
    _throwIfCancelled(cancel);
    final candidates = AiSearchEngine.rankCandidates(plan, hits);
    if (candidates.isEmpty) {
      final outcome = AiSearchOutcome(plan: plan, items: const []);
      _remember(cacheKey, outcome);
      return outcome;
    }

    onStage?.call('正在阅读 ${candidates.length} 部作品的简介…');
    final works = await _enrich(kind, candidates, cancel);
    _throwIfCancelled(cancel);

    onStage?.call('正在挑选最符合的作品…');
    try {
      final json = await client.completeJson(
        system: AiSearchEngine.rerankSystemPrompt(kind),
        user: AiSearchEngine.rerankUserPrompt(input, plan, works),
        // 挑选要判断「不要太虐」这类条件，留一点推理
        reasoningEffort: 'low',
        cancel: cancel,
      );
      final outcome = AiSearchOutcome(
        plan: plan,
        items: AiSearchEngine.parseRerank(json, works),
        candidateCount: works.length,
      );
      _remember(cacheKey, outcome);
      return outcome;
    } on AiSearchCancelled {
      rethrow;
    } catch (e) {
      // 挑选失败时仍列出依条件排序的候选，不整个报错
      Log.logPrint(e);
      return AiSearchOutcome(
        plan: plan,
        items: [
          for (final work in works.take(AiSearchEngine.maxResults))
            AiSearchResultItem(work: work, reason: ''),
        ],
        reranked: false,
        candidateCount: works.length,
      );
    }
  }

  Future<void> _consumeQuota() async {
    final storage = LocalStorageService.instance;
    final value = storage.getValue<dynamic>(
      LocalStorageService.kAiSearchQuota,
      '',
    );
    final result = AiSearchEngine.consumeQuota(
      value is String ? value : '',
      DateTime.now(),
    );
    await storage.setValue(LocalStorageService.kAiSearchQuota, result.stored);
    if (!result.allowed) {
      throw AppError(
        '今天的 AI 搜索次数已用完（每天 ${AiSearchEngine.dailyLimit} 次），明天再来吧',
      );
    }
  }

  Future<AiTagVocabulary> _vocabulary(AiSearchKind kind) async {
    final cached = _vocabularies[kind];
    if (cached != null) return cached;
    if (kind == AiSearchKind.comic) {
      // 服务端失败时 categoryFilter 会用本地标签表补齐，不会丢例外
      final groups = await _comic.categoryFilter();
      List<AiTag> pick(int dimension) => [
            for (final group in groups)
              if (group.dimension == dimension)
                for (final item in group.items)
                  if (item.tagId != 0) AiTag(item.tagId, item.tagName),
          ];
      return _vocabularies[kind] = AiTagVocabulary(
        themes: pick(ComicTagDimension.theme),
        audiences: pick(ComicTagDimension.audience),
        zones: pick(ComicTagDimension.zone),
        statuses: pick(ComicTagDimension.status),
      );
    }
    try {
      final groups = await _novel.categoryFilter();
      return _vocabularies[kind] = AiTagVocabulary(themes: [
        for (final group in groups)
          for (final item in group.items)
            if (item.tagId != 0) AiTag(item.tagId, item.tagName),
      ]);
    } catch (e) {
      // 拿不到小说分类时只靠书名与关键词，下次再试
      Log.logPrint(e);
      return const AiTagVocabulary();
    }
  }

  Future<List<AiCandidateHit>> _collect(
    AiSearchKind kind,
    AiSearchPlan plan,
    CancelToken? cancel,
  ) async {
    final jobs = <Future<List<AiCandidateHit>> Function()>[];
    // 接口只有一个标签位：有题材用题材，没有才用受众
    final slots = plan.themes.isNotEmpty
        ? plan.themes
        : [if (plan.audience != null) plan.audience!];
    for (final tag in slots) {
      jobs.add(() => _byFilter(kind, tag, plan, 0));
      if (slots.length == 1) jobs.add(() => _byFilter(kind, tag, plan, 1));
    }
    if (slots.isEmpty &&
        plan.hasFilters &&
        plan.titles.isEmpty &&
        plan.keywords.isEmpty) {
      jobs.add(() => _byFilter(kind, null, plan, 0));
    }
    for (final title in plan.titles) {
      jobs.add(() => _bySearch(kind, title, AiHitSource.title, 3));
    }
    for (final keyword in plan.keywords) {
      jobs.add(() => _bySearch(kind, keyword, AiHitSource.keyword, 6));
    }
    if (kind == AiSearchKind.comic && plan.titles.isNotEmpty) {
      jobs.add(() => _byIndex(plan.titles));
    }
    var failures = 0;
    final results = await _pool(jobs, 4, cancel, onError: () => failures++);
    _throwIfCancelled(cancel);
    if (jobs.isNotEmpty && failures == jobs.length) {
      throw AppError('无法取得候选作品，请检查网络后再试');
    }
    return [for (final list in results) ...?list];
  }

  /// 依条件列出作品（热门或最近更新）；[pageIndex] 从 0 起算
  Future<List<AiCandidateHit>> _byFilter(
    AiSearchKind kind,
    AiTag? tag,
    AiSearchPlan plan,
    int pageIndex,
  ) async {
    final offset = pageIndex * 20;
    if (kind == AiSearchKind.comic) {
      final list = await _comic.categoryComic(
        id: tag?.id ?? 0,
        sort: plan.preferNew ? 1 : 2,
        page: pageIndex + 1,
        status: plan.status?.id ?? 0,
        zone: plan.zone?.id ?? 0,
      );
      return [
        for (var i = 0; i < list.length; i++)
          AiCandidateHit(
            AiWork(
              id: list[i].id,
              title: list[i].name,
              authors: list[i].authors ?? '',
              tags: AiWork.splitTags(list[i].types),
              status: list[i].status ?? '',
              cover: list[i].cover ?? '',
              lastChapter: list[i].lastUpdateChapterName ?? '',
            ),
            AiHitSource.filter,
            offset + i,
          ),
      ];
    }
    // 小说分类接口的页码从 0 开始
    final list = await _novel.categoryNovel(
      cateId: tag?.id ?? 0,
      sort: plan.preferNew ? 1 : 0,
      page: pageIndex,
    );
    return [
      for (var i = 0; i < list.length; i++)
        AiCandidateHit(
          AiWork(
            id: list[i].id,
            title: list[i].title,
            authors: list[i].authors ?? '',
            tags: AiWork.splitTags(list[i].types),
            status: list[i].status ?? '',
            cover: list[i].cover ?? '',
            lastChapter: list[i].lastName ?? '',
          ),
          AiHitSource.filter,
          offset + i,
        ),
    ];
  }

  /// 用书名、作者等关键词走官方搜索，取前 [take] 笔
  Future<List<AiCandidateHit>> _bySearch(
    AiSearchKind kind,
    String keyword,
    AiHitSource source,
    int take,
  ) async {
    final text = ComicIndexText.toSimplified(keyword);
    if (kind == AiSearchKind.comic) {
      final list = await _comic.search(keyword: text, page: 1);
      return [
        for (var i = 0; i < list.length && i < take; i++)
          AiCandidateHit(
            AiWork(
              id: list[i].comicId,
              title: list[i].title,
              authors: list[i].author,
              tags: AiWork.splitTags(list[i].tags),
              cover: list[i].cover,
              lastChapter: list[i].lastChapterName,
            ),
            source,
            i,
          ),
      ];
    }
    final list = await _novel.search(keyword: text, page: 1);
    return [
      for (var i = 0; i < list.length && i < take; i++)
        AiCandidateHit(
          AiWork(
            id: list[i].id,
            title: list[i].title,
            authors: list[i].authors ?? '',
            tags: AiWork.splitTags(list[i].types),
            status: list[i].status ?? '',
            cover: list[i].cover ?? '',
            lastChapter: list[i].lastName ?? '',
          ),
          source,
          i,
        ),
    ];
  }

  /// AI 点名的作品若官方搜索找不到（神隐、下架），再查本地漫画索引，只收书名完全相同的
  Future<List<AiCandidateHit>> _byIndex(List<String> titles) async {
    final service = ComicIndexService.instance;
    if (!service.enabled.value) return const [];
    final hits = <AiCandidateHit>[];
    for (final title in titles) {
      final key = ComicIndexText.normalize(title);
      if (key.isEmpty) continue;
      for (final hit in await service.search(title, limit: 5)) {
        if (ComicIndexText.normalize(hit.title) != key) continue;
        hits.add(AiCandidateHit(
          AiWork(
            id: hit.id,
            title: hit.title,
            authors: hit.authors,
            status: switch (hit.status) {
              1 => '连载中',
              2 => '已完结',
              _ => '',
            },
          ),
          AiHitSource.title,
          0,
        ));
        break;
      }
    }
    return hits;
  }

  /// 向详情接口补上简介、题材与封面（同时最多 5 个请求）
  Future<List<AiWork>> _enrich(
    AiSearchKind kind,
    List<AiWork> works,
    CancelToken? cancel,
  ) async {
    final results = await _pool(
      [for (final work in works) () => _detail(kind, work)],
      5,
      cancel,
    );
    return [
      for (var i = 0; i < works.length; i++) results[i] ?? works[i],
    ];
  }

  Future<AiWork> _detail(AiSearchKind kind, AiWork work) async {
    final key = '${kind.name}:${work.id}';
    var info = _details[key];
    if (info == null) {
      if (kind == AiSearchKind.comic) {
        info = AiWork.fromComicDetail(
          work.id,
          await _comic.comicDetailData(comicId: work.id),
        );
      } else {
        final detail = (await _novel.novelDetail(novelId: work.id)).data;
        info = AiWork(
          id: work.id,
          title: detail.name,
          authors: detail.authors,
          tags: detail.types,
          status: detail.status,
          cover: detail.cover,
          description: detail.introduction,
          lastChapter: detail.lastUpdateChapterName,
        );
      }
      if (_details.length >= _detailCacheSize) {
        _details.remove(_details.keys.first);
      }
      _details[key] = info;
    }
    return work.mergedWith(info);
  }

  void _remember(String key, AiSearchOutcome outcome) {
    if (_recent.length >= _recentCacheSize) _recent.remove(_recent.keys.first);
    _recent[key] = (DateTime.now(), outcome);
  }

  static void _throwIfCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const AiSearchCancelled();
  }

  /// 同时执行最多 [concurrency] 个工作，结果依原顺序；失败的记日志并回 null
  static Future<List<T?>> _pool<T>(
    List<Future<T> Function()> jobs,
    int concurrency,
    CancelToken? cancel, {
    void Function()? onError,
  }) async {
    final results = List<T?>.filled(jobs.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < jobs.length && !(cancel?.isCancelled ?? false)) {
        final index = next++;
        try {
          results[index] = await jobs[index]();
        } catch (e) {
          Log.logPrint(e);
          onError?.call();
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < jobs.length; i++) worker(),
    ]);
    return results;
  }
}
