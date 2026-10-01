import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/models/user/user_exam_model.dart';
import 'package:zai_x/services/ai/ai_chat_client.dart';
import 'package:zai_x/services/ai/ai_search_engine.dart';
import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/ai/ai_search_pipeline.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';

/// 题目里提到的作品，在再漫画查到的资料
class AiExamReference {
  const AiExamReference({
    required this.title,
    required this.kind,
    required this.work,
  });

  /// 题目里写的书名
  final String title;
  final AiSearchKind kind;
  final AiWork work;

  /// 给 AI 看的一行资料
  String describe() {
    final sameName =
        ComicIndexText.normalize(work.title) == ComicIndexText.normalize(title);
    final parts = <String>[
      kind == AiSearchKind.comic ? '漫画' : '轻小说',
      if (work.title.isNotEmpty && !sameName) '站内书名「${work.title}」',
      if (work.authors.isNotEmpty) '作者 ${work.authors}',
      if (work.tags.isNotEmpty) '题材 ${work.tags.join('/')}',
      if (work.status.isNotEmpty) work.status,
    ];
    final description = AiSearchEngine.clip(
      AiSearchEngine.cleanDescription(work.description),
      AiExamSolver.descriptionLimit,
    );
    return '《$title》：${parts.join('，')}'
        '${description.isEmpty ? '' : '。简介：$description'}';
  }
}

/// AI 作答题库认证：查站内作品资料 → 分批作答 → 没把握的再想一次
///
/// 送给 AI 的只有题目、选项，以及题目提到的作品在再漫画的公开资料。
class AiExamSolver {
  AiExamSolver({required this.chat, required this.backend, this.onError});

  final AiJsonChat chat;
  final AiSearchBackend backend;

  /// 个别请求失败时的记录（不会中断作答）
  final void Function(Object error)? onError;

  /// 第一轮每批几题（各批同时送出）
  static const int batchSize = 10;

  /// 复查每批几题
  static const int recheckBatchSize = 8;

  /// 把握低于这个值的题目再想一次
  static const double recheckBelow = 0.6;

  /// 一份考卷最多查几部作品
  static const int maxReferences = 36;

  /// 每部作品的简介最多几个字
  static const int descriptionLimit = 160;

  /// 两轮作答后仍缺几题以内用猜的补上；更多就当作失败，不交卷
  static const int maxGuesses = 3;

  static final RegExp _titlePattern = RegExp(r'[《『]([^《》『』]{1,40})[》』]');

  /// 题干与选项里用书名号标出的书名（去重，保留顺序）
  static List<String> titlesOf(UserExamQuestion question) {
    final seen = <String>{};
    final titles = <String>[];
    for (final text in [question.title, ...question.options]) {
      for (final match in _titlePattern.allMatches(text)) {
        final title = match.group(1)!.trim();
        final key = ComicIndexText.normalize(title);
        if (key.isEmpty || !seen.add(key)) continue;
        titles.add(title);
      }
    }
    return titles;
  }

  Future<List<UserExamAnswer>> solve(
    UserExamPaper paper, {
    CancelToken? cancel,
    void Function(String stage)? onStage,
  }) async {
    final questions = paper.questions;
    if (questions.isEmpty) throw AppError('没有取得题目');

    final titles = <String>[];
    final keys = <String>{};
    for (final question in questions) {
      for (final title in titlesOf(question)) {
        if (keys.add(ComicIndexText.normalize(title))) titles.add(title);
      }
    }
    final wanted = titles.take(maxReferences).toList();
    var references = const <String, AiExamReference>{};
    if (wanted.isNotEmpty) {
      onStage?.call('正在查询题目提到的 ${wanted.length} 部作品…');
      references = await _lookup(wanted, cancel);
      _throwIfCancelled(cancel);
    }

    onStage?.call('AI 正在作答 ${questions.length} 道题…');
    final answers = <int, UserExamAnswer>{};
    final batches = split(questions, batchSize);
    final first = await Future.wait([
      for (final batch in batches) _ask(batch, references, cancel: cancel),
    ]);
    _throwIfCancelled(cancel);
    for (final result in first) {
      if (result != null) answers.addAll(result);
    }

    // 没把握或这轮没答到的题，提高思考程度再问一次
    final unsure = [
      for (final question in questions)
        if ((answers[question.id]?.confidence ?? -1) < recheckBelow) question,
    ];
    if (unsure.isNotEmpty) {
      onStage?.call('AI 正在复查 ${unsure.length} 道没把握的题…');
      final second = await Future.wait([
        for (final batch in split(unsure, recheckBatchSize))
          _ask(batch, references, previous: answers, cancel: cancel),
      ]);
      _throwIfCancelled(cancel);
      for (final result in second) {
        if (result != null) answers.addAll(result);
      }
    }

    final missing = questions.where((e) => !answers.containsKey(e.id)).length;
    if (missing > maxGuesses) {
      throw AppError('AI 作答失败，请稍后再试');
    }
    return [
      for (final question in questions) answers[question.id] ?? guess(question),
    ];
  }

