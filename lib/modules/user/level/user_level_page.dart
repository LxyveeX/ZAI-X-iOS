import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/models/user/user_level_model.dart';
import 'package:zai_x/modules/user/level/user_exam_page.dart';
import 'package:zai_x/modules/user/level/user_level_controller.dart';
import 'package:zai_x/services/user_exam_service.dart';
import 'package:zai_x/widgets/status/app_error_widget.dart';
import 'package:zai_x/widgets/status/app_loadding_widget.dart';

/// 用户等级：对应官方 App 点等级进入的页面
class UserLevelPage extends StatelessWidget {
  UserLevelPage({super.key})
      : controller = Get.put(
          UserLevelController(),
          tag: DateTime.now().millisecondsSinceEpoch.toString(),
        );

  final UserLevelController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("用户等级".i18n)),
      body: Obx(() {
        final info = controller.info.value;
        if (controller.pageError.value) {
          return AppErrorWidget(
            errorMsg: controller.errorMsg.value,
            onRefresh: controller.load,
          );
        }
        if (info == null) {
          return const AppLoaddingWidget();
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: LayoutBuilder(builder: (context, constraints) {
            final inset = constraints.maxWidth > 760
                ? (constraints.maxWidth - 720) / 2
                : 16.0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
              children: [
                _header(context, info),
                const SizedBox(height: 16),
                _card(context, "当前等级特权".i18n, [
                  if (info.privileges.isEmpty)
                    _muted(context, "这个等级没有额外特权".i18n)
                  else
                    for (final item in info.privileges) _bullet(context, item),
                ]),
                const SizedBox(height: 16),
                _conditions(context, info),
              ],
            );
          }),
        );
      }),
    );
  }

  Widget _header(BuildContext context, UserLevelInfo info) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final credits = controller.credits.value;
    return Material(
      color: primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "Lv.${info.level}",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 12),
                if (credits != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      "当前积分 $credits".i18n,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _track(context, info),
          ],
        ),
      ),
    );
  }

  /// 等级进度：已达到的等级用主色
  Widget _track(BuildContext context, UserLevelInfo info) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final idle = theme.dividerColor.withValues(alpha: .35);
    final levels =
        info.levels.isEmpty ? List<int>.generate(6, (i) => i) : info.levels;
    return Row(
      children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                color: levels[i] <= info.level ? primary : idle,
              ),
            ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: levels[i] <= info.level ? primary : Colors.transparent,
              border: Border.all(
                color: levels[i] <= info.level ? primary : idle,
                width: levels[i] == info.level ? 3 : 1.5,
              ),
            ),
            child: Text(
              "${levels[i]}",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: levels[i] <= info.level
                    ? theme.colorScheme.onPrimary
                    : theme.textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _conditions(BuildContext context, UserLevelInfo info) {
    final children = <Widget>[];
    if (info.isMaxLevel) {
      children.add(_muted(context, "已经是最高等级了".i18n));
    } else if (info.conditionGroups.isEmpty) {
      children.add(_muted(context, "暂时没有晋升条件".i18n));
    } else {
      if (info.conditionGroups.length > 1) {
        children.add(_muted(context, "完成任意一类即可升级".i18n));
      }
      for (final group in info.conditionGroups) {
        for (final item in group) {
          children.add(_conditionRow(context, item));
          if (item.isExam && !item.completed) {
            children.add(_examPanel(context));
          }
        }
      }
    }
    return _card(context, "晋升条件".i18n, children);
  }

  Widget _conditionRow(BuildContext context, UserLevelCondition item) {
    final color = item.completed ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            item.completed ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: item.completed ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(item.content.i18n)),
          const SizedBox(width: 8),
          Text(
            item.completed ? "已完成".i18n : "未完成".i18n,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  /// 题库认证：规则、上次成绩与 AI 一键答题
  Widget _examPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final service = UserExamService.instance;
      final last = controller.lastScore.value;
      final prepare = controller.prepare.value;
      final blocked = prepare != null && !prepare.ready;
      final left = controller.remaining.value;
      final canStart = service.available && !blocked && left > 0;
      final caption = theme.textTheme.bodySmall;
      return Container(
        margin: const EdgeInsets.only(top: 2, bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "30 分钟内作答 50 题（送分题 20、正常题 20、地狱题 10），"
                      "总分超过 60 分即可晋升 Lv5。"
                  .i18n,
              style: caption,
            ),
            if (last != null && last.taken) ...[
              const SizedBox(height: 6),
              Text(
                "上次成绩：${UserExamPage.formatScore(last.score)} 分"
                        "（${last.passed ? "已过关" : "未过关"}）"
                    .i18n,
                style: caption?.copyWith(
                  color: last.passed ? Colors.green : Colors.orange,
                ),
              ),
            ],
            if (blocked) ...[
              const SizedBox(height: 6),
              Text(
                prepare.message.i18n,
                style: caption?.copyWith(color: Colors.orange),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text("交卷前让我检查答案".i18n),
              subtitle: Text("关闭时 AI 作答完会直接交卷".i18n),
              value: controller.reviewFirst.value,
              onChanged: controller.setReviewFirst,
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canStart ? controller.startExam : null,
                icon: const Icon(Remix.robot_2_line, size: 18),
                label: Text("AI 一键答题".i18n),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              !service.available
                  ? "这个版本没有内建 AI 服务".i18n
                  : left > 0
                      ? "答案由 AI 判断，不保证过关 · 今天还能用 $left 次".i18n
                      : "今天的次数已用完，明天再来吧".i18n,
              style: caption?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    });
  }

  Widget _card(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Material(
      color: theme.brightness == Brightness.dark
          ? const Color(0xff151a21)
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Expanded(child: Text(text.i18n)),
        ],
      ),
    );
  }

  Widget _muted(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
      );
}
