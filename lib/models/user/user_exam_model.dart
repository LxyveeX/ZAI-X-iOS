import 'dart:convert';

/// 终极试炼之【题库认证】的资料（account-api /v1/auth/*）
///
/// 官方 H5（user-auth.zaimanhua.com）的流程：prepare 看能不能考 → question_list
/// 出 50 题并给 session_id → post 交卷（answer 是 {题目id: "A" 或 "A,C"} 的 JSON 字串）
/// → review 看最近一次的分数。题目不附答案（correct_option 一律是空字串）。
class UserExamQuestion {
  UserExamQuestion({
    required this.id,
    required this.title,
    required this.options,
    required this.multiple,
    required this.difficulty,
  });

  final int id;
  final String title;
  final List<String> options;

  /// 多选题（select_type == 2）
  final bool multiple;

  /// 1 送分题、2 正常题、3 地狱题
  final int difficulty;

  factory UserExamQuestion.fromJson(Map<String, dynamic> json) =>
      UserExamQuestion(
        id: _int(json['id']),
        title: '${json['title'] ?? ''}'.trim(),
        options: [
          for (final item in _list(json['option_list'])) '$item'.trim(),
        ],
        multiple: _int(json['select_type']) == 2,
        difficulty: _int(json['difficulty']),
      );
}

/// 一份考卷
class UserExamPaper {
  UserExamPaper({
    required this.sessionId,
    required this.countDown,
    required this.questions,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  final String sessionId;

  /// 作答时限（秒）
  final int countDown;
  final List<UserExamQuestion> questions;

  /// 拿到考卷的时间，用来算剩余时间
  final DateTime receivedAt;

  /// 交卷期限
  DateTime get deadline => receivedAt.add(Duration(seconds: countDown));

  factory UserExamPaper.fromJson(Map<String, dynamic> data) => UserExamPaper(
        sessionId: '${data['session_id'] ?? ''}',
        countDown: _int(data['count_down_time']) > 0
            ? _int(data['count_down_time'])
            : 1800,
        questions: [
          for (final item in _list(data['question_list']))
            if (item is Map)
              UserExamQuestion.fromJson(Map<String, dynamic>.from(item)),
        ]..removeWhere((e) => e.id == 0 || e.options.isEmpty),
      );
}

/// 能不能开始作答（errMsg 不是空的就不能考，例如等级不够或次数用完）
class UserExamPrepare {
  UserExamPrepare({required this.message, required this.countDown});

  final String message;
  final int countDown;

  bool get ready => message.isEmpty;

  factory UserExamPrepare.fromJson(Map<String, dynamic> data) =>
      UserExamPrepare(
        message: '${data['errMsg'] ?? data['err_msg'] ?? ''}'.trim(),
        countDown: _int(data['count_down_time']),
      );
}

/// 最近一次（或这次交卷）的成绩
class UserExamScore {
  UserExamScore({required this.id, required this.score, required this.passed});

  /// 0 表示还没考过
  final int id;
  final num score;
  final bool passed;

  bool get taken => id != 0 || score > 0 || passed;

  factory UserExamScore.fromJson(Map<String, dynamic> data) => UserExamScore(
        id: _int(data['id']),
        score: switch (data['score']) {
          num v => v,
          String v => num.tryParse(v) ?? 0,
          _ => 0,
        },
        passed: _int(data['is_pass']) == 1 || data['is_pass'] == true,
      );
}

/// 一题的作答
class UserExamAnswer {
  UserExamAnswer({
    required this.questionId,
    required List<int> choices,
    this.confidence = 0,
  }) : choices = (choices.toSet().toList()..sort());

  final int questionId;

  /// 选了哪些选项（0 起算，已排序）
  final List<int> choices;

  /// AI 的把握（0～1）
  final double confidence;

  UserExamAnswer copyWith({List<int>? choices, double? confidence}) =>
      UserExamAnswer(
        questionId: questionId,
        choices: choices ?? this.choices,
        confidence: confidence ?? this.confidence,
      );

  /// 「A」或「A,C」
  String get letters => choices.map(optionLetter).join(',');

  static String optionLetter(int index) =>
      index >= 0 && index < 26 ? String.fromCharCode(65 + index) : '?';

  /// 交卷用的 answer 字串：{"题目id":"A","题目id":"A,C"}，没选的题不送
  static String encode(Iterable<UserExamAnswer> answers) => jsonEncode({
        for (final answer in answers)
          if (answer.choices.isNotEmpty) '${answer.questionId}': answer.letters,
      });
}

List<dynamic> _list(dynamic value) {
  if (value is List) return value;
  // 官方 H5 用 Object.entries 读，保险起见也接受 {"0": {...}} 的写法
  if (value is Map) return value.values.toList();
  return const [];
}

int _int(dynamic value) => switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
