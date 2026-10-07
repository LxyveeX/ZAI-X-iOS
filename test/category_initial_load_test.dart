import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/models/comic/category_comic_model.dart';
import 'package:zai_x/models/comic/category_filter_model.dart';
import 'package:zai_x/models/comic/comic_tag_table.g.dart';
import 'package:zai_x/modules/comic/category_detail/category_detail_controller.dart';
import 'package:zai_x/requests/comic_request.dart';

class _DelayedFilters extends ComicRequest {
  final filters = Completer<List<ComicCategoryFilterModel>>();
  final queries = <Map<String, int>>[];

  @override
  Future<List<ComicCategoryFilterModel>> categoryFilter() => filters.future;

  @override
  Future<List<ComicCategoryComicModel>> categoryComic({
    required int id,
    int sort = 1,
    int page = 1,
    int status = 0,
    int zone = 0,
    String firstLetter = '',
  }) async {
    queries.add({'theme': id, 'status': status, 'zone': zone, 'page': page});
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in [
    (id: 2310, dimension: ComicTagDimension.status, parameter: 'status'),
    (id: 2304, dimension: ComicTagDimension.zone, parameter: 'zone'),
    (id: 3243, dimension: ComicTagDimension.theme, parameter: 'theme'),
  ]) {
    test(
      'initial category refresh waits and uses ${entry.parameter}',
      () async {
        final api = _DelayedFilters();
        final controller = CategoryDetailController(entry.id, request: api);
        controller.onInit();
        final request = controller.getData(1, 20);
        await Future<void>.delayed(Duration.zero);
        expect(api.queries, isEmpty);
        api.filters.complete([
          ComicCategoryFilterModel(
            title: '类别',
            dimension: entry.dimension,
            items: [
              ComicCategoryFilterItemModel(tagId: 0, tagName: '全部'),
              ComicCategoryFilterItemModel(tagId: entry.id, tagName: '所选分类'),
            ],
          ),
        ]);
        await request;
        expect(api.queries, hasLength(1));
        expect(api.queries.single[entry.parameter], entry.id);
        for (final key in ['theme', 'status', 'zone']) {
          if (key != entry.parameter) expect(api.queries.single[key], 0);
        }
        controller.scrollController.dispose();
        controller.easyRefreshController.dispose();
      },
    );
  }
}
