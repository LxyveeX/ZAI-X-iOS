import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_search_session.dart';
import 'package:zai_x/widgets/net_image.dart';

/// AI 功能的强调色
const Color kAiAccent = Color(0xFF8B5CF6);

/// 搜索页的示例描述
abstract final class AiSearchExamples {
  static const List<String> comic = [
    '校园恋爱，已完结',
    '女主很强的奇幻冒险',
    '轻松治愈的日常，不要太虐',
    '类似《葬送的芙莉莲》的作品',
  ];

  static const List<String> novel = [
    '异世界转生，主角很强',
    '校园恋爱喜剧',
    '推理悬疑，已完结',
  ];
}

/// 搜索框下方的「AI 搜索」开关
class AiSearchToggle extends StatelessWidget {
  const AiSearchToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      toggled: value,
      button: true,
      child: Material(
        color: value ? kAiAccent.withValues(alpha: .14) : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: value
                ? kAiAccent.withValues(alpha: .7)
                : Colors.grey.withValues(alpha: .4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 3, 6, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: kAiAccent),
                const SizedBox(width: 4),
                Text(
                  "AI 搜索".i18n,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 34,
                  height: 20,
                  child: FittedBox(
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                      activeThumbColor: kAiAccent,
                      activeTrackColor: kAiAccent.withValues(alpha: .45),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// AI 搜索的结果区：进度、错误、AI 的理解与推荐清单
class AiSearchResultView extends StatelessWidget {
  const AiSearchResultView({
    required this.session,
    required this.onOpen,
    super.key,
  });

  final AiSearchSession session;
  final void Function(int id) onOpen;

  static const TextStyle _grey = TextStyle(color: Colors.grey, fontSize: 14);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (session.running.value) return _buildLoading(context);
      if (session.error.value.isNotEmpty) return _buildError(context);
      final items = session.results.toList();
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildHeader(context, items.length),
          if (items.isEmpty)
            _buildEmpty(context)
          else ...[
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(
                  indent: 12,
                  endIndent: 12,
                  height: 1,
                  color: Colors.grey.withValues(alpha: .2),
                ),
              _buildItem(context, items[i]),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                "结果由 AI 依标题、题材与简介挑选，仅供参考".i18n,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _buildLoading(BuildContext context) {
    final summary = session.summary.value;
    return Center(
      child: Padding(
        padding: AppStyle.edgeInsetsA24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: kAiAccent,
              ),
            ),
            AppStyle.vGap12,
            Text(
              session.stage.value.i18n,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (summary.isNotEmpty) ...[
              AppStyle.vGap8,
              Text(
                "AI 理解：$summary".i18n,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppStyle.edgeInsetsA24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: Colors.grey.withValues(alpha: .7),
            ),
            AppStyle.vGap12,
            Text(
              session.error.value.i18n,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            AppStyle.vGap12,
            OutlinedButton(
              onPressed: session.retry,
              child: Text("重试".i18n),
            ),
            AppStyle.vGap8,
            Text(
              "也可以关闭 AI 搜索，改用一般搜索".i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    final theme = Theme.of(context);
    final summary = session.summary.value;
    final conditions = session.conditions.toList();
    final reranked = session.reranked.value;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kAiAccent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.auto_awesome, size: 16, color: kAiAccent),
              ),
              AppStyle.hGap8,
              Expanded(
                child: Text(
                  (summary.isEmpty ? "AI 搜索结果" : summary).i18n,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (conditions.isNotEmpty) ...[
            AppStyle.vGap8,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final condition in conditions)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: kAiAccent.withValues(alpha: .35),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      condition.i18n,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
          if (count > 0) ...[
            AppStyle.vGap8,
            Text(
              reranked
                  ? "依标题、题材与简介挑出 $count 部".i18n
                  : "AI 没能完成挑选，先依条件列出候选".i18n,
              style: TextStyle(
                fontSize: 12,
                color: reranked ? Colors.grey : Colors.orange,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: Colors.grey.withValues(alpha: .7),
          ),
          AppStyle.vGap8,
          Text(
            "没有找到符合描述的作品".i18n,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          AppStyle.vGap4,
          Text(
            "换个说法，或少一点条件再试试".i18n,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, AiSearchResultItem item) {
    final work = item.work;
    final tags = work.tags.join('/');
    final progress = [work.status, work.lastChapter]
        .where((e) => e.isNotEmpty)
        .join(' · ');
    return InkWell(
      onTap: () => onOpen(work.id),
      child: Padding(
        padding: AppStyle.edgeInsetsA12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetImage(work.cover, width: 80, height: 110, borderRadius: 4),
            AppStyle.hGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.title.i18n,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (work.authors.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: [
                        const WidgetSpan(
                          child: Icon(
                            Icons.account_circle,
                            color: Colors.grey,
                            size: 18,
                          ),
                        ),
                        const TextSpan(text: " "),
                        TextSpan(text: work.authors, style: _grey),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    AppStyle.vGap4,
                    Text(
                      tags.i18n,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _grey,
                    ),
                  ],
                  if (progress.isNotEmpty) ...[
                    AppStyle.vGap4,
                    Text(
                      progress.i18n,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _grey,
                    ),
                  ],
                  if (item.reason.isNotEmpty) ...[
                    AppStyle.vGap8,
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kAiAccent.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Icon(
                              Icons.auto_awesome,
                              size: 13,
                              color: kAiAccent,
                            ),
                          ),
                          AppStyle.hGap4,
                          Expanded(
                            child: Text(
                              item.reason.i18n,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
