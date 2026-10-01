import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/models/user/user_exam_model.dart';
import 'package:zai_x/models/user/user_level_model.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_exam_solver.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_search_pipeline.dart';

/// 假 AI：依题目 id 回答；[recheck] 是复查时改用的答案
class _FakeChat implements AiJsonChat {
  _FakeChat(this.first, {this.recheck = const {}, this.failures = 0});

  /// id → (choice, confidence)；没列到的题不回答
  final Map<int, (String, double)> first;
  final Map<int, (String, double)> recheck;

  /// 前几个请求直接失败
  int failures;
  final List<({String system, String user, String? effort})> calls = [];

  @override
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required String user,
    String? reasoningEffort,
    CancelToken? cancel,
  }) async {
    calls.add((system: system, user: user, effort: reasoningEffort));
    if (failures > 0) {
      failures--;
      throw Exception('ai failed');
    }
    final isRecheck = system.contains('first 是第一次的答案');
    final answers = <Map<String, dynamic>>[];
    for (final item in _questionsIn(user)) {
      final id = item['id'] as int;
      final picked = (isRecheck ? recheck[id] : null) ?? first[id];
      if (picked == null) continue;
      answers.add({'id': id, 'choice': picked.$1, 'confidence': picked.$2});
    }
    return {'answers': answers};
  }
}

List<Map<String, dynamic>> _questionsIn(String prompt) {
  final start = prompt.indexOf('题目：\n');
  return [
    for (final item in jsonDecode(prompt.substring(start + 4)) as List)
      Map<String, dynamic>.from(item as Map),
  ];
}

class _FakeBackend implements AiSearchBackend {
  _FakeBackend(this.works);

  /// 书名 → 作品
  final Map<String, AiWork> works;
  final List<String> calls = [];

  @override
  Future<List<AiWork>> filter(
    AiSearchKind kind,
    AiSearchPlan plan,
    AiTag? tag,
    int page,
  ) async =>
      const [];

  @override
  Future<List<AiWork>> search(
    AiSearchKind kind,
    String keyword,
    int page,
  ) async {
    calls.add('search:${kind.name}:$keyword');
    final work = works[keyword];
    return kind == AiSearchKind.comic && work != null ? [work] : const [];
  }

  @override
  Future<List<AiIndexHit>> index(
    AiSearchKind kind,
    String keyword,
    int limit,
  ) async =>
      const [];

  @override
  Future<AiWork> detail(AiSearchKind kind, int id) async {
    calls.add('detail:$id');
    final work = works.values.firstWhere((e) => e.id == id);
    return AiWork(
        id: id, title: work.title, description: '简介：${work.title}的故事');
  }
}

UserExamQuestion _q(
  int id,
  String title, {
  bool multiple = false,
  int difficulty = 2,
  List<String> options = const ['甲', '乙', '丙', '丁'],
}) =>
    UserExamQuestion(
      id: id,
      title: title,
      options: options,
      multiple: multiple,
      difficulty: difficulty,
    );

UserExamPaper _paper(List<UserExamQuestion> questions) => UserExamPaper(
      sessionId: 'session',
      countDown: 1800,
      questions: questions,
    );

