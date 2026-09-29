import 'package:flutter/material.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/models/comic/search_item.dart';
import 'package:zai_x/modules/comic/search/comic_search_controller.dart';
import 'package:zai_x/routes/app_navigator.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';
import 'package:zai_x/widgets/net_image.dart';
import 'package:zai_x/widgets/page_list_view.dart';
import 'package:zai_x/widgets/search_suggestion_view.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/i18n.dart';

class ComicSearchPage extends StatelessWidget {
  final String keyword;
  final ComicSearchController controller;
  ComicSearchPage({this.keyword = "", super.key})
      : controller = Get.put(ComicSearchController(keyword));

  /// 「官方未收录」区块收合时显示几笔
  static const int kCollapsedCount = 3;

  /// 展开后最多显示几笔（每笔都要向详情接口补封面）
  static const int kExpandedLimit = 50;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: controller.searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "搜索漫画".i18n,
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              prefixIcon: SizedBox(
                width: 48,
                child: IconButton(
                  onPressed: () {
                    AppNavigator.closePage();
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              suffixIcon: SizedBox(
                width: 48,
                child: IconButton(
                  onPressed: controller.submit,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            onSubmitted: (e) {
              controller.submit();
            },
            onChanged: controller.onKeywordChanged,
          ),
        ),
      ),
      body: Stack(
        children: [
          PageListView(
            pageController: controller,
            firstRefresh: false,
            showPageLoadding: true,
            header: _buildLocalSection(context),
            separatorBuilder: (context, i) => Divider(
              endIndent: 12,
              indent: 12,
              color: Colors.grey.withValues(alpha: .2),
              height: 1,
            ),
            itemBuilder: (context, i) {
              var item = controller.list[i];
              return buildItem(item);
            },
          ),
          Positioned.fill(
            child: Obx(
              () => Offstage(
                offstage: !controller.showHotWord.value &&
                    controller.suggestions.isEmpty,
                child: Container(
                  color: Get.theme.scaffoldBackgroundColor,
                  child: SearchSuggestionView(
                    history: controller.searchHistory.toList(),
                    suggestions: controller.suggestions.toList(),
                    onSearch: controller.searchKeyword,
                    onRemoveHistory: controller.removeHistory,
                    onClearHistory: controller.clearHistory,
                    onOpen: AppNavigator.toComicDetail,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 官方搜索没有收录、由本地漫画索引补上的作品
  Widget _buildLocalSection(BuildContext context) {
    return Obx(() {
      final hits = controller.hiddenResults.toList();
      if (hits.isEmpty) return const SizedBox();
      final onlyLocal = controller.list.isEmpty;
      final expanded = onlyLocal || controller.hiddenExpanded.value;
      final shown =
          hits.take(expanded ? kExpandedLimit : kCollapsedCount).toList();
      final theme = Theme.of(context);
      final divider = Divider(
        endIndent: 12,
        indent: 12,
        color: Colors.grey.withValues(alpha: .2),
        height: 1,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Icon(Icons.travel_explore,
                    size: 18, color: theme.colorScheme.primary),
                AppStyle.hGap8,
                Expanded(
                  child: Text(
                    "官方搜索没有收录的作品 · ${hits.length} 部".i18n,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 2, 12, 4),
            child: Text(
              "神隐、下架等作品，来自每日更新的本地漫画索引".i18n,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) divider,
            _buildLocalItem(shown[i]),
          ],
          if (expanded && hits.length > kExpandedLimit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                "还有 ${hits.length - kExpandedLimit} 部，请输入更完整的关键字".i18n,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          if (!onlyLocal && hits.length > kCollapsedCount)
            TextButton.icon(
              onPressed: controller.hiddenExpanded.toggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: Text(expanded ? "收起".i18n : "展开全部 ${hits.length} 部".i18n),
            ),
          if (!onlyLocal) ...[
            Container(height: 8, color: Colors.grey.withValues(alpha: .08)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: Text("官方搜索结果".i18n, style: theme.textTheme.titleSmall),
            ),
          ],
        ],
      );
    });
  }

  Widget _buildLocalItem(ComicIndexHit hit) {
    final brief = controller.briefOf(hit.id);
    const grey = TextStyle(color: Colors.grey, fontSize: 14);
    return InkWell(
      onTap: () {
        AppNavigator.toComicDetail(hit.id);
      },
      child: Container(
        padding: AppStyle.edgeInsetsA12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Obx(
              () => NetImage(
                brief.value?.cover ?? "",
                width: 80,
                height: 110,
                borderRadius: 4,
              ),
            ),
            AppStyle.hGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hit.title.i18n,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AppStyle.hGap4,
                      _buildBadge(hit),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      const WidgetSpan(
                          child: Icon(
                        Icons.account_circle,
                        color: Colors.grey,
                        size: 18,
                      )),
                      const TextSpan(text: " "),
                      TextSpan(text: hit.authors, style: grey),
                    ]),
                  ),
                  AppStyle.vGap4,
                  Obx(() => Text((brief.value?.types ?? "").i18n, style: grey)),
                  AppStyle.vGap4,
                  Obx(() {
                    final last = brief.value?.lastChapterName ?? "";
                    return Text(
                      (last.isNotEmpty ? last : _statusText(hit.status)).i18n,
                      style: grey,
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(ComicIndexHit hit) {
    final color = hit.isHidden ? Colors.deepOrange : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        (hit.isHidden ? "神隐" : "未收录").i18n,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  static String _statusText(int status) => switch (status) {
        1 => "连载中",
        2 => "已完结",
        _ => "",
      };

  Widget buildItem(SearchComicItem item) {
    return InkWell(
      onTap: () {
        AppNavigator.toComicDetail(item.comicId);
      },
      child: Container(
        padding: AppStyle.edgeInsetsA12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            NetImage(
              item.cover,
              width: 80,
              height: 110,
              borderRadius: 4,
            ),
            AppStyle.hGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title.i18n,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      const WidgetSpan(
                          child: Icon(
                        Icons.account_circle,
                        color: Colors.grey,
                        size: 18,
                      )),
                      const TextSpan(
                        text: " ",
                      ),
                      TextSpan(
                          text: item.author,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14))
                    ]),
                  ),
                  AppStyle.vGap4,
                  Text(item.tags.i18n,
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  AppStyle.vGap4,
                  Text(item.lastChapterName.i18n,
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
