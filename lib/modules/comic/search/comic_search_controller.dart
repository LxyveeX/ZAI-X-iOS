import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:zai_x/app/dialog_utils.dart';
import 'package:zai_x/app/controller/base_controller.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/app/app_constant.dart';
import 'package:zai_x/models/comic/comic_brief.dart';
import 'package:zai_x/models/comic/search_item.dart';
import 'package:zai_x/requests/comic_request.dart';
import 'package:zai_x/routes/app_navigator.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_search_session.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';
import 'package:zai_x/services/comic_index/comic_index_service.dart';
import 'package:zai_x/services/search_history_service.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/i18n.dart';

class ComicSearchController extends BasePageController<SearchComicItem> {
  final String keyword;
  ComicSearchController(this.keyword) {
    searchController = TextEditingController(text: keyword);
    showHotWord.value = keyword.isEmpty;
  }
  late TextEditingController searchController;
  final ComicRequest request = ComicRequest();

  String _keyword = "";

  RxMap<int, String> hotWords = <int, String>{}.obs;

  var showHotWord = true.obs;

  /// 搜索历史
  final searchHistory = <String>[].obs;

  /// 依输入内容从本机资料给的建议
  final suggestions = <LocalSearchSuggestion>[].obs;

  /// AI 搜索（没有内建 AI 服务的建置不显示开关）
  final ai = AiSearchSession(AiSearchKind.comic);

  bool get _aiMode => ai.enabled.value;

  /// 官方搜索每页固定 20 笔（见 [ComicRequest.search]）
  static const int kRemotePageSize = 20;

  /// 本地漫画索引找到、但官方搜索没有给的作品（神隐、下架等）
  final hiddenResults = <ComicIndexHit>[].obs;

  /// 「官方未收录」区块是否展开
  final hiddenExpanded = false.obs;

  Future<List<ComicIndexHit>>? _localSearch;
  final Set<int> _remoteIds = {};
  int _remotePage = 1;
  bool _remoteComplete = false;
  int _generation = 0;

  final Map<int, Rx<ComicBrief?>> _briefs = {};
  final List<int> _briefQueue = [];
  int _briefRunning = 0;

  @override
  void onInit() {
    // loadHotWord();
    loadHistory();
    if (keyword.isNotEmpty) {
      submit();
    }
    super.onInit();
  }

  void loadHistory() {
    searchHistory.assignAll(
      SearchHistoryService.get(AppConstant.kTypeComic, ai: _aiMode),
    );
  }

  /// 输入变化时更新建议；清空输入就回到历史列表
  void onKeywordChanged(String text) {
    // AI 模式输入的是描述，不比对书名
    suggestions.assignAll(_aiMode
        ? const <LocalSearchSuggestion>[]
        : SearchHistoryService.suggest(AppConstant.kTypeComic, text));
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
    await SearchHistoryService.remove(AppConstant.kTypeComic, text, ai: _aiMode);
    loadHistory();
  }

  Future<void> clearHistory() async {
    await SearchHistoryService.clear(AppConstant.kTypeComic, ai: _aiMode);
    loadHistory();
  }

  void submit() async {
    if (searchController.text.isEmpty) {
      list.clear();
      hiddenResults.clear();
      ai.hide();
      showHotWord.value = true;
      return;
    }

    if (_aiMode) {
      unawaited(_submitAi());
      return;
    }

    if (int.tryParse(searchController.text) != null &&
        await numberJumpComic()) {
      return;
    }

    if (searchController.text.startsWith("id:\\") && await handelJumpComic()) {
      return;
    }

    showHotWord.value = false;
    _keyword = searchController.text;
    suggestions.clear();
    await SearchHistoryService.add(AppConstant.kTypeComic, _keyword);
    loadHistory();
    _startLocalSearch();
    refreshData();
  }

  Future<void> _submitAi() async {
    final text = searchController.text.trim();
    if (text.isEmpty) return;
    showHotWord.value = false;
    suggestions.clear();
    await SearchHistoryService.add(AppConstant.kTypeComic, text, ai: true);
    loadHistory();
    await ai.search(text);
  }

  @override
  void onClose() {
    ai.dispose();
    super.onClose();
  }