void main() {
  group('等级资料', () {
    test('读出特权、晋升条件与题库认证', () {
      final info = UserLevelInfo.fromJson({
        'currentUserLevelDetail': {
          'userLevel': 4,
          'name': 'Lv4',
          'privilege': ['访问漫画分类/排行/专题', '发私信', ' '],
          'or_conditions': [
            {
              'list': [
                {
                  'con': '终极试炼之【题库认证】',
                  'is_completed': false,
                  'url':
                      'https://user-auth.zaimanhua.com/#/?channel=android&app_view=1',
                },
              ],
            },
            {
              'list': [
                {'con': '积分达到1500', 'is_completed': false, 'url': ''},
              ],
            },
          ],
        },
        'userLevelList': [
          for (var i = 5; i >= 0; i--) {'userLevel': i, 'name': 'Lv$i'},
        ],
      });
      expect(info.level, 4);
      expect(info.privileges, ['访问漫画分类/排行/专题', '发私信']);
      expect(info.conditionGroups.length, 2);
      expect(info.levels, [0, 1, 2, 3, 4, 5]);
      expect(info.isMaxLevel, isFalse);
      expect(info.exam?.content, '终极试炼之【题库认证】');
      expect(info.conditionGroups[1].single.isExam, isFalse);
    });

    test('最高等级没有晋升条件', () {
      final info = UserLevelInfo.fromJson({
        'currentUserLevelDetail': {'userLevel': '5', 'or_conditions': []},
        'userLevelList': [
          {'userLevel': 0},
          {'userLevel': 5},
        ],
      });
      expect(info.level, 5);
      expect(info.isMaxLevel, isTrue);
      expect(info.exam, isNull);
    });
  });

  group('考卷与交卷格式', () {
    test('读出题目，略过不完整的题', () {
      final paper = UserExamPaper.fromJson({
        'session_id': 'abc',
        'question_list': [
          {
            'id': 77,
            'title': '台词是对谁说的',
            'option_list': ['A1', 'B1', 'C1', 'D1'],
            'select_type': 1,
            'difficulty': 1,
            'correct_option': '',
          },
          {
            'id': 8,
            'title': '多选题',
            'option_list': ['A2', 'B2', 'C2', 'D2'],
            'select_type': 2,
            'difficulty': 3,
          },
          {'id': 0, 'title': '坏资料', 'option_list': []},
        ],
      });
      expect(paper.sessionId, 'abc');
      expect(paper.countDown, 1800);
      expect(paper.questions.map((e) => e.id), [77, 8]);
      expect(paper.questions[1].multiple, isTrue);
      expect(paper.questions[1].difficulty, 3);
      expect(
        paper.deadline.difference(paper.receivedAt),
        const Duration(minutes: 30),
      );
    });

    test('也接受以物件包装的题目清单', () {
      final paper = UserExamPaper.fromJson({
        'session_id': 'abc',
        'count_down_time': 600,
        'question_list': {
          '0': {
            'id': 3,
            'title': '题',
            'option_list': ['a', 'b'],
          },
        },
      });
      expect(paper.countDown, 600);
      expect(paper.questions.single.id, 3);
    });

    test('交卷字串与官方 H5 相同：题目 id 对应字母，多选以逗号分隔', () {
      final text = UserExamAnswer.encode([
        UserExamAnswer(questionId: 77, choices: const [2]),
        UserExamAnswer(questionId: 8, choices: const [3, 0, 1, 1]),
        UserExamAnswer(questionId: 9, choices: const []),
      ]);
      expect(jsonDecode(text), {'77': 'C', '8': 'A,B,D'});
    });

    test('成绩与资格', () {
      final score = UserExamScore.fromJson({
        'id': 20812,
        'is_pass': 0,
        'score': '50',
      });
      expect(score.taken, isTrue);
      expect(score.passed, isFalse);
      expect(score.score, 50);
      expect(UserExamScore.fromJson({'id': 0}).taken, isFalse);
      expect(UserExamScore.fromJson({'is_pass': 1, 'score': 72}).passed, true);
      expect(UserExamPrepare.fromJson({'errMsg': ''}).ready, isTrue);
      expect(
        UserExamPrepare.fromJson({'errMsg': '今日次数已用完'}).message,
        '今日次数已用完',
      );
    });
  });

  group('读 AI 的答案', () {
    test('选项字母的各种写法', () {
      expect(AiExamSolver.parseChoice('A', 4), [0]);
      expect(AiExamSolver.parseChoice('A,C', 4), [0, 2]);
      expect(AiExamSolver.parseChoice('CA', 4), [0, 2]);
      expect(AiExamSolver.parseChoice('A、D', 4), [0, 3]);
      expect(AiExamSolver.parseChoice(['B', 'd'], 4), [1, 3]);
      expect(AiExamSolver.parseChoice('Answer: B', 4), [1]);
      expect(AiExamSolver.parseChoice('E', 4), isEmpty);
      expect(AiExamSolver.parseChoice(null, 4), isEmpty);
    });

    test('单选只取一个，不在这批或选项不合法的略过', () {
      final batch = [_q(1, '单选'), _q(2, '多选', multiple: true)];
      final answers = AiExamSolver.parseAnswers({
        'answers': [
          {'id': 1, 'choice': 'B,C', 'confidence': 0.9},
          {'id': '2', 'choice': 'A,D', 'confidence': 70},
          {'id': 3, 'choice': 'A'},
          {'id': 2, 'choice': 'Z'},
        ],
      }, batch);
      expect(answers.keys, [1, 2]);
      expect(answers[1]!.choices, [1]);
      expect(answers[2]!.choices, [0, 3]);
      expect(answers[2]!.confidence, closeTo(0.7, 1e-9));
    });

    test('把握的写法', () {
      expect(AiExamSolver.parseConfidence(0.4), 0.4);
      expect(AiExamSolver.parseConfidence('90%'), closeTo(0.9, 1e-9));
      expect(AiExamSolver.parseConfidence(null), 0.5);
      expect(AiExamSolver.parseConfidence(-2), 0);
    });

    test('从题干与选项取出书名，去掉重复', () {
      final titles = AiExamSolver.titlesOf(_q(
        1,
        '漫画《画皮酱》中，女主本体是？与『画皮酱』有关',
        options: ['《三月的惊雷》', '《画皮酱》', '普通选项', '《 》'],
      ));
      expect(titles, ['画皮酱', '三月的惊雷']);
    });
  });

  group('AI 作答流程', () {
    test('附上站内资料作答，没把握的题提高思考程度复查', () async {
      final chat = _FakeChat(
        {1: ('B', 0.9), 2: ('A', 0.3), 3: ('A,B', 0.8)},
        recheck: {2: ('C', 0.7)},
      );
      final backend = _FakeBackend({
        '画皮酱': AiWork(id: 11, title: '画皮酱'),
      });
      final solver = AiExamSolver(chat: chat, backend: backend);
      final stages = <String>[];
      final answers = await solver.solve(
        _paper([
          _q(1, '社区规范题'),
          _q(2, '漫画《画皮酱》中，女主本体是？'),
          _q(3, '多选题', multiple: true),
        ]),
        onStage: stages.add,
      );
      expect(answers.map((e) => e.questionId), [1, 2, 3]);
      expect(answers[0].choices, [1]);
      expect(answers[1].choices, [2], reason: '复查的答案取代第一次的');
      expect(answers[2].choices, [0, 1]);
      expect(chat.calls.first.effort, 'medium');
      expect(chat.calls.first.user, contains('《画皮酱》：漫画'));
      expect(chat.calls.first.user, contains('画皮酱的故事'));
      final recheck = chat.calls.last;
      expect(recheck.effort, 'high');
      expect(_questionsIn(recheck.user).map((e) => e['id']), [2]);
      expect(_questionsIn(recheck.user).single['first'], 'A');
      expect(stages.any((e) => e.contains('复查 1 道')), isTrue);
    });

    test('请求失败会重试一次', () async {
      final chat = _FakeChat({1: ('A', 0.9)}, failures: 1);
      final solver = AiExamSolver(chat: chat, backend: _FakeBackend({}));
      final answers = await solver.solve(_paper([_q(1, '题')]));
      expect(answers.single.choices, [0]);
      expect(chat.calls.length, 2);
    });

    test('少数题没答到时用猜的补上，太多就不交卷', () async {
      final few = AiExamSolver(
        chat: _FakeChat({1: ('B', 0.9)}),
        backend: _FakeBackend({}),
      );
      final answers = await few.solve(_paper([
        _q(1, '题'),
        _q(2, '单选没答到'),
        _q(3, '多选没答到', multiple: true),
      ]));
      expect(answers[1].choices, [0]);
      expect(answers[2].choices, [0, 1, 2, 3]);
      expect(answers[2].confidence, 0);

      final many = AiExamSolver(
        chat: _FakeChat({}, failures: 100),
        backend: _FakeBackend({}),
      );
      await expectLater(
        many.solve(_paper([for (var i = 1; i <= 5; i++) _q(i, '题$i')])),
        throwsA(isA<AppError>()),
      );
    });
  });
}
