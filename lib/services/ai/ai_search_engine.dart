import 'package:zai_x/services/ai/ai_search_models.dart';
import 'package:zai_x/services/comic_index/comic_index.dart';

/// 候选作品的来源
enum AiHitSource {
  /// AI 点名的具体作品
  title,

  /// 用关键词搜书名找到的作品
  keyword,

  /// 依题材、受众等条件列出的作品
  filter,
}

/// 从某个来源找到的一部作品
class AiCandidateHit {
  const AiCandidateHit(this.work, this.source, this.rank);

  final AiWork work;
  final AiHitSource source;

  /// 在来源清单里的名次，从 0 起算；
  /// [AiHitSource.title] 时 0 表示书名相同、1 表示书名相近
  final int rank;
}

/// AI 搜索的纯逻辑：提示词、解析 AI 回覆、候选排序与每日次数
abstract final class AiSearchEngine {
  static const int maxThemes = 3;
  static const int maxTitles = 10;
  static const int maxKeywords = 5;

  /// 每一轮送去挑选的候选数
  static const int roundSize = 45;

  /// 每个 AI 请求处理的候选数；同一轮分成几批同时送出，缩短等待
  static const int batchSize = 15;

  /// 每批最多挑出几部
  static const int maxPicksPerBatch = 10;

  static const int descriptionLimit = 150;
  static const int reasonLimit = 40;
  static const int queryLimit = 200;

