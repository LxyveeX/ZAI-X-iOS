import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/controller/base_controller.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/models/user/task_model.dart';
import 'package:zai_x/models/user/user_exam_model.dart';
import 'package:zai_x/models/user/user_level_model.dart';
import 'package:zai_x/requests/user_request.dart';
import 'package:zai_x/routes/app_navigator.dart';
import 'package:zai_x/services/user_exam_service.dart';
import 'package:zai_x/services/user_service.dart';

/// 用户等级：特权、晋升条件，以及题库认证的 AI 一键答题入口
class UserLevelController extends BaseController {
  final UserRequest request = UserRequest();

  final info = Rxn<UserLevelInfo>();

  /// 目前积分（与任务中心同一个来源）
  final credits = RxnInt();

  /// 题库认证最近一次的成绩
  final lastScore = Rxn<UserExamScore>();

  /// 题库认证现在能不能考
  final prepare = Rxn<UserExamPrepare>();

  final reviewFirst = UserExamService.instance.reviewFirst.obs;
  final remaining = UserExamService.instance.remainingToday.obs;

  @override
  void onInit() {
    load();
    super.onInit();
  }

  Future<void> load() async {
    if (!UserService.instance.logined.value) {
      pageError.value = true;
      errorMsg.value = "请先登录".i18n;
      pageLoadding.value = false;
      return;
    }
    try {
      pageLoadding.value = info.value == null;
      pageError.value = false;
      final level = await request.userLevelInfo();
      info.value = level;
      remaining.value = UserExamService.instance.remainingToday;
      // 积分与试炼状态只是附加资讯，拿不到不影响页面
      final exam = level.exam;
      await Future.wait([
        _quietly(() async =>
            credits.value = parseUserCredits(await request.taskListRaw())),
        if (exam != null && !exam.completed) ...[
          _quietly(() async => lastScore.value = await request.examReview()),
          _quietly(() async => prepare.value = await request.examPrepare()),
        ],
      ]);
    } catch (e) {
      Log.logPrint(e);
      if (info.value == null) {
        pageError.value = true;
        errorMsg.value = e.toString();
      } else {
        SmartDialog.showToast(e.toString());
      }
    } finally {
      pageLoadding.value = false;
    }
  }

  Future<void> _quietly(Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      Log.logPrint(e);
    }
  }

  void setReviewFirst(bool value) {
    reviewFirst.value = value;
    UserExamService.instance.setReviewFirst(value);
  }

  Future<void> startExam() async {
    final service = UserExamService.instance;
    if (!service.available) {
      SmartDialog.showToast("这个版本没有内建 AI 服务".i18n);
      return;
    }
    final left = service.remainingToday;
    if (left <= 0) {
      SmartDialog.showToast("今天的 AI 答题次数已用完，明天再来吧".i18n);
      return;
    }
    final flow = reviewFirst.value
        ? "AI 会领取一份新考卷，查询题目提到的作品资料后作答，再交给你检查与修改，请在 30 分钟内交卷。"
        : "AI 会领取一份新考卷，查询题目提到的作品资料后作答，并自动交卷。";
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text("AI 一键答题".i18n),
        content: Text(
          "${flow.i18n}\n\n"
          "${"答案由 AI 判断，不保证过关；没过关可以再试一次。".i18n}"
          "${"今天还能用 $left 次。".i18n}",
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text("取消".i18n),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text("开始答题".i18n),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppNavigator.toUserExam(reviewFirst: reviewFirst.value);
    remaining.value = service.remainingToday;
    await load();
  }
}