  /// AI 没给答案时的猜测：单选选 A，多选全选；把握记为 0
  static UserExamAnswer guess(UserExamQuestion question) => UserExamAnswer(
        questionId: question.id,
        choices: question.multiple
            ? List<int>.generate(question.options.length, (i) => i)
            : const [0],
      );

  /// 一批题交给 AI；失败会再试一次，仍失败回 null（取消会往外丢）
  Future<Map<int, UserExamAnswer>?> _ask(
    List<UserExamQuestion> batch,
    Map<String, AiExamReference> references, {
    Map<int, UserExamAnswer>? previous,
    CancelToken? cancel,
  }) async {
    final related = <AiExamReference>[];
    final seen = <String>{};
    for (final question in batch) {
      for (final title in titlesOf(question)) {
        final key = ComicIndexText.normalize(title);
        final reference = references[key];
        if (reference != null && seen.add(key)) related.add(reference);
      }
    }
    final recheck = previous != null;
    for (var attempt = 0; attempt < 2; attempt++) {
      _throwIfCancelled(cancel);
      try {
        final json = await chat.completeJson(
          system: systemPrompt(recheck: recheck),
          user: userPrompt(batch, related, previous: previous),
          // 冷门题靠回想，留多一点推理；复查时再提高
          reasoningEffort: recheck ? 'high' : 'medium',
          cancel: cancel,
        );
        final parsed = parseAnswers(json, batch);
        if (parsed.isNotEmpty) return parsed;
      } on AiSearchCancelled {
        rethrow;
      } catch (e) {
        onError?.call(e);
      }
    }
    return null;
  }

  static String systemPrompt({required bool recheck}) => [
        '你在帮用户作答「再漫画」网站 Lv4 升 Lv5 的「终极试炼之【题库认证】」。'
            '题目涵盖漫画、动画、轻小说、游戏、动漫音乐等 ACG 知识，以及网站的社区规范。',
        '作答规则：',
        '1. type 为「单选」只能选一个选项；「多选」要选出所有正确的选项（至少一个，也可能全选）。',
        '2. 看清楚题干问的是谁、对谁、哪一个，留意「不是」「不正确」「不会」「没有」这类否定词。',
        '3. 社区规范题依文明友善、遵守法律法规、不引战不刷屏、不发广告与可疑链接、'
            '遇到问题举报给管理员的原则作答。',
        '4. 「参考资料」是再漫画站内的作品资料，和题目有关时优先采用；'
            '资料没提到的依你的知识判断，不要因为资料没写就否定。',
        '5. 每题都要作答；不确定时选最有可能的答案，并在 confidence 如实写出把握（0～1）。',
        if (recheck)
          '6. 这些题第一次作答时把握不高（first 是第一次的答案）。'
              '请重新审题、回想作品设定与相关知识后给出最终答案；第一次答对就保留。',
        '只回传 JSON：{"answers":[{"id":题目id,"choice":"A" 或 "A,C","confidence":0到1的小数}]}，'
            '不要其它文字。',
      ].join('\n');

  static String userPrompt(
    List<UserExamQuestion> batch,
    List<AiExamReference> references, {
    Map<int, UserExamAnswer>? previous,
  }) {
    final buffer = StringBuffer();
    if (references.isNotEmpty) {
      buffer.writeln('参考资料（再漫画站内的作品资料）：');
      for (final reference in references) {
        buffer.writeln('- ${reference.describe()}');
      }
      buffer.writeln();
    }
    buffer.writeln('题目：');
    buffer.write(jsonEncode([
      for (final question in batch)
        {
          'id': question.id,
          'type': question.multiple ? '多选' : '单选',
          'title': question.title,
          'options': {
            for (var i = 0; i < question.options.length; i++)
              UserExamAnswer.optionLetter(i): question.options[i],
          },
          if (previous?[question.id] != null)
            'first': previous![question.id]!.letters,
        },
    ]));
    return buffer.toString();
  }

