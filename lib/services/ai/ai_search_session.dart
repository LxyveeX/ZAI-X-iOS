import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_search_pipeline.dart';
import 'package:zai_x/services/ai/ai_search_service.dart';
import 'package:zai_x/services/local_storage_service.dart';

/// 搜索页 AI 模式的状态（漫画、小说各一份）
class AiSearchSession {
  AiSearchSession(this.kind, {AiSearchService? service})
      : _service = service ?? AiSearchService.instance {
    if (available) {
      final value = LocalStorageService.instance
          .getValue<dynamic>(LocalStorageService.kAiSearchEnabled, false);
      enabled.value = value == true;
    }
  }

  final AiSearchKind kind;
  final AiSearchService _service;

  /// 这个建置有没有 AI 服务；没有就不显示开关
  bool get available => _service.available;

  /// AI 模式开关（漫画、小说共用同一个设定）
  final enabled = false.obs;

  /// 是否显示 AI 结果区
  final visible = false.obs;
  final running = false.obs;
  final stage = ''.obs;
  final error = ''.obs;

  /// AI 对需求的理解
  final summary = ''.obs;
  final conditions = <String>[].obs;
  final results = <AiSearchResultItem>[].obs;

  /// false：AI 挑选失败，显示的是依条件排序的候选
  final reranked = true.obs;

  /// AI 已经读过几部作品
  final seen = 0.obs;

  /// 「找更多作品」
  final hasMore = false.obs;
  final loadingMore = false.obs;
  final moreStage = ''.obs;
  final moreError = ''.obs;

  /// 上一次「找更多作品」没有找到符合的
  final moreEmpty = false.obs;

  String _query = '';
  int _generation = 0;
  CancelToken? _cancel;
  AiSearchRun? _run;

  Future<void> setEnabled(bool value) async {
    if (!available) return;
    enabled.value = value;
    hide();
    await LocalStorageService.instance
        .setValue(LocalStorageService.kAiSearchEnabled, value);
  }

  Future<void> search(String query) async {
    final text = query.trim();
    if (text.isEmpty || !available) return;
    _query = text;
    final generation = ++_generation;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    bool current() => generation == _generation;

    _run = null;
    visible.value = true;
    running.value = true;
    error.value = '';
    summary.value = '';
    conditions.clear();
    results.clear();
    reranked.value = true;
    seen.value = 0;
    hasMore.value = false;
    loadingMore.value = false;
    moreError.value = '';
    moreEmpty.value = false;
    stage.value = '正在理解你的需求…';
    try {
      final run = await _service.start(
        text,
        kind,
        cancel: cancel,
        onStage: (value) {
          if (current()) stage.value = value;
        },
        onPlan: (plan) {
          if (!current()) return;
          summary.value = plan.summary;
          conditions.assignAll(plan.conditions);
        },
      );
      if (!current()) return;
      _run = run;
      _apply(run);
    } on AiSearchCancelled {
      return;
    } catch (e) {
      if (!current()) return;
      Log.logPrint(e);
      error.value = e is AppError ? e.message : 'AI 搜索失败，请稍后再试';
    } finally {
      if (current()) running.value = false;
    }
  }

  Future<void> retry() => search(_query);

  /// 再读一批还没看过的候选
  Future<void> loadMore() async {
    final run = _run;
    if (run == null || running.value || loadingMore.value || !run.hasMore) {
      return;
    }
    final generation = _generation;
    final cancel = _cancel = CancelToken();
    loadingMore.value = true;
    moreError.value = '';
    moreEmpty.value = false;
    moreStage.value = '正在寻找更多作品…';
    try {
      final items = await _service.more(
        run,
        cancel: cancel,
        onStage: (value) {
          if (generation == _generation) moreStage.value = value;
        },
      );
      if (generation != _generation) return;
      _apply(run);
      moreEmpty.value = items.isEmpty;
    } on AiSearchCancelled {
      return;
    } catch (e) {
      if (generation != _generation) return;
      Log.logPrint(e);
      moreError.value = e is AppError ? e.message : '没能找到更多作品，请稍后再试';
    } finally {
      if (generation == _generation) loadingMore.value = false;
    }
  }

  void _apply(AiSearchRun run) {
    summary.value = run.plan.summary;
    conditions.assignAll(run.plan.conditions);
    results.assignAll(run.items);
    reranked.value = run.reranked;
    seen.value = run.seen;
    hasMore.value = run.hasMore;
  }

  /// 收起结果区，并停止进行中的搜索
  void hide() {
    _generation++;
    _cancel?.cancel();
    _run = null;
    running.value = false;
    loadingMore.value = false;
    visible.value = false;
  }

  void dispose() {
    _generation++;
    _cancel?.cancel();
  }
}
