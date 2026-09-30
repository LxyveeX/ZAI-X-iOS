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
import 'package:zai_x/services/ai/ai_search_pipeline.dart';
import 'package:zai_x/services/ai/ai_service_config.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';
import 'package:zai_x/services/comic_index/comic_index_service.dart';
import 'package:zai_x/services/local_storage_service.dart';

/// App 里的 AI 搜索：每日次数、同一描述的短暂快取，以及官方接口与本地索引的资料来源
class AiSearchService {
  AiSearchService._(AiServiceConfig? config)
      : _pipeline = config == null
            ? null
            : AiSearchPipeline(
                chat: AiChatClient(config),
                backend: _AppSearchBackend(),
                onError: Log.logPrint,
              );

  static final AiSearchService instance =
      AiSearchService._(AiServiceConfig.current);

  final AiSearchPipeline? _pipeline;
  final ComicRequest _comic = ComicRequest();
  final NovelRequest _novel = NovelRequest();

  /// 这个建置有没有内建 AI 服务
  bool get available => _pipeline != null;

  final Map<AiSearchKind, AiTagVocabulary> _vocabularies = {};
  final Map<String, (DateTime, AiSearchRun)> _recent = {};

  static const int _recentCacheSize = 20;
  static const Duration _recentTtl = Duration(minutes: 30);

  Future<AiSearchRun> start(
    String query,
    AiSearchKind kind, {
    CancelToken? cancel,
    void Function(String stage)? onStage,
    void Function(AiSearchPlan plan)? onPlan,
  }) async {
    final pipeline = _pipeline;
    if (pipeline == null) throw AppError('这个版本没有内建 AI 服务');
    final text = query.trim();
    final input = text.length > AiSearchEngine.queryLimit
        ? text.substring(0, AiSearchEngine.queryLimit)
        : text;
    // 同一段描述半小时内沿用上次的结果（含已找到的更多作品），不再花额度
    final key = '${kind.name}|${ComicIndexText.normalize(input)}';
    final cached = _recent[key];
    if (cached != null && DateTime.now().difference(cached.$1) < _recentTtl) {
      onPlan?.call(cached.$2.plan);
      return cached.$2;
    }
    await _consumeQuota();
    final vocab = await _vocabulary(kind);
    if (cancel?.isCancelled ?? false) throw const AiSearchCancelled();
    final run = await pipeline.start(
      input,
      kind,
      vocab,
      cancel: cancel,
      onStage: onStage,
      onPlan: onPlan,
    );
    if (_recent.length >= _recentCacheSize) _recent.remove(_recent.keys.first);
    _recent[key] = (DateTime.now(), run);
    return run;
  }

  /// 再读一批候选；回传新挑出的作品
  Future<List<AiSearchResultItem>> more(
    AiSearchRun run, {
    CancelToken? cancel,
    void Function(String stage)? onStage,
  }) async {
    final pipeline = _pipeline;
    if (pipeline == null) throw AppError('这个版本没有内建 AI 服务');
    await _consumeQuota();
    return pipeline.more(run, cancel: cancel, onStage: onStage);
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
}

/// 官方接口与本地漫画索引
class _AppSearchBackend implements AiSearchBackend {
  final ComicRequest _comic = ComicRequest();
  final NovelRequest _novel = NovelRequest();
  final Map<String, AiWork> _details = {};
  static const int _detailCacheSize = 400;

  @override
  Future<List<AiWork>> filter(
    AiSearchKind kind,
    AiSearchPlan plan,
    AiTag? tag,
    int page,
  ) async {
    if (kind == AiSearchKind.comic) {
      final list = await _comic.categoryComic(
        id: tag?.id ?? 0,
        sort: plan.preferNew ? 1 : 2,
        page: page + 1,
        status: plan.status?.id ?? 0,
        zone: plan.zone?.id ?? 0,
      );
      return [
        for (final e in list)
          AiWork(
            id: e.id,
            title: e.name,
            authors: e.authors ?? '',
            tags: AiWork.splitTags(e.types),
            status: e.status ?? '',
            cover: e.cover ?? '',
            lastChapter: e.lastUpdateChapterName ?? '',
            hot: e.hotNum ?? 0,
          ),
      ];
    }
    // 小说分类接口的页码其实从 1 开始（传 0 与 1 会拿到同一页）
    final list = await _novel.categoryNovel(
      cateId: tag?.id ?? 0,
      sort: plan.preferNew ? 1 : 0,
      page: page + 1,
    );
    return [
      for (final e in list)
        AiWork(
          id: e.id,
          title: e.title,
          authors: e.authors ?? '',
          tags: AiWork.splitTags(e.types),
          status: e.status ?? '',
          cover: e.cover ?? '',
          lastChapter: e.lastName ?? '',
          hot: e.hotHits ?? 0,
        ),
    ];
  }

  @override
  Future<List<AiWork>> search(
    AiSearchKind kind,
    String keyword,
    int page,
  ) async {
    final text = ComicIndexText.toSimplified(keyword);
    if (kind == AiSearchKind.comic) {
      final list = await _comic.searchModels(keyword: text, page: page + 1);
      return [
        for (final e in list)
          AiWork(
            id: e.id,
            title: e.title,
            authors: e.authors ?? '',
            tags: AiWork.splitTags(e.types),
            aliases: AiWork.splitTags(e.aliasName),
            status: e.status ?? '',
            cover: e.cover ?? '',
            lastChapter: e.lastName ?? '',
            hot: e.hotHits ?? 0,
          ),
      ];
    }
    final list = await _novel.search(keyword: text, page: page + 1);
    return [
      for (final e in list)
        AiWork(
          id: e.id,
          title: e.title,
          authors: e.authors ?? '',
          tags: AiWork.splitTags(e.types),
          status: e.status ?? '',
          cover: e.cover ?? '',
          lastChapter: e.lastName ?? '',
          hot: e.hotHits ?? 0,
        ),
    ];
  }

  @override
  Future<List<AiIndexHit>> index(
    AiSearchKind kind,
    String keyword,
    int limit,
  ) async {
    if (kind != AiSearchKind.comic) return const [];
    final hits = await ComicIndexService.instance.search(keyword, limit: limit);
    return [
      for (final hit in hits)
        AiIndexHit(
          AiWork(
            id: hit.id,
            title: hit.title,
            authors: hit.authors,
            status: switch (hit.status) {
              1 => '连载中',
              2 => '已完结',
              _ => '',
            },
            hot: hit.hot,
          ),
          hit.tier,
        ),
    ];
  }

  @override
  Future<AiWork> detail(AiSearchKind kind, int id) async {
    final key = '${kind.name}:$id';
    final cached = _details[key];
    if (cached != null) return cached;
    final AiWork info;
    if (kind == AiSearchKind.comic) {
      info = AiWork.fromComicDetail(
        id,
        await _comic.comicDetailData(comicId: id),
      );
    } else {
      final detail = (await _novel.novelDetail(novelId: id)).data;
      info = AiWork(
        id: id,
        title: detail.name,
        authors: detail.authors,
        tags: detail.types,
        status: detail.status,
        cover: detail.cover,
        description: detail.introduction,
        lastChapter: detail.lastUpdateChapterName,
        hot: detail.hotHits,
      );
    }
    if (_details.length >= _detailCacheSize) _details.remove(_details.keys.first);
    _details[key] = info;
    return info;
  }
}