  /// 读出 AI 的答案；不在这批、选项超出范围或没选的略过
  static Map<int, UserExamAnswer> parseAnswers(
    Map<String, dynamic> json,
    List<UserExamQuestion> batch,
  ) {
    final byId = {for (final question in batch) question.id: question};
    final answers = <int, UserExamAnswer>{};
    final list = json['answers'];
    if (list is! List) return answers;
    for (final item in list) {
      if (item is! Map) continue;
      final id = switch (item['id']) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v.trim()) ?? 0,
        _ => 0,
      };
      final question = byId[id];
      if (question == null) continue;
      var choices = parseChoice(
        item['choice'] ?? item['answer'],
        question.options.length,
      );
      if (choices.isEmpty) continue;
      if (!question.multiple && choices.length > 1) choices = [choices.first];
      answers[id] = UserExamAnswer(
        questionId: id,
        choices: choices,
        confidence: parseConfidence(item['confidence']),
      );
    }
    return answers;
  }

  /// 「A」「A,C」「AC」「A、C」或 ["A","C"] → 选项索引（0 起算）
  static List<int> parseChoice(dynamic value, int optionCount) {
    final text = value is List ? value.join(',') : '${value ?? ''}';
    final picked = <int>{};
    for (final token in text.split(RegExp(r'[^A-Za-z]+'))) {
      if (token.isEmpty) continue;
      // 单个字母可以是小写；连写的只认大写，避免把英文单字当成选项
      final letters = token.length == 1 ? token.toUpperCase() : token;
      if (letters.length > optionCount || letters != letters.toUpperCase()) {
        continue;
      }
      final indexes = [for (final unit in letters.codeUnits) unit - 65];
      if (indexes.any((i) => i < 0 || i >= optionCount)) continue;
      picked.addAll(indexes);
    }
    return picked.toList()..sort();
  }

  static double parseConfidence(dynamic value) {
    var number = switch (value) {
      num v => v.toDouble(),
      String v => double.tryParse(v.replaceAll('%', '').trim()) ?? 0.5,
      _ => 0.5,
    };
    if (number > 1) number /= 100;
    return number.clamp(0.0, 1.0).toDouble();
  }

  /// 依序切成每批 [size] 个
  static List<List<T>> split<T>(List<T> items, int size) => [
        for (var i = 0; i < items.length; i += size)
          items.sublist(i, i + size > items.length ? items.length : i + size),
      ];

  Future<Map<String, AiExamReference>> _lookup(
    List<String> titles,
    CancelToken? cancel,
  ) async {
    final results = List<AiExamReference?>.filled(titles.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < titles.length && !(cancel?.isCancelled ?? false)) {
        final index = next++;
        try {
          results[index] = await _resolve(titles[index]);
        } catch (e) {
          onError?.call(e);
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < 6 && i < titles.length; i++) worker(),
    ]);
    return {
      for (var i = 0; i < titles.length; i++)
        if (results[i] != null)
          ComicIndexText.normalize(titles[i]): results[i]!,
    };
  }

  /// 先找漫画（含本地索引里的神隐作品），找不到再找轻小说
  Future<AiExamReference?> _resolve(String title) async {
    final key = ComicIndexText.normalize(title);
    // 太短的书名只认完全相同，避免「EVA」对到不相干的作品
    final minLevel = key.length >= 4 ? 1 : 2;
    for (final kind in AiSearchKind.values) {
      AiWork? best;
      var bestLevel = 0;
      try {
        for (final work in (await backend.search(kind, title, 0)).take(10)) {
          final level = AiSearchEngine.titleMatch(title, work.title,
              aliases: work.aliases);
          if (level > bestLevel) {
            best = work;
            bestLevel = level;
          }
          if (level == 2) break;
        }
      } catch (e) {
        onError?.call(e);
      }
      if (bestLevel < 2 && kind == AiSearchKind.comic) {
        try {
          for (final hit in await backend.index(kind, title, 5)) {
            final level = hit.tier <= 1
                ? 2
                : AiSearchEngine.titleMatch(title, hit.work.title);
            if (level > bestLevel) {
              best = hit.work;
              bestLevel = level;
            }
          }
        } catch (e) {
          onError?.call(e);
        }
      }
      if (best == null || bestLevel < minLevel) continue;
      var work = best;
      try {
        work = best.mergedWith(await backend.detail(kind, best.id));
      } catch (e) {
        onError?.call(e);
      }
      return AiExamReference(title: title, kind: kind, work: work);
    }
    return null;
  }

  static void _throwIfCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const AiSearchCancelled();
  }
}
