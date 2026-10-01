import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/models/user/user_exam_model.dart';
import 'package:zai_x/modules/user/level/user_exam_controller.dart';
import 'package:zai_x/services/ai/ai_exam_solver.dart';
import 'package:zai_x/services/user_exam_service.dart';

/// AI 一键答题的进度、检查与成绩
class UserExamPage extends GetView<UserExamController> {
  const UserExamPage({super.key});

  static String formatScore(num score) => score == score.roundToDouble()
      ? "${score.round()}"
      : score.toStringAsFixed(1);

  static String difficultyLabel(int difficulty) => switch (difficulty) {
        1 => "送分题",
        3 => "地狱题",
        _ => "正常题",
      };

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final stage = controller.stage.value;
      final busy = stage == UserExamStage.running ||
          stage == UserExamStage.reviewing ||
          stage == UserExamStage.submitting;
      return PopScope(
        canPop: !busy,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) controller.confirmLeave();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text("AI 一键答题".i18n),
            actions: [
              if (stage == UserExamStage.reviewing)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      "剩余 ${_clock(controller.secondsLeft.value)}".i18n,
                      style: TextStyle(
                        fontSize: 13,
                        color: controller.secondsLeft.value < 120
                            ? Colors.red
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: switch (stage) {
            UserExamStage.running ||
            UserExamStage.submitting =>
              _progress(context),
            UserExamStage.reviewing => _review(context),
            UserExamStage.done => _done(context),
            UserExamStage.failed => _failed(context),
          },
          bottomNavigationBar: stage == UserExamStage.reviewing
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton(
                      onPressed: controller.confirmSubmit,
                      child: Text("交卷".i18n),
                    ),
                  ),
                )
              : null,
        ),
      );
    });
  }

  static String _clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, "0");
    final s = (seconds % 60).toString().padLeft(2, "0");
    return "$m:$s";
  }

  Widget _progress(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 20),
            Text(
              controller.stageText.value.i18n,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              "通常需要一两分钟，请留在这个页面".i18n,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _review(BuildContext context) {
    final draft = controller.draft.value!;
    final unsure = controller.answers
        .where((e) =>
            e.confidence < AiExamSolver.recheckBelow &&
            !controller.edited.contains(e.questionId))
        .length;
    return _sheet(
      context,
      draft.paper.questions,
      editable: true,
      header: _notice(
        context,
        unsure > 0
            ? "AI 已作答完毕，其中 $unsure 题把握较低（橘框标示），可以点选项修改后再交卷。".i18n
            : "AI 已作答完毕，可以点选项修改后再交卷。".i18n,
      ),
    );
  }

  Widget _done(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.score.value!;
    final draft = controller.draft.value!;
    final left = UserExamService.instance.remainingToday;
    final color = result.passed ? Colors.green : Colors.orange;
    final header = Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            "${formatScore(result.score)} 分".i18n,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result.passed
                ? "恭喜过关，获得晋升 Lv5 的资格！".i18n
                : "这次没有超过 60 分，换一份考卷再试一次吧。".i18n,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          if (!result.passed) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: left > 0 ? controller.run : null,
              child: Text(
                left > 0 ? "再试一次（今天还能用 $left 次）".i18n : "今天的次数已用完".i18n,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            "下面是 AI 这次的作答（官方不公布正确答案）".i18n,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
    return _sheet(context, draft.paper.questions,
        editable: false, header: header);
  }

  Widget _failed(BuildContext context) {
    final theme = Theme.of(context);
    final left = UserExamService.instance.remainingToday;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              controller.errorText.value.i18n,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 20),
            if (controller.canResubmit)
              FilledButton(
                onPressed: controller.submit,
                child: Text("重新交卷".i18n),
              )
            else if (left > 0)
              FilledButton(
                onPressed: controller.run,
                child: Text("重新开始（今天还能用 $left 次）".i18n),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: controller.confirmLeave,
              child: Text("返回".i18n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _sheet(
    BuildContext context,
    List<UserExamQuestion> questions, {
    required bool editable,
    required Widget header,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final inset =
          constraints.maxWidth > 760 ? (constraints.maxWidth - 720) / 2 : 16.0;
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(inset, 12, inset, 24),
        itemCount: questions.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return header;
          final question = questions[index - 1];
          return Obx(() {
            final answer = controller.answers
                .firstWhereOrNull((e) => e.questionId == question.id);
            return _question(context, index, question, answer,
                editable: editable,
                edited: controller.edited.contains(question.id));
          });
        },
      );
    });
  }

  Widget _question(
    BuildContext context,
    int number,
    UserExamQuestion question,
    UserExamAnswer? answer, {
    required bool editable,
    required bool edited,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final confidence = answer?.confidence ?? 0;
    final unsure = !edited && confidence < AiExamSolver.recheckBelow;
    final badgeColor = edited
        ? primary
        : confidence >= 0.8
            ? Colors.green
            : confidence >= AiExamSolver.recheckBelow
                ? Colors.amber.shade700
                : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xff151a21)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: editable && unsure
            ? Border.all(color: Colors.orange.withValues(alpha: .7))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                number.toString().padLeft(2, "0"),
                style: TextStyle(fontWeight: FontWeight.w700, color: primary),
              ),
              const SizedBox(width: 8),
              _tag(context, difficultyLabel(question.difficulty).i18n),
              if (question.multiple) ...[
                const SizedBox(width: 6),
                _tag(context, "多选".i18n),
              ],
              const Spacer(),
              if (answer != null)
                Text(
                  edited
                      ? "已修改".i18n
                      : "把握 ${(confidence * 100).round()}%".i18n,
                  style: TextStyle(fontSize: 12, color: badgeColor),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(question.title.i18n, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          for (var i = 0; i < question.options.length; i++)
            _option(
              context,
              question,
              i,
              selected: answer?.choices.contains(i) ?? false,
              editable: editable,
            ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    UserExamQuestion question,
    int index, {
    required bool selected,
    required bool editable,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final icon = question.multiple
        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: editable ? () => controller.toggle(question, index) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: selected ? primary : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "${UserExamAnswer.optionLetter(index)}. "
                "${question.options[index].i18n}",
                style: TextStyle(
                  color: selected ? primary : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.withValues(alpha: .5)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}
