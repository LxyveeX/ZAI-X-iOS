import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/models/user/user_exam_model.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/user_exam_service.dart';
import 'package:zai_x/services/user_service.dart';

enum UserExamStage { running, reviewing, submitting, done, failed }

/// AI 一键答题：领卷 → AI 作答 →（检查）→ 交卷 → 成绩
class UserExamController extends GetxController {
  UserExamController({required this.reviewFirst});

  /// 交卷前先让使用者检查
  final bool reviewFirst;

  final stage = UserExamStage.running.obs;
  final stageText = "".obs;
  final errorText = "".obs;
  final draft = Rxn<UserExamDraft>();

  /// 目前的作答（检查时可以修改）
  final answers = <UserExamAnswer>[].obs;

  /// 使用者改过的题目
  final edited = <int>{}.obs;
  final score = Rxn<UserExamScore>();

  /// 剩余作答秒数（检查时显示）
  final secondsLeft = 0.obs;

  CancelToken? _cancel;
  Timer? _timer;

  @override
  void onInit() {
    run();
    super.onInit();
  }

  /// 领一份新考卷从头作答
  Future<void> run() async {
    _timer?.cancel();
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    stage.value = UserExamStage.running;
    stageText.value = "正在准备…";
    errorText.value = "";
    score.value = null;
    draft.value = null;
    answers.clear();
    edited.clear();
    try {
      final result = await UserExamService.instance.draft(
        cancel: cancel,
        onStage: (text) => stageText.value = text,
      );
      if (cancel.isCancelled) return;
      draft.value = result;
      answers.assignAll(result.answers);
      if (reviewFirst) {
        stage.value = UserExamStage.reviewing;
        _startCountdown();
      } else {
        await submit();
      }
    } on AiSearchCancelled {
      // 离开页面
    } catch (e) {
      if (cancel.isCancelled) return;
      Log.logPrint(e);
      errorText.value = e.toString();
      stage.value = UserExamStage.failed;
    }
  }

  /// 交卷（失败时可以在期限内重送）
  Future<void> submit() async {
    final current = draft.value;
    if (current == null) return;
    _timer?.cancel();
    stage.value = UserExamStage.submitting;
    stageText.value = "正在交卷…";
    try {
      score.value = await UserExamService.instance
          .submit(UserExamDraft(current.paper, answers));
      stage.value = UserExamStage.done;
      if (score.value?.passed == true) {
        // 过关后刷新「我的」页的等级
        unawaited(UserService.instance.refreshProfile());
      }
    } catch (e) {
      Log.logPrint(e);
      errorText.value = e.toString();
      stage.value = UserExamStage.failed;
    }
  }

  /// 检查时交卷：有没作答的题先确认
  Future<void> confirmSubmit() async {
    final empty = answers.where((e) => e.choices.isEmpty).length;
    if (empty > 0) {
      final ok = await Get.dialog<bool>(
        AlertDialog(
          content: Text("还有 $empty 题没有作答，确定交卷吗？".i18n),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text("继续作答".i18n),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: Text("交卷".i18n),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await submit();
  }

  /// 期限内、还没拿到成绩时可以重送这份考卷
  bool get canResubmit {
    final current = draft.value;
    return current != null &&
        score.value == null &&
        DateTime.now().isBefore(current.paper.deadline);
  }

  /// 检查时改答案：单选换一个，多选切换
  void toggle(UserExamQuestion question, int option) {
    if (stage.value != UserExamStage.reviewing) return;
    final index = answers.indexWhere((e) => e.questionId == question.id);
    if (index < 0) return;
    final current = answers[index];
    final List<int> next;
    if (question.multiple) {
      next = current.choices.contains(option)
          ? current.choices.where((e) => e != option).toList()
          : [...current.choices, option];
    } else {
      next = [option];
    }
    answers[index] = current.copyWith(choices: next);
    edited.add(question.id);
  }

  /// 作答中离开前确认；回传 true 表示已离开
  Future<void> confirmLeave() async {
    final busy = stage.value == UserExamStage.running ||
        stage.value == UserExamStage.reviewing ||
        stage.value == UserExamStage.submitting;
    if (busy) {
      final ok = await Get.dialog<bool>(
        AlertDialog(
          content: Text("离开后这次作答会作废（不会记录成绩），确定离开吗？".i18n),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text("留下".i18n),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: Text("离开".i18n),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _cancel?.cancel();
    _timer?.cancel();
    Get.back();
  }

  void _startCountdown() {
    _timer?.cancel();
    void tick() {
      final current = draft.value;
      if (current == null) return;
      final left = current.paper.deadline.difference(DateTime.now()).inSeconds;
      secondsLeft.value = left < 0 ? 0 : left;
      if (left <= 0 && stage.value == UserExamStage.reviewing) {
        _timer?.cancel();
        errorText.value = "已经超过作答时间，这份考卷作废了，请重新开始".i18n;
        stage.value = UserExamStage.failed;
      }
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  void onClose() {
    _cancel?.cancel();
    _timer?.cancel();
    super.onClose();
  }
}