  /// 同时开始搜本地漫画索引；结果等官方第一页回来后再决定要显示哪些
  void _startLocalSearch() {
    _generation++;
    hiddenResults.clear();
    hiddenExpanded.value = false;
    final service = ComicIndexService.instance;
    if (!service.enabled.value) {
      _localSearch = null;
      return;
    }
    _localSearch = service.search(_keyword).catchError((Object e) {
      Log.logPrint(e);
      return <ComicIndexHit>[];
    });
    // 背景检查索引更新；内部有频率限制，手机只在 Wi-Fi 下自动下载
    unawaited(service.refresh());
  }

  /// 算出「官方未收录」区块，返回是否有内容
  Future<bool> _showLocal(int generation, {bool remoteFailed = false}) async {
    final future = _localSearch;
    if (future == null) return false;
    final hits = await future;
    if (generation != _generation) return false;
    hiddenResults.assignAll(ComicIndexMerge.missingFromRemote(
      hits,
      _remoteIds,
      remoteComplete: _remoteComplete,
      remoteFailed: remoteFailed,
    ));
    return hiddenResults.isNotEmpty;
  }

  /// 本地结果的封面、题材等资料，逐笔向详情接口补抓（同时最多 3 个请求）
  Rx<ComicBrief?> briefOf(int comicId) {
    final existing = _briefs[comicId];
    if (existing != null) return existing;
    final rx = Rx<ComicBrief?>(null);
    _briefs[comicId] = rx;
    _briefQueue.add(comicId);
    _pumpBriefs();
    return rx;
  }

  void _pumpBriefs() {
    while (_briefRunning < 3 && _briefQueue.isNotEmpty) {
      final id = _briefQueue.removeAt(0);
      _briefRunning++;
      request.comicBrief(comicId: id).then((brief) {
        if (!isClosed) _briefs[id]?.value = brief;
      }).catchError((Object e) {
        Log.logPrint(e);
      }).whenComplete(() {
        _briefRunning--;
        if (!isClosed) _pumpBriefs();
      });
    }
  }

  Future<bool> handelJumpComic() async {
    var id = int.tryParse(searchController.text.replaceAll("id:\\", "")) ?? 0;
    if (id != 0) {
      AppNavigator.toComicDetail(id);
      return true;
    } else {
      return false;
    }
  }

  Future numberJumpComic() async {
    if (!await DialogUtils.showAlertDialog(
      "你输入了纯数字，是否跳转至对应的漫画?".i18n,
      title: "漫画ID跳转".i18n,
    )) {
      return false;
    }
    return await handelJumpComic();
  }

  @override
  Future loadData() async {
    await super.loadData();
    // 官方没结果、但本地索引有：不要盖上「空白」或错误画面
    if (hiddenResults.isNotEmpty) {
      pageEmpty.value = false;
      pageError.value = false;
    }
  }

  @override
  Future<List<SearchComicItem>> getData(int page, int pageSize) async {
    if (searchController.text.isEmpty) {
      return [];
    }
    final generation = _generation;
    if (page == 1) {
      _remoteIds.clear();
      _remotePage = 1;
      _remoteComplete = false;
    }
    final fresh = <SearchComicItem>[];
    try {
      while (fresh.isEmpty && !_remoteComplete) {
        final remote =
            await request.search(keyword: _keyword, page: _remotePage);
        _remotePage++;
        if (remote.length < kRemotePageSize) {
          _remoteComplete = true;
        }
        // 已经显示在「官方未收录」区块的作品不重复列出
        final shown =
            page == 1 ? const <int>{} : hiddenResults.map((e) => e.id).toSet();
        for (final item in remote) {
          if (shown.contains(item.comicId)) continue;
          if (_remoteIds.add(item.comicId)) fresh.add(item);
        }
        // 第一页要先算出本地区块；之后若整页都被滤掉就继续抓下一页
        if (page == 1) break;
      }
    } catch (e) {
      if (page == 1 && await _showLocal(generation, remoteFailed: true)) {
        SmartDialog.showToast("官方搜索失败，先显示本地索引的结果".i18n);
        return [];
      }
      rethrow;
    }
    if (page == 1) {
      await _showLocal(generation);
    }
    return fresh;
  }

  void loadHotWord() async {
    try {
      hotWords.value = await request.searchHotWord();
    } catch (e) {
      Log.logPrint(e);
    }
  }
}
