import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/models/comic/chapter_detail_model.dart';
import 'package:zai_x/models/comic/comic_brief.dart';
import 'package:zai_x/models/comic/detail_info.dart';
import 'package:zai_x/models/comic/detail_model.dart';
import 'package:zai_x/requests/comic_request.dart';
import 'package:zai_x/requests/common/api.dart';

/// 依 2026-09-29 实测 /comic/detail/48894?_v=2.3.8（未登录）的回应精简
Map<String, dynamic> _hiddenDetail() => {
      'data': {
        'id': 48894,
        'title': '污秽不堪的你最可爱了',
        'direction': 1,
        'islong': 2,
        'cover': 'https://images.zaimanhua.com/webpic/2/wbbkdnsasx2021715.jpg',
        'description': '',
        'last_updatetime': 1788528548,
        'last_update_chapter_name': '第05卷',
        'first_letter': 'w',
        'comic_py': 'wusuibukandenizuikeaile',
        'last_update_chapter_id': 186043,
        'hidden': 1,
        'canRead': false,
        'types': [
          {'tag_id': 3243, 'tag_name': 'ゆり', 'tag_py': 'baihe'}
        ],
        'status': [
          {'tag_id': 2310, 'tag_name': '已完结', 'tag_py': 'yiwanjie'}
        ],
        'authors': [
          {'tag_id': 8431, 'tag_name': 'まにお', 'tag_py': 'manio'}
        ],
        'chapters': [
          {
            'title': '连载',
            'data': [
              {
                'chapter_id': 86107,
                'chapter_title': '1话',
                'updatetime': 1541000000,
                'chapter_order': 10,
                'canRead': false,
              },
              {
                'chapter_id': 86108,
                'chapter_title': '2话',
                'updatetime': 1542000000,
                'chapter_order': 20,
                'canRead': false,
              },
            ],
          },
          {
            'title': '单行本',
            'data': [
              {
                'chapter_id': 186043,
                'chapter_title': '第05卷',
                'updatetime': 1788528548,
                'chapter_order': 50,
                'canRead': false,
              },
            ],
          },
        ],
      },
      'readingRecord': {'uid': 0, 'chapter_id': 0},
    };

void main() {
  test('神隐作品的详情可以解析，并带出神隐与阅读权限', () {
    final info =
        ComicDetailInfo.fromV4(ComicDetailModel.fromJson(_hiddenDetail()));
    expect(info.id, 48894);
    expect(info.isHide, isTrue);
    expect(info.canRead, isFalse);
    expect(info.volumes.map((v) => v.title).toList(), ['连载', '单行本']);
    expect(info.volumes.first.chapters.length, 2);
    expect(info.authors.single.tagId, 8431);
  });

  test('一般作品没有 hidden/canRead 栏位时维持原本行为', () {
    final json = _hiddenDetail();
    (json['data'] as Map).remove('hidden');
    (json['data'] as Map).remove('canRead');
    final info = ComicDetailInfo.fromV4(ComicDetailModel.fromJson(json));
    expect(info.isHide, isFalse);
    expect(info.canRead, isTrue);
  });

  test('没有图片的章节视为无阅读权限', () {
    final locked = ComicChapterDetailModel.fromJson({
      'chapter_id': 86107,
      'comic_id': 48894,
      'title': '第01话',
      'chapter_order': 10,
      'direction': 1,
      'page_url': [],
      'picnum': 0,
      'page_url_hd': [],
      'comment_count': 0,
      'canRead': false,
    });
    expect(locked.isLocked, isTrue);
    expect(locked.canRead, isFalse);

    final readable = ComicChapterDetailModel.fromJson({
      'chapter_id': 1,
      'comic_id': 2,
      'title': '第1话',
      'chapter_order': 1,
      'direction': 1,
      'page_url': ['https://images.zaimanhua.com/a.jpg'],
      'picnum': 1,
      'page_url_hd': [],
    });
    expect(readable.isLocked, isFalse);
    expect(readable.canRead, isNull);
  });

  test('无权限说明依登录状态不同', () {
    final guest = ComicRequest.chapterLockedMessage(false);
    final member = ComicRequest.chapterLockedMessage(true);
    expect(guest, contains('登录'));
    expect(member, contains('等级'));
    expect(guest, isNot(member));
  });

  test('官方 App 版本参数不低于隐藏作品的门槛 2.2.9', () {
    final parts = Api.APP_VERSION.split('.').map(int.parse).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    final value = parts[0] * 10000 + parts[1] * 100 + parts[2];
    expect(value, greaterThanOrEqualTo(20209));
  });

  test('搜索结果补图资料', () {
    final brief = ComicBrief.fromDetailJson(_hiddenDetail());
    expect(brief.cover, endsWith('wbbkdnsasx2021715.jpg'));
    expect(brief.types, 'ゆり');
    expect(brief.lastChapterName, '第05卷');
    expect(ComicBrief.fromDetailJson(null).cover, isEmpty);
  });
}
