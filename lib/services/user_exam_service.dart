import 'package:dio/dio.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/models/user/user_exam_model.dart';
import 'package:zai_x/requests/user_request.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_exam_solver.dart';
import 'package:zai_x/services/ai/ai_search_engine.dart';
import 'package:zai_x/services/ai/ai_search_service.dart';
import 'package:zai_x/services/ai/ai_service_config.dart';
import 'package:zai_x/services/local_storage_service.dart';

/// AI 作答完、还没交卷的考卷
class UserExamDraft {
  UserExamDraft(this.paper, List<UserExamAnswer> answers)
      : answers = List.of(answers);

  final UserExamPaper paper;
  final List<UserExamAnswer> answers;

  /// 把握低于复查门槛的题数
  int get unsureCount =>
      answers.where((e) => e.confidence < AiExamSolver.recheckBelow).length;
}

/// 终极试炼之【题库认证】的 AI 一键答题
class UserExamService {
  UserExamService._(AiServiceConfig? config)
      : _solver = config == null
            ? null
            : AiExamSolver(
                chat: AiChatClient(
                  config,
                  // 复查用较高的思考程度，回应会比 AI 搜索久
                  dio: Dio(BaseOptions(
                    connectTimeout: const Duration(seconds: 15),
                    sendTimeout: const Duration(seconds: 20),
                    receiveTimeout: const Duration(seconds: 150),
                  )),
                ),
                backend: AppAiSearchBackend(),
                onError: Log.logPrint,
              );

  static final UserExamService instance =
      UserExamService._(AiServiceConfig.current);

  final AiExamSolver? _solver;
  final UserRequest _request = UserRequest();

  /// 每台装置每天最多几次（每次约用掉两三次 AI 搜索的额度）
  static const int dailyLimit = 5;

  /// 这个建置有没有内建 AI 服务
  bool get available => _solver != null;

  /// 今天还能用几次
  int get remainingToday {
    final value = LocalStorageService.instance
        .getValue<dynamic>(LocalStorageService.kAiExamQuota, '');
    final parts = (value is String ? value : '').split('|');
    final used =
        parts.length == 2 && parts[0] == AiSearchEngine.dateKey(DateTime.now())
            ? int.tryParse(parts[1]) ?? 0
            : 0;
    return (dailyLimit - used).clamp(0, dailyLimit);
  }

  /// 交卷前先让使用者检查
  bool get reviewFirst => LocalStorageService.instance
      .getValue<bool>(LocalStorageService.kAiExamReviewFirst, false);

  Future<void> setReviewFirst(bool value) => LocalStorageService.instance
      .setValue(LocalStorageService.kAiExamReviewFirst, value);

  /// 取得考卷并让 AI 作答（还没交卷）
  Future<UserExamDraft> draft({
    CancelToken? cancel,
    void Function(String stage)? onStage,
  }) async {
    final solver = _solver;
    if (solver == null) throw AppError('这个版本没有内建 AI 服务');
    onStage?.call('正在确认试炼资格…');
    final prepare = await _request.examPrepare();
    if (!prepare.ready) throw AppError(prepare.message);
    await _consumeQuota();
    if (cancel?.isCancelled ?? false) throw const AiSearchCancelled();
    onStage?.call('正在领取考卷…');
    final paper = await _request.examPaper();
    if (paper.sessionId.isEmpty || paper.questions.isEmpty) {
      throw AppError('没有取得题目，请稍后再试');
    }
    final answers = await solver.solve(paper, cancel: cancel, onStage: onStage);
    return UserExamDraft(paper, answers);
  }

  /// 交卷
  Future<UserExamScore> submit(UserExamDraft draft) async {
    if (DateTime.now().isAfter(draft.paper.deadline)) {
      throw AppError('已经超过作答时间，这份考卷作废了，请重新开始');
    }
    return _request.examSubmit(
      sessionId: draft.paper.sessionId,
      answer: UserExamAnswer.encode(draft.answers),
    );
  }

  Future<void> _consumeQuota() async {
    final storage = LocalStorageService.instance;
    final value =
        storage.getValue<dynamic>(LocalStorageService.kAiExamQuota, '');
    final result = AiSearchEngine.consumeQuota(
      value is String ? value : '',
      DateTime.now(),
      limit: dailyLimit,
    );
    await storage.setValue(LocalStorageService.kAiExamQuota, result.stored);
    if (!result.allowed) {
      throw AppError('今天的 AI 答题次数已用完（每天 $dailyLimit 次），明天再来吧');
    }
  }
}
