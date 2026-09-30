/// 漫画专题（官方 App 的「火热专题」）
///
/// 列表：/api/v1/zt/h5/list 的 subjectList；详情：/api/v1/zt/h5/detail。
/// 旧的 /app/v1/subject 接口已经 404，专题一律改走这两个接口。
class ComicTopic {
  const ComicTopic({
    required this.id,
    required this.title,
    this.shortTitle = '',
    this.cover = '',
    this.createTime = '',
    this.redirectUrl = '',
  });

  factory ComicTopic.fromJson(Map json) => ComicTopic(
        id: _int(json['id']),
        title: _text(json['title']),
        shortTitle: _text(json['short_title']),
        cover: _text(json['cover']),
        createTime: _text(json['create_time']),
        redirectUrl: _text(json['redirectUrl']),
      );

  final int id;
  final String title;
  final String shortTitle;

  /// 横幅封面，约 2.5:1
  final String cover;

  /// 建立日期，例如 2026-09-28
  final String createTime;

  /// 有值时点开直接前往这个网址（目前官方资料都是空的）
  final String redirectUrl;

  /// 解析一页专题；最后一页之后 subjectList 会是 null
  static List<ComicTopic> listFromJson(dynamic data) {
    final list = data is Map ? data['subjectList'] : null;
    if (list is! List) return const [];
    return [
      for (final item in list.whereType<Map>()) ComicTopic.fromJson(item),
    ].where((e) => e.id > 0).toList();
  }
}

/// 专题详情：介绍与收录的漫画
class ComicTopicDetail {
  const ComicTopicDetail({
    required this.id,
    required this.title,
    this.cover = '',
    this.bannerCover = '',
    this.summary = '',
    this.comics = const [],
  });

  factory ComicTopicDetail.fromJson(dynamic data) {
    final map = data is Map ? data : const {};
    final subject = map['subject'] is Map ? map['subject'] as Map : const {};
    final seen = <int>{};
    final comics = <ComicTopicComic>[];
    final list = map['comicList'];
    if (list is List) {
      for (final item in list.whereType<Map>()) {
        final comic = ComicTopicComic.fromJson(item);
        // 没有漫画 ID 或书名的跳过（已失效，官方详情也是空的）；同一部漫画只列一次
        if (comic.comicId <= 0 || comic.name.isEmpty) continue;
        if (seen.add(comic.comicId)) comics.add(comic);
      }
    }
    return ComicTopicDetail(
      id: _int(subject['id']),
      title: _text(subject['title']),
      cover: _text(subject['cover']),
      bannerCover: _text(subject['bannerCover']),
      summary: _text(subject['summary']),
      comics: comics,
    );
  }

  final int id;
  final String title;

  /// 横幅封面，约 2.5:1
  final String cover;

  /// 详情页大图，约 1.25:1；较早的专题没有
  final String bannerCover;
  final String summary;
  final List<ComicTopicComic> comics;

  /// 页首用横幅封面，比较不占画面；没有才用大图
  String get headerImage => cover.isNotEmpty ? cover : bannerCover;

  /// 还没订阅的漫画（「订阅全部」只送这些）
  List<int> unsubscribedIds(Set<int> subscribed) => [
        for (final comic in comics)
          if (!subscribed.contains(comic.comicId)) comic.comicId,
      ];
}

/// 专题里的一部漫画
class ComicTopicComic {
  const ComicTopicComic({
    required this.comicId,
    required this.name,
    this.cover = '',
    this.brief = '',
    this.reason = '',
    this.subscribed = false,
  });

  /// 注意 id 是专题条目的编号，漫画 ID 是 comic_id
  factory ComicTopicComic.fromJson(Map json) => ComicTopicComic(
        comicId: _int(json['comic_id']),
        name: _text(json['name']),
        cover: _text(json['cover']),
        brief: _text(json['recommend_brief']),
        reason: _text(json['recommend_reason']),
        subscribed: _int(json['isSub']) == 1,
      );

  final int comicId;
  final String name;
  final String cover;

  /// 短评或题材，例如「近期完结推荐」「惊悚,悬疑」
  final String brief;

  /// 推荐语
  final String reason;

  /// 服务端回报已订阅（需登录才准确）
  final bool subscribed;
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value == null ? '' : '$value') ?? 0;
}

String _text(dynamic value) => value == null ? '' : '$value'.trim();
