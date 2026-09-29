import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/services/search_history_service.dart';
import 'package:zai_x/widgets/ai_search_view.dart';

/// 搜索框下方的历史与本地建议
///
/// 官方热门搜索接口已失效，这里改用本机资料：搜过的词、看过与收藏的作品。
/// AI 模式下改显示示例描述与 AI 搜索历史。
class SearchSuggestionView extends StatelessWidget {
  const SearchSuggestionView({
    required this.history,
    required this.suggestions,
    required this.onSearch,
    required this.onRemoveHistory,
    required this.onClearHistory,
    required this.onOpen,
    this.aiMode = false,
    this.examples = const [],
    super.key,
  });

  final List<String> history;
  final List<LocalSearchSuggestion> suggestions;
  final void Function(String keyword) onSearch;
  final void Function(String keyword) onRemoveHistory;
  final void Function() onClearHistory;
  final void Function(int id) onOpen;

  /// AI 模式：显示示例描述与 AI 搜索历史
  final bool aiMode;

  /// AI 模式的示例描述（简体原文，显示时转换）
  final List<String> examples;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (aiMode) ..._buildAiIntro(),
        if (suggestions.isNotEmpty) ...[
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "本机相关".i18n,
              style: Get.textTheme.titleSmall,
            ),
          ),
          ...suggestions.map(
            (e) => ListTile(
              leading: const Icon(Remix.book_2_line),
              title: Text(
                e.title.i18n,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(e.from.i18n),
              onTap: () => onOpen(e.id),
            ),
          ),
          const Divider(height: 1),
        ],
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  (aiMode ? "AI 搜索历史" : "搜索历史").i18n,
                  style: Get.textTheme.titleSmall,
                ),
              ),
              if (history.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                  onPressed: onClearHistory,
                  child: Text("清除".i18n),
                ),
            ],
          ),
        ),
        if (history.isEmpty)
          Padding(
            padding: AppStyle.edgeInsetsA24,
            child: Text(
              (aiMode ? "还没有 AI 搜索记录" : "还没有搜索记录").i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          )
        else
          Padding(
            padding: AppStyle.edgeInsetsH12.copyWith(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: history
                  .map(
                    (e) => InputChip(
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          e.i18n,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onPressed: () => onSearch(e),
                      onDeleted: () => onRemoveHistory(e),
                      deleteIcon: const Icon(Icons.close, size: 16),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildAiIntro() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: kAiAccent),
            AppStyle.hGap8,
            Expanded(
              child: Text(
                "用一句话描述想看的作品".i18n,
                style: Get.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 12, 10),
        child: Text(
          "AI 会依标题、题材与简介帮你挑选".i18n,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
      if (examples.isNotEmpty)
        Padding(
          padding: AppStyle.edgeInsetsH12.copyWith(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in examples)
                ActionChip(
                  avatar: const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: kAiAccent,
                  ),
                  label: Text(example.i18n),
                  onPressed: () => onSearch(example.i18n),
                ),
            ],
          ),
        ),
      const Divider(height: 1),
    ];
  }
}
