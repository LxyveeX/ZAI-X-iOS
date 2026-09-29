import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
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

  String _query = '';
  int _generation = 0;
  CancelToken? _cancel;

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

    visible.value = true;
    running.value = true;
    error.value = '';
    summary.value = '';
    conditions.clear();
    results.clear();
    reranked.value = true;
    stage.value = '正在理解你的需求…';
    try {
      final outcome = await _service.search(
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
      summary.value = outcome.plan.summary;
      conditions.assignAll(outcome.plan.conditions);
      results.assignAll(outcome.items);
      reranked.value = outcome.reranked;
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

  /// 收起结果区，并停止进行中的搜索
  void hide() {
    _generation++;
    _cancel?.cancel();
    running.value = false;
    visible.value = false;
  }

  void dispose() {
    _generation++;
    _cancel?.cancel();
  }
}
