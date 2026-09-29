import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zai_x/app/controller/base_controller.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/app/app_constant.dart';
import 'package:zai_x/models/novel/search_model.dart';
import 'package:zai_x/requests/novel_request.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_search_session.dart';
import 'package:zai_x/services/search_history_service.dart';
import 'package:get/get.dart';

class NovelSearchController extends BasePageController<NovelSearchModel> {
  final String keyword;
  NovelSearchController(this.keyword) {
    searchController = TextEditingController(text: keyword);
  }
  late TextEditingController searchController;
  final NovelRequest request = NovelRequest();

  String _keyword = "";
  RxMap<int, String> hotWords = <int, String>{}.obs;
  var showHotWord = true.obs;

  /// 搜索历史
  final searchHistory = <String>[].obs;

  /// 依输入内容从本机资料给的建议
  final suggestions = <LocalSearchSuggestion>[].obs;

  /// AI 搜索（没有内建 AI 服务的建置不显示开关）
  final ai = AiSearchSession(AiSearchKind.novel);

  bool get _aiMode => ai.enabled.value;

  @override
  void onInit() {
    //  loadHotWord();
    loadHistory();
    if (keyword.isNotEmpty) {
      submit();
    }
    super.onInit();
  }

  void loadHistory() {
    searchHistory.assignAll(
      SearchHistoryService.get(AppConstant.kTypeNovel, ai: _aiMode),
    );
  }

  /// 输入变化时更新建议；清空输入就回到历史列表
  void onKeywordChanged(String text) {
    // AI 模式输入的是描述，不比对书名
    suggestions.assignAll(_aiMode
        ? const <LocalSearchSuggestion>[]
        : SearchHistoryService.suggest(AppConstant.kTypeNovel, text));
    if (text.isEmpty) {
      showHotWord.value = true;
    }
  }

  /// 切换 AI 模式：回到历史列表，按搜索才会开始
  Future<void> setAiMode(bool value) async {
    await ai.setEnabled(value);
    suggestions.clear();
    loadHistory();
    showHotWord.value = true;
  }

  void searchKeyword(String text) {
    searchController.text = text;
    submit();
  }

  Future<void> removeHistory(String text) async {
    await SearchHistoryService.remove(AppConstant.kTypeNovel, text, ai: _aiMode);
    loadHistory();
  }

  Future<void> clearHistory() async {
    await SearchHistoryService.clear(AppConstant.kTypeNovel, ai: _aiMode);
    loadHistory();
  }

  void submit() async {
    if (searchController.text.isEmpty) {
      list.clear();
      ai.hide();
      showHotWord.value = true;
      return;
    }
    if (_aiMode) {
      unawaited(_submitAi());
      return;
    }
    showHotWord.value = false;
    _keyword = searchController.text;
    suggestions.clear();
    await SearchHistoryService.add(AppConstant.kTypeNovel, _keyword);
    loadHistory();
    refreshData();
  }

  Future<void> _submitAi() async {
    final text = searchController.text.trim();
    if (text.isEmpty) return;
    showHotWord.value = false;
    suggestions.clear();
    await SearchHistoryService.add(AppConstant.kTypeNovel, text, ai: true);
    loadHistory();
    await ai.search(text);
  }

  @override
  void onClose() {
    ai.dispose();
    super.onClose();
  }

  @override
  Future<List<NovelSearchModel>> getData(int page, int pageSize) async {
    if (searchController.text.isEmpty) {
      return [];
    }
    return await request.search(keyword: _keyword, page: page);
  }

  void loadHotWord() async {
    try {
      hotWords.value = await request.searchHotWord();
    } catch (e) {
      Log.logPrint(e);
    }
  }
}
