/// AI 搜索的对象
enum AiSearchKind { comic, novel }

/// 分类标签：名称与接口用的 tagId
class AiTag {
  const AiTag(this.id, this.name);

  final int id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AiTag && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => name;
}

/// AI 可以挑选的筛选条件
class AiTagVocabulary {
  const AiTagVocabulary({
    this.themes = const [],
    this.audiences = const [],
    this.zones = const [],
    this.statuses = const [],
  });

  /// 题材
  final List<AiTag> themes;

  /// 受众（漫画）
  final List<AiTag> audiences;

  /// 地区（漫画）
  final List<AiTag> zones;

  /// 进度（漫画）
  final List<AiTag> statuses;
}

/// AI 从描述整理出的搜索条件
class AiSearchPlan {
  const AiSearchPlan({
    this.summary = '',
    this.themes = const [],
    this.excludeThemes = const [],
    this.audience,
    this.zone,
    this.status,
    this.titles = const [],
    this.keywords = const [],
    this.preferNew = false,
  });

  /// 一句话复述需求
  final String summary;
  final List<AiTag> themes;
  final List<AiTag> excludeThemes;
  final AiTag? audience;
  final AiTag? zone;
  final AiTag? status;

  /// AI 认为符合描述的具体作品
  final List<String> titles;

  /// 书名或作者名里可能出现的词
  final List<String> keywords;

  /// 想看新作或最近更新
  final bool preferNew;

  bool get hasFilters =>
      themes.isNotEmpty || audience != null || zone != null || status != null;

  bool get isEmpty => !hasFilters && titles.isEmpty && keywords.isEmpty;

  AiSearchPlan copyWith({List<String>? keywords}) => AiSearchPlan(
        summary: summary,
        themes: themes,
        excludeThemes: excludeThemes,
        audience: audience,
        zone: zone,
        status: status,
        titles: titles,
        keywords: keywords ?? this.keywords,
        preferNew: preferNew,
      );

  /// 画面上显示的条件，例如「校园、爱情」「完结」「不要：惊悚」
  List<String> get conditions => [
        if (themes.isNotEmpty) themes.map((e) => e.name).join('、'),
        if (audience != null) audience!.name,
        if (zone != null) zone!.name,
        if (status != null) status!.name,
        if (excludeThemes.isNotEmpty)
          '不要：${excludeThemes.map((e) => e.name).join('、')}',
      ];
}

/// 一部候选作品
class AiWork {
  AiWork({
    required this.id,
    required this.title,
    this.authors = '',
    List<String> tags = const [],
    this.status = '',
    this.cover = '',
    this.description = '',
    this.lastChapter = '',
  }) : tags = List.unmodifiable(tags);

  final int id;
  final String title;
  final String authors;
  final List<String> tags;
  final String status;
  final String cover;
  final String description;

  /// 最新章节名称
  final String lastChapter;

  /// 合并资料：[other] 有值的栏位优先（通常是详情接口的资料）
  AiWork mergedWith(AiWork other) => AiWork(
        id: id,
        title: other.title.isNotEmpty ? other.title : title,
        authors: other.authors.isNotEmpty ? other.authors : authors,
        tags: other.tags.isNotEmpty ? other.tags : tags,
        status: other.status.isNotEmpty ? other.status : status,
        cover: other.cover.isNotEmpty ? other.cover : cover,
        description:
            other.description.isNotEmpty ? other.description : description,
        lastChapter:
            other.lastChapter.isNotEmpty ? other.lastChapter : lastChapter,
      );

  /// 把「冒险/奇幻」这种字串拆成标签
  static List<String> splitTags(String? text) => (text ?? '')
      .split(RegExp(r'[/,，、|]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 漫画详情接口回传的资料（{data: {...}, readingRecord: {...}}）
  factory AiWork.fromComicDetail(int id, dynamic json) {
    final data = json is Map ? json['data'] : null;
    if (data is! Map) return AiWork(id: id, title: '');
    List<String> names(dynamic list) => list is List
        ? list
            .whereType<Map>()
            .map((e) => '${e['tag_name'] ?? ''}'.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];
    final status = names(data['status']);
    return AiWork(
      id: id,
      title: '${data['title'] ?? ''}',
      authors: names(data['authors']).join('/'),
      tags: names(data['types']),
      status: status.isEmpty ? '' : status.first,
      cover: '${data['cover'] ?? ''}',
      description: '${data['description'] ?? ''}',
      lastChapter: '${data['last_update_chapter_name'] ?? ''}',
    );
  }
}

/// 一笔 AI 搜索结果
class AiSearchResultItem {
  const AiSearchResultItem({required this.work, required this.reason});

  final AiWork work;

  /// 推荐理由；AI 挑选失败时为空
  final String reason;
}

/// 一次 AI 搜索的结果
class AiSearchOutcome {
  const AiSearchOutcome({
    required this.plan,
    required this.items,
    this.reranked = true,
    this.candidateCount = 0,
  });

  final AiSearchPlan plan;
  final List<AiSearchResultItem> items;

  /// false：AI 挑选失败，改列依条件排序的候选
  final bool reranked;

  /// 送去挑选的候选数量
  final int candidateCount;
}
