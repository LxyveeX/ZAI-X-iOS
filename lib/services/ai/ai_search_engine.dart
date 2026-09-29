import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';

/// 候选作品的来源
enum AiHitSource {
  /// 依题材、受众等条件列出的作品
  filter,

  /// AI 点名的具体作品
  title,

  /// 书名或作者关键词
  keyword,
}

/// 从某个来源找到的一部作品
class AiCandidateHit {
  const AiCandidateHit(this.work, this.source, this.rank);

  final AiWork work;
  final AiHitSource source;

  /// 在来源清单里的名次，从 0 起算
  final int rank;
}

/// AI 搜索的纯逻辑：提示词、解析 AI 回覆、候选排序与每日次数
abstract final class AiSearchEngine {
  static const int maxThemes = 3;
  static const int maxTitles = 6;
  static const int maxKeywords = 4;
  static const int maxCandidates = 24;
  static const int maxResults = 10;
  static const int descriptionLimit = 120;
  static const int reasonLimit = 60;
  static const int queryLimit = 200;

  /// 每台装置每天可用的 AI 搜索次数
  static const int dailyLimit = 50;

  static String kindName(AiSearchKind kind) =>
      kind == AiSearchKind.novel ? '轻小说' : '漫画';

  // 第一步：理解需求

  static String planSystemPrompt(
    AiSearchKind kind,
    AiTagVocabulary vocab,
    DateTime today,
  ) {
    final name = kindName(kind);
    String names(List<AiTag> tags) =>
        tags.isEmpty ? '（无）' : tags.map((e) => e.name).join('、');
    final b = StringBuffer()
      ..writeln('你是「再漫画X」App 的$name搜索助手，负责把用户的描述转换成站内搜索条件。')
      ..writeln('今天是 ${dateKey(today)}。')
      ..writeln('标签只能从下列清单选，名称必须一字不差；没有合适的就留空。')
      ..writeln('题材：${names(vocab.themes)}');
    if (vocab.audiences.isNotEmpty) {
      b.writeln('受众：${names(vocab.audiences)}');
    }
    if (vocab.zones.isNotEmpty) b.writeln('地区：${names(vocab.zones)}');
    if (vocab.statuses.isNotEmpty) b.writeln('进度：${names(vocab.statuses)}');
    b
      ..writeln()
      ..writeln('只输出一个 JSON 物件：')
      ..writeln('{')
      ..writeln('  "summary": "用一句话复述用户想找什么，简体中文，20 字以内",')
      ..writeln('  "themes": ["最关键的题材，最多 $maxThemes 个"],')
      ..writeln('  "exclude_themes": ["用户明确不想要的题材"],');
    if (vocab.audiences.isNotEmpty) {
      b.writeln('  "audience": "受众，没有就空字串",');
    }
    if (vocab.zones.isNotEmpty) b.writeln('  "zone": "地区，没有就空字串",');
    if (vocab.statuses.isNotEmpty) b.writeln('  "status": "进度，没有就空字串",');
    b
      ..writeln('  "titles": ["符合描述、你熟悉且口碑好的具体作品，用中文站常见的简体书名，'
          '最多 $maxTitles 个；描述是类型或氛围时也要列出代表作，'
          '找「类似某作品」时列相似的作品、不要列原作；完全想不到才留空"],')
      ..writeln('  "keywords": ["书名或作者名里可能出现的词，最多 $maxKeywords 个；'
          '用户提到的书名、作者、角色一定要放"],')
      ..writeln('  "sort": "hot 或 new，用户想看新作或最近更新时用 new"')
      ..writeln('}')
      ..writeln('如果用户只输入书名或作者，就放进 keywords，其他栏位留空。');
    return b.toString();
  }