  /// 每台装置每天可用的 AI 搜索次数（「找更多作品」也算一次）
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
      ..writeln('  "keywords": ["拿去搜书名的词，最多 $maxKeywords 个"],')
      ..writeln('  "sort": "hot 或 new"')
      ..writeln('}')
      ..writeln('填写说明：')
      ..writeln('- 受众是目标读者（少年、少女、青年等），不是主角的性别；'
          '受众、地区、进度只在用户明确提到时才填。')
      ..writeln('- keywords：用户提到的书名、作者、角色一定要放；'
          '描述题材或人物设定时，放这类作品书名里常见、又能缩小范围的词'
          '（例如找异世界作品放「转生」「异世界」，找女主很强的作品放「魔女」「圣女」「女骑士」）；'
          '不要放「女主」「主角」「漫画」这种几乎什么书名都搜得到的词。')
      ..writeln('- sort：用户想看新作或最近更新时用 new，否则用 hot。')
      ..writeln('- 如果用户只输入书名或作者，就放进 keywords，其他栏位留空。');
    return b.toString();
  }

  /// 同时另外问一次：符合描述的代表作（两个请求并行，比一次全部回答快）
  static String titlesSystemPrompt(AiSearchKind kind) {
    final name = kindName(kind);
    return '你是「再漫画X」App 的$name选书助手。根据用户的描述，'
        '列出你熟悉、口碑好又符合描述的具体作品，用中文站常见的简体书名。\n'
        '描述是类型、氛围或人物设定时，尽量列满 8～$maxTitles 部；'
        '找「类似某作品」时列相似的作品，不要列原作；'
        '用户只输入书名或作者时，列出那部作品或那位作者的代表作。\n'
        '只输出 JSON：{"titles":["书名"]}';
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

  /// 比对 AI 点名的书名：2 相同（含别名）、1 相近、0 不是同一部
  ///
  /// 「相近」只容许多或少几个字（书名的三分之一，至少 2 个字），
  /// 画集、外传、公式书这类书名长很多的作品不算，避免把周边当成本传。
  static int titleMatch(
    String wanted,
    String title, {
    Iterable<String> aliases = const [],
  }) {
    final key = ComicIndexText.normalize(wanted);
    if (key.isEmpty) return 0;
    var best = 0;
    for (final name in [title, ...aliases]) {
      final value = ComicIndexText.normalize(name);
      if (value.isEmpty) continue;
      if (value == key) return 2;
      final extra = (value.length - key.length).abs();
      final allowed = key.length ~/ 3 > 2 ? key.length ~/ 3 : 2;
      if (extra <= allowed &&
          value.length >= 2 &&
          key.length >= 2 &&
          (value.startsWith(key) || key.startsWith(value))) {
        best = 1;
      }
    }
    return best;
  }

  // 第二步：合并候选

  /// 合并各来源找到的作品并依条件排序，略过 [exclude] 里已经挑选过的作品
  ///
  /// 带有「不要」题材的直接剔除；AI 点名的作品最前面，
  /// 其余依来源名次交错排列；同时被几个来源找到、或同时符合几个题材的会往前，
  /// 已知题材却一个都不符合的往后。
  static List<AiWork> rankCandidates(
    AiSearchPlan plan,
    List<AiCandidateHit> hits, {
    Set<int> exclude = const {},
    int? limit,
  }) {
    final order = <int>[];
    final works = <int, AiWork>{};
    final bonus = <int, double>{};
    for (final hit in hits) {
      final id = hit.work.id;
      if (id <= 0 || exclude.contains(id)) continue;
      final existing = works[id];
      if (existing == null) {
        order.add(id);
        works[id] = hit.work;
      } else {
        works[id] = existing.mergedWith(hit.work);
      }
      final rank = hit.rank < 0 ? 0 : hit.rank;
      final score = switch (hit.source) {
        AiHitSource.title => rank == 0 ? 8.0 : 6.0,
        AiHitSource.keyword => 3.0 - (rank < 30 ? rank : 30) * 0.08,
        AiHitSource.filter => 3.0 - (rank < 30 ? rank : 30) * 0.08,
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
      if (tags.isNotEmpty && wanted.isNotEmpty) {
        // 题材清单来的作品一定符合一个题材，所以只有多符合的才加分；
        // 还不知道题材的（例如本地索引）不加不减
        final matched = wanted.where(tags.contains).length;
        score += matched == 0 ? -1.5 : (matched - 1) * 1.5;
      }
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
    final picked = limit == null ? scored : scored.take(limit);
    return [for (final e in picked) e.work];
  }

  /// 交错分批，让每一批都有排名前面与后面的候选
  static List<List<T>> splitBatches<T>(List<T> items, int size) {
    if (items.isEmpty || size <= 0) return [];
    final count = (items.length + size - 1) ~/ size;
    return [
      for (var b = 0; b < count; b++)
        [for (var i = b; i < items.length; i += count) items[i]],
    ];
  }

  // 第三步：读简介挑选

  static String rerankSystemPrompt(AiSearchKind kind) {
    final name = kindName(kind);
    return '你是「再漫画X」的$name推荐助手。请根据用户需求，从候选作品中挑选并排序。\n'
        '1. fit 填 2 表示明确符合需求；填 1 表示大致符合，或信息不足、但很可能符合。'
        '判断时可以结合你对这部作品本身的了解，不必只看简介。\n'
        '2. 明显不符合主要需求的不要列出，例如题材不对、主角类型不对、用户说不想要的。\n'
        '3. 先列 fit 为 2 的，再列 1；同一级里越符合、口碑越好的排越前面。'
        '用户要找类似某作品时，不要列出那部作品本身。\n'
        '4. 书名前有 ★ 的，是先前依需求想到的代表作；符合就给 2，但仍要依作品实际内容判断。\n'
        '5. 最多 $maxPicksPerBatch 部。推荐理由用简体中文、20 字以内，点出符合的地方，不要剧透。\n'
        '只输出 JSON：{"results":[{"n":候选编号,"fit":2,"reason":"推荐理由"}]}';
  }

  /// [named] 是 AI 先前点名的作品，书名前会加上 ★
  static String rerankUserPrompt(
    String query,
    AiSearchPlan plan,
    List<AiWork> candidates, {
    Set<int> named = const {},
  }) {
    final b = StringBuffer()..writeln('用户需求：${clip(query, queryLimit)}');
    if (plan.summary.isNotEmpty) b.writeln('需求重点：${plan.summary}');
    final conditions = plan.conditions;
    if (conditions.isNotEmpty) b.writeln('筛选条件：${conditions.join('；')}');
    b.writeln('候选作品（编号|书名|作者|题材|进度|人气|简介）：');
    for (var i = 0; i < candidates.length; i++) {
      final work = candidates[i];
      b.writeln([
        '${i + 1}',
        '${named.contains(work.id) ? '★' : ''}${_field(work.title, 40)}',
        _field(work.authors, 30),
        _field(work.tags.join('/'), 40),
        _field(work.status, 10),
        formatHot(work.hot),
        _field(cleanDescription(work.description), descriptionLimit),
      ].join('|'));
    }
    return b.toString();
  }

  /// 解析挑选结果；编号超出范围或重复的忽略
  static List<AiSearchResultItem> parseRerank(
    Map<String, dynamic> json,
    List<AiWork> candidates, {
    int maxPicks = maxPicksPerBatch,
  }) {
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
        fit: int.tryParse(_text(entry['fit'])) == 1 ? 1 : 2,
      ));
      if (items.length >= maxPicks) break;
    }
    return items;
  }

  /// 合并同一轮各批的结果：先「符合」再「可能符合」；
  /// 同级里 [preferred]（AI 点名的代表作）在前，其余依各批名次交错
  static List<AiSearchResultItem> mergeBatches(
    List<List<AiSearchResultItem>> batches, {
    Set<int> preferred = const {},
  }) {
    final entries = <({AiSearchResultItem item, int pos, int batch})>[];
    for (var b = 0; b < batches.length; b++) {
      for (var i = 0; i < batches[b].length; i++) {
        entries.add((item: batches[b][i], pos: i, batch: b));
      }
    }
    entries.sort((a, b) {
      final byFit = b.item.fit.compareTo(a.item.fit);
      if (byFit != 0) return byFit;
      final aPreferred = preferred.contains(a.item.work.id) ? 0 : 1;
      final bPreferred = preferred.contains(b.item.work.id) ? 0 : 1;
      if (aPreferred != bPreferred) return aPreferred - bPreferred;
      final byPos = a.pos.compareTo(b.pos);
      return byPos != 0 ? byPos : a.batch.compareTo(b.batch);
    });
    final seen = <int>{};
    return [
      for (final e in entries)
        if (seen.add(e.item.work.id)) e.item,
    ];
  }

  /// 人气写成「6.4万」这种短格式；0 表示不知道，回空字串
  static String formatHot(int hot) {
    if (hot <= 0) return '';
    String short(double value, String unit) {
      final text = value.toStringAsFixed(1);
      return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}$unit';
    }

    if (hot >= 100000000) return short(hot / 100000000, '亿');
    if (hot >= 10000) return short(hot / 10000, '万');
    return '$hot';
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
