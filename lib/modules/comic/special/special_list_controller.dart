import 'package:zai_x/app/controller/base_controller.dart';
import 'package:zai_x/models/comic/comic_topic_model.dart';
import 'package:zai_x/requests/comic_request.dart';
import 'package:zai_x/routes/app_navigator.dart';

/// 专题合集（首页「火热专题」里的「漫画专题大合集」）
class SpecialListController extends BasePageController<ComicTopic> {
  final ComicRequest request = ComicRequest();
  final Set<int> _seen = {};

  @override
  Future<List<ComicTopic>> getData(int page, int pageSize) async {
    if (page == 1) _seen.clear();
    final list = await request.topics(page: page, size: pageSize);
    // 翻页期间有新专题上架时，旧的会往后挤一格，别重复列出
    return list.where((e) => _seen.add(e.id)).toList();
  }

  void open(ComicTopic item) {
    if (item.redirectUrl.isNotEmpty) {
      AppNavigator.toWebView(item.redirectUrl);
      return;
    }
    AppNavigator.toSpecialDetail(item.id, fromList: true);
  }
}