  static AiSearchPlan parsePlan(
    Map<String, dynamic> json,
    AiTagVocabulary vocab,
  ) {
    final themes = <AiTag>[];
    for (final name in _strings(json['themes'], 8)) {
      final tag = matchTag(name, vocab.themes);
      if (tag != null && !themes.contains(tag)) themes.add(tag);
      if (themes.length >= maxThemes) break;
    }
    final exclude = <AiTag>[];
    for (final name in _strings(json['exclude_themes'], 8)) {
      final tag = matchTag(name, vocab.themes);
      if (tag != null && !themes.contains(tag) && !exclude.contains(tag)) {
        exclude.add(tag);
      }
    }
    return AiSearchPlan(
      summary: clip(_text(json['summary']), 40),
      themes: themes,
      excludeThemes: exclude,
      audience: matchTag(_text(json['audience']), vocab.audiences),
      zone: matchTag(_text(json['zone']), vocab.zones),
      status: matchTag(_text(json['status']), vocab.statuses),
      titles: _distinct(_strings(json['titles'], maxTitles)),
      keywords: _distinct(_strings(json['keywords'], maxKeywords)),
      preferNew: _text(json['sort']).toLowerCase() == 'new',
    );
  }

  /// 把 AI 给的名称对到标签：先比完全相同（忽略简繁与大小写），
  /// 再接受唯一一个互相包含的，例如「已完结」对到「完结」
  static AiTag? matchTag(String name, List<AiTag> tags) {
    final key = ComicIndexText.normalize(name);
    if (key.isEmpty) return null;
    AiTag? partial;
    var partialCount = 0;
    for (final tag in tags) {
      final value = ComicIndexText.normalize(tag.name);
      if (value.isEmpty) continue;
      if (value == key) return tag;
      if (value.length >= 2 &&
          key.length >= 2 &&
          (key.contains(value) || value.contains(key))) {
        partial = tag;
        partialCount++;
      }
    }
    return partialCount == 1 ? partial : null;
  }

  // 第二步：合并候选

