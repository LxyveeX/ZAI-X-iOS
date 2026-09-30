import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/app_constant.dart';
import 'package:zai_x/app/controller/base_controller.dart';
import 'package:zai_x/app/dialog_utils.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/models/comic/comic_topic_model.dart';
import 'package:zai_x/requests/comic_request.dart';
import 'package:zai_x/routes/app_navigator.dart';
import 'package:zai_x/services/user_service.dart';

class SpecialDetailController extends BaseController {
  SpecialDetailController(this.id, {this.fromList = false});

  final int id;

  /// 从专题合集点进来的：「全部专题」直接返回，不再叠一层合集
  final bool fromList;

  final ComicRequest request = ComicRequest();

  Rx<ComicTopicDetail?> detail = Rx<ComicTopicDetail?>(null);

  @override
  void onInit() {
    loadData();
    super.onInit();
  }

  Future<void> loadData() async {
    try {
      pageLoadding.value = true;
      pageError.value = false;
      var result = await request.topicDetail(id: id);
      // 服务端回报已订阅的，同步给爱心按钮与「订阅全部」
      UserService.instance.subscribedComicIds.addAll([
        for (final comic in result.comics)
          if (comic.subscribed) comic.comicId,
      ]);
      detail.value = result;
    } catch (e) {
      handleError(e, showPageError: true);
    } finally {
      pageLoadding.value = false;
    }
  }

  void openList() {
    if (fromList) {
      AppNavigator.closePage();
    } else {
      AppNavigator.toSpecialList();
    }
  }

  Future<void> subscribeAll() async {
    if (detail.value == null) return;
    final user = UserService.instance;
    if (!user.logined.value) {
      if (!await user.login()) return;
      // 登录后重新载入，拿到这个帐号已订阅的清单，避免重复订阅
      await loadData();
    }
    final ids = detail.value?.unsubscribedIds(user.subscribedComicIds) ?? [];
    if (ids.isEmpty) {
      SmartDialog.showToast("这个专题的漫画都已经订阅了".i18n);
      return;
    }
    final confirmed = await DialogUtils.showAlertDialog(
      "要订阅这个专题里还没订阅的 ${ids.length} 部漫画吗？".i18n,
      title: "订阅全部".i18n,
    );
    if (!confirmed) return;
    await user.addSubscribe(ids, AppConstant.kTypeComic);
  }
}
