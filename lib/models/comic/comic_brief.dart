/// 搜索结果补图用的简要资料（取自漫画详情接口）
class ComicBrief {
  const ComicBrief({
    required this.cover,
    required this.types,
    required this.lastChapterName,
  });

  /// [json] 为详情接口 data 栏位：{data: {...}, readingRecord: {...}}
  factory ComicBrief.fromDetailJson(dynamic json) {
    final data = json is Map ? json['data'] : null;
    if (data is! Map) {
      return const ComicBrief(cover: '', types: '', lastChapterName: '');
    }
    final types = data['types'];
    return ComicBrief(
      cover: '${data['cover'] ?? ''}',
      types: types is List
          ? types
              .whereType<Map>()
              .map((e) => '${e['tag_name'] ?? ''}')
              .where((e) => e.isNotEmpty)
              .join('/')
          : '',
      lastChapterName: '${data['last_update_chapter_name'] ?? ''}',
    );
  }

  final String cover;
  final String types;
  final String lastChapterName;
}