  /// 合并各来源找到的作品并依条件排序，最多留 [limit] 部
  ///
  /// 带有「不要」题材的直接剔除；题材吻合、被 AI 点名、搜索名次前面的排前面。
  static List<AiWork> rankCandidates(
    AiSearchPlan plan,
    List<AiCandidateHit> hits, {
    int limit = maxCandidates,
  }) {
    final order = <int>[];
    final works = <int, AiWork>{};
    final bonus = <int, double>{};
    for (final hit in hits) {
      final id = hit.work.id;
      if (id <= 0) continue;
      final existing = works[id];
      if (existing == null) {
        order.add(id);
        works[id] = hit.work;
      } else {
        works[id] = existing.mergedWith(hit.work);
      }
      final rank = hit.rank < 0 ? 0 : hit.rank;
      final score = switch (hit.source) {
        AiHitSource.title => 5.0 - (rank < 2 ? rank : 2),
        AiHitSource.keyword => 2.0 - (rank < 5 ? rank : 5) * 0.2,
        AiHitSource.filter => 2.0 * (1 - (rank < 40 ? rank : 40) / 40),
      };
      bonus[id] = (bonus[id] ?? 0) + score;
    }

    final wanted = plan.themes.map((e) => ComicIndexText.normalize(e.name));
    final unwanted =
        plan.excludeThemes.map((e) => ComicIndexText.normalize(e.name)).toSet();
    final status =
        plan.status == null ? '' : ComicIndexText.normalize(plan.status!.name);
    final scored = <({AiWork work, double score, int index})>[];
    for (var i = 0; i < order.length; i++) {
      final work = works[order[i]]!;
      final tags = work.tags.map(ComicIndexText.normalize).toSet();
      if (tags.any(unwanted.contains)) continue;
      var score = bonus[work.id] ?? 0;
      final matched = wanted.where(tags.contains).length;
      score += matched * 3;
      if (wanted.isNotEmpty && matched == 0 && tags.isNotEmpty) score -= 2;
      if (status.isNotEmpty && work.status.isNotEmpty) {
        final value = ComicIndexText.normalize(work.status);
        if (!value.contains(status) && !status.contains(value)) score -= 3;
      }
      scored.add((work: work, score: score, index: i));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    return [for (final e in scored.take(limit)) e.work];
  }

  // 第三步：读简介挑选

  static String rerankSystemPrompt(AiSearchKind kind) {
    final name = kindName(kind);
    return '你是「再漫画X」的$name推荐助手。根据用户需求，从候选作品中挑出真正符合的，'
        '按符合程度由高到低排序，最多 $maxResults 部；明显不符合的不要列出，宁缺毋滥。\n'
        '符合程度相近时，优先口碑好、人气高的作品；用户要找类似某作品时，不要推荐那部作品本身。\n'
        '每部写一句推荐理由：简体中文、30 字以内，点出它符合需求的地方，不要剧透关键情节。\n'
        '只输出 JSON：{"results":[{"n":候选编号,"reason":"推荐理由"}]}';
  }

  static String rerankUserPrompt(
    String query,
    AiSearchPlan plan,
    List<AiWork> candidates,
  ) {
    final b = StringBuffer()..writeln('用户需求：${clip(query, queryLimit)}');
    if (plan.summary.isNotEmpty) b.writeln('需求重点：${plan.summary}');
    final conditions = plan.conditions;
    if (conditions.isNotEmpty) b.writeln('筛选条件：${conditions.join('；')}');
    b.writeln('候选作品（编号|书名|作者|题材|进度|简介）：');
    for (var i = 0; i < candidates.length; i++) {
      final work = candidates[i];
      b.writeln([
        '${i + 1}',
        _field(work.title, 40),
        _field(work.authors, 30),
        _field(work.tags.join('/'), 40),
        _field(work.status, 10),
        _field(cleanDescription(work.description), descriptionLimit),
      ].join('|'));
    }
    return b.toString();
  }

  /// 解析挑选结果；编号超出范围或重复的忽略
  static List<AiSearchResultItem> parseRerank(
    Map<String, dynamic> json,
    List<AiWork> candidates,
  ) {
    final list = json['results'];
    if (list is! List) return const [];
    final seen = <int>{};
    final items = <AiSearchResultItem>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final n = int.tryParse(_text(entry['n'] ?? entry['id']));
      if (n == null || n < 1 || n > candidates.length || !seen.add(n)) continue;
      items.add(AiSearchResultItem(
        work: candidates[n - 1],
        reason: clip(_text(entry['reason']), reasonLimit),
      ));
      if (items.length >= maxResults) break;
    }
    return items;
  }

  /// 简介去掉 HTML 与多余空白
  static String cleanDescription(String text) => text
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'&nbsp;|&#160;'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // 每日次数

  /// 用掉一次今天的额度；[stored] 格式为「yyyy-MM-dd|次数」
  static ({bool allowed, String stored}) consumeQuota(
    String stored,
    DateTime now, {
    int limit = dailyLimit,
  }) {
    final today = dateKey(now);
    final parts = stored.split('|');
    var used = parts.length == 2 && parts[0] == today
        ? int.tryParse(parts[1]) ?? 0
        : 0;
    if (used >= limit) return (allowed: false, stored: '$today|$used');
    used++;
    return (allowed: true, stored: '$today|$used');
  }

  static String dateKey(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  /// 超过 [max] 字就截断并加上省略号
  static String clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  static String _field(String text, int max) => clip(
        text.replaceAll('|', '/').replaceAll(RegExp(r'\s+'), ' ').trim(),
        max,
      );

  static String _text(dynamic value) {
    if (value is String) return value.trim();
    if (value is num) return '$value';
    return '';
  }

  static List<String> _strings(dynamic value, int limit) {
    final Iterable<String> raw;
    if (value is List) {
      raw = value.map(_text);
    } else if (value is String) {
      raw = value.split(RegExp(r'[,，、;；]'));
    } else {
      raw = const <String>[];
    }
    return raw
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => e.length > 30 ? e.substring(0, 30) : e)
        .take(limit)
        .toList();
  }

  static List<String> _distinct(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final key = ComicIndexText.normalize(value);
      if (key.isNotEmpty && seen.add(key)) result.add(value);
    }
    return result;
  }
}
