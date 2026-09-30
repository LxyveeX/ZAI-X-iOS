import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/models/comic/comic_topic_model.dart';
import 'package:zai_x/modules/comic/special/special_list_controller.dart';
import 'package:zai_x/modules/comic/special/special_list_page.dart';
import 'package:zai_x/modules/comic/special_detail/special_detail_controller.dart';
import 'package:zai_x/modules/comic/special_detail/special_detail_page.dart';
import 'package:zai_x/services/local_storage_service.dart';
import 'package:zai_x/services/user_service.dart';

/// 手机、折叠机展开、平板右侧内容区，以及繁体加大字
const _sizes = [Size(360, 800), Size(840, 900), Size(1180, 900), Size(320, 800)];

Widget _app(Size size, Widget page) => GetMaterialApp(
      theme: AppStyle.lightTheme,
      darkTheme: AppStyle.darkTheme,
      themeMode: size.width == 840 ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(size.width == 320 ? 1.8 : 1),
        ),
        child: child!,
      ),
      home: page,
    );

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(LocalStorageService());
    Get.put<UserService>(_User());
  });

  tearDown(() {
    AppI18n.useTraditional = false;
    Get.reset();
  });

  testWidgets('topic list fits phones, foldables and tablets', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in _sizes) {
      await tester.binding.setSurfaceSize(size);
      AppI18n.useTraditional = size.width == 320;
      final controller = _ListController();
      await tester.pumpWidget(_app(size, SpecialListPage(controller: controller)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.text('国庆补漫画啦！完结漫画专场'.i18n), findsOneWidget);
      expect(find.text('2026-09-28'), findsOneWidget);

      final first = tester.getTopLeft(find.text('国庆补漫画啦！完结漫画专场'.i18n));
      final second = tester.getTopLeft(find.text('教师节漫画专题2026'.i18n));
      // 手机一栏往下排；折叠机与平板并排
      expect(first.dy == second.dy, size.width >= 800, reason: '$size');

      await tester.tap(find.text('教师节漫画专题2026'.i18n));
      expect(controller.opened, [604]);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('topic detail fits phones, foldables and tablets', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in _sizes) {
      await tester.binding.setSurfaceSize(size);
      AppI18n.useTraditional = size.width == 320;
      final controller = _DetailController();
      await tester.pumpWidget(_app(
        size,
        SpecialDetailPage(605, fromList: true, controller: controller),
      ));
      await controller.loadData();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.text('国庆补漫画啦！完结漫画专场'.i18n), findsOneWidget);
      expect(find.text('收录 3 部漫画'.i18n), findsOneWidget);

      final first = tester.getTopLeft(find.text('缺憾之恋的主角们'.i18n));
      final second = tester.getTopLeft(find.text('擅长（？）捉弄人的西片同学'.i18n));
      expect(first.dy == second.dy, size.width >= 800, reason: '$size');

      // 已订阅的显示实心爱心
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2));

      await tester.tap(find.text('全部专题'.i18n));
      expect(controller.listOpened, 1);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size scrolled');
      await tester.pumpWidget(const SizedBox());
    }
  });
}

class _User extends UserService {}

class _ListController extends SpecialListController {
  final opened = <int>[];

  @override
  Future<List<ComicTopic>> getData(int page, int pageSize) async {
    if (page > 1) return [];
    return const [
      ComicTopic(
        id: 605,
        title: '国庆补漫画啦！完结漫画专场',
        createTime: '2026-09-28',
      ),
      ComicTopic(id: 604, title: '教师节漫画专题2026', createTime: '2026-09-09'),
      ComicTopic(
        id: 603,
        title: '新番漫画专题2026年10月号，这是一个很长很长的专题名称用来测试截断',
        createTime: '2026-09-04',
      ),
    ];
  }

  @override
  void open(ComicTopic item) => opened.add(item.id);
}

class _DetailController extends SpecialDetailController {
  _DetailController() : super(605, fromList: true);

  int listOpened = 0;

  @override
  Future<void> loadData() async {
    final result = ComicTopicDetail.fromJson({
      'comicList': [
        {
          'comic_id': 77926,
          'name': '缺憾之恋的主角们',
          'recommend_brief': '近期完结推荐',
          'recommend_reason': '旁人都心知肚明 只有当事人蒙在鼓里的 双箭头！'
              '但是！单相思？ 跟着同学们一起磕CP，再加一些字让它换行换到第三行以上',
          'isSub': 1,
        },
        {
          'comic_id': 88064,
          'name': '擅长（？）捉弄人的西片同学',
          'recommend_brief': '近期完结推荐',
          'recommend_reason': '高木和西片的闺女，中学生小千，另一段捉弄人的故事正式开幕！',
        },
        {'comic_id': 1433, 'name': '蝙蝠比利', 'recommend_brief': '大长篇杀时间'},
      ],
      'subject': {
        'id': 605,
        'title': '国庆补漫画啦！完结漫画专场',
        'summary': '国庆就来补完结漫画和大长篇！',
      },
    });
    UserService.instance.subscribedComicIds.addAll([
      for (final comic in result.comics)
        if (comic.subscribed) comic.comicId,
    ]);
    detail.value = result;
  }

  @override
  void openList() => listOpened++;
}
