import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/models/comic/comic_topic_model.dart';
import 'package:zai_x/modules/comic/special/special_list_page.dart';
import 'package:zai_x/modules/comic/special_detail/special_detail_page.dart';

void main() {
  group('topic list', () {
    test('parses a page of topics', () {
      final data = jsonDecode('''
        {
          "currentPage": 1,
          "size": 24,
          "subjectList": [
            {
              "id": 605,
              "title": "国庆补漫画啦！完结漫画专场",
              "short_title": "国庆补漫画啦",
              "cover": "https://images.zaimanhua.com/special_subject/14/a.jpg",
              "create_time": "2026-09-28",
              "page_url": "519d0e6a-bf4c-4121-9d2e-5b25e9841a72",
              "redirectUrl": ""
            },
            {"id": "604", "title": "教师节漫画专题2026", "redirectUrl": "https://example.com/t"},
            {"id": 0, "title": "没有编号"},
            "x"
          ],
          "total": 57
        }
      ''');
      final topics = ComicTopic.listFromJson(data);
      expect(topics.map((e) => e.id), [605, 604]);
      expect(topics.first.title, '国庆补漫画啦！完结漫画专场');
      expect(topics.first.shortTitle, '国庆补漫画啦');
      expect(topics.first.createTime, '2026-09-28');
      expect(topics.first.redirectUrl, isEmpty);
      expect(topics.last.cover, isEmpty);
      expect(topics.last.redirectUrl, 'https://example.com/t');
    });

    test('past the last page the list is null', () {
      final data = jsonDecode(
        '{"currentPage":4,"size":24,"subjectList":null,"total":57}',
      );
      expect(ComicTopic.listFromJson(data), isEmpty);
      expect(ComicTopic.listFromJson(null), isEmpty);
    });
  });

  group('topic detail', () {
    test('uses comic_id, not the entry id, and drops repeats', () {
      final detail = ComicTopicDetail.fromJson(jsonDecode('''
        {
          "comicList": [
            {
              "id": 17719,
              "comic_id": 77926,
              "recommend_lvl": 5,
              "recommend_brief": "近期完结推荐",
              "recommend_reason": "旁人都心知肚明 只有当事人蒙在鼓里的 双箭头！",
              "name": "缺憾之恋的主角们",
              "cover": "https://images.zaimanhua.com/webpic/3/a.jpg",
              "isSub": 1
            },
            {"id": 17720, "comic_id": 88064, "name": "擅长（？）捉弄人的西片同学", "isSub": 0},
            {"id": 17721, "comic_id": 77926, "name": "重复"},
            {"id": 17722, "name": "没有漫画编号"},
            {"id": 17723, "comic_id": 82531, "name": "", "recommend_brief": "爱情/四格"}
          ],
          "subject": {
            "id": 605,
            "title": "国庆补漫画啦！完结漫画专场",
            "cover": "https://images.zaimanhua.com/special_subject/14/a.jpg",
            "summary": "国庆就来补完结漫画和大长篇！",
            "static_html": "",
            "bannerCover": "https://images.zaimanhua.com/special_subject/19/b.jpg"
          }
        }
      '''));
      expect(detail.id, 605);
      expect(detail.title, '国庆补漫画啦！完结漫画专场');
      expect(detail.summary, '国庆就来补完结漫画和大长篇！');
      expect(detail.comics.map((e) => e.comicId), [77926, 88064]);
      expect(detail.comics.first.brief, '近期完结推荐');
      expect(detail.comics.first.reason, startsWith('旁人都心知肚明'));
      expect(detail.comics.first.subscribed, isTrue);
      expect(detail.comics.last.subscribed, isFalse);
      // 页首用横幅封面，比较不占画面
      expect(detail.headerImage, endsWith('/14/a.jpg'));
    });

    test('older topics without a banner still get a header', () {
      final detail = ComicTopicDetail.fromJson({
        'comicList': [],
        'subject': {'id': 520, 'title': '旧专题', 'bannerCover': 'b.jpg'},
      });
      expect(detail.headerImage, 'b.jpg');
      expect(ComicTopicDetail.fromJson({}).comics, isEmpty);
      expect(ComicTopicDetail.fromJson(null).title, isEmpty);
    });

    test('subscribe all only sends the ones not yet subscribed', () {
      final detail = ComicTopicDetail.fromJson({
        'comicList': [
          {'comic_id': 1, 'name': '甲'},
          {'comic_id': 2, 'name': '乙'},
          {'comic_id': 3, 'name': '丙'},
        ],
      });
      expect(detail.unsubscribedIds({2}), [1, 3]);
      expect(detail.unsubscribedIds({1, 2, 3}), isEmpty);
    });
  });

  test('columns grow with the available width', () {
    // 手机、折叠机展开、平板右侧内容区、桌面
    expect(SpecialListPage.columns(360), 1);
    expect(SpecialListPage.columns(600), 1);
    expect(SpecialListPage.columns(830), 2);
    expect(SpecialListPage.columns(1200), 3);
    expect(SpecialListPage.columns(4000), 4);
    expect(SpecialDetailPage.columns(411), 1);
    expect(SpecialDetailPage.columns(830), 2);
    expect(SpecialDetailPage.columns(1300), 3);
    expect(SpecialDetailPage.columns(4000), 3);
  });
}
