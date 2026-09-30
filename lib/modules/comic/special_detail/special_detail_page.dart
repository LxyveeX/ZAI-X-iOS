import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:zai_x/app/app_constant.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/models/comic/comic_topic_model.dart';
import 'package:zai_x/modules/comic/special_detail/special_detail_controller.dart';
import 'package:zai_x/routes/app_navigator.dart';
import 'package:zai_x/services/user_service.dart';
import 'package:zai_x/widgets/net_image.dart';
import 'package:zai_x/widgets/status/app_error_widget.dart';
import 'package:zai_x/widgets/status/app_loadding_widget.dart';

/// 专题详情：横幅、介绍与收录的漫画；折叠机与平板上漫画改成两栏以上
class SpecialDetailPage extends StatelessWidget {
  /// [controller] 只给测试替换资料来源用
  SpecialDetailPage(
    this.id, {
    this.fromList = false,
    SpecialDetailController? controller,
    super.key,
  }) : controller = controller ??
            Get.put(
              SpecialDetailController(id, fromList: fromList),
              tag: 'special-$id-${_instances++}',
            );

  static int _instances = 0;

  final int id;
  final bool fromList;
  final SpecialDetailController controller;

  /// 每栏至少约 380 宽（左右留白 12、栏距 16）
  static int columns(double width) {
    final count = (width - 8) ~/ 396;
    if (count < 1) return 1;
    return count > 3 ? 3 : count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(
          () => Text(
            (controller.detail.value?.title ?? "专题").i18n,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      body: Obx(() {
        final detail = controller.detail.value;
        return Stack(
          children: [
            if (detail != null)
              LayoutBuilder(
                builder: (context, constraints) => CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(context, detail)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      sliver: SliverMasonryGrid.count(
                        crossAxisCount: columns(constraints.maxWidth),
                        crossAxisSpacing: 16,
                        childCount: detail.comics.length,
                        itemBuilder: (context, i) =>
                            _buildItem(context, detail.comics[i]),
                      ),
                    ),
                  ],
                ),
              ),
            Visibility(
              visible: controller.pageLoadding.value,
              child: const AppLoaddingWidget(),
            ),
            Offstage(
              offstage: !controller.pageError.value,
              child: AppErrorWidget(
                errorMsg: controller.errorMsg.value,
                onRefresh: controller.loadData,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildHeader(BuildContext context, ComicTopicDetail detail) {
    const grey = TextStyle(fontSize: 13, color: Colors.grey);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (detail.headerImage.isNotEmpty)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: AspectRatio(
                  aspectRatio: detail.cover.isNotEmpty ? 2.5 : 1.25,
                  child: NetImage(
                    detail.headerImage,
                    width: 840,
                    height: detail.cover.isNotEmpty ? 336 : 672,
                    borderRadius: 8,
                  ),
                ),
              ),
            ),
          if (detail.summary.isNotEmpty) ...[
            AppStyle.vGap12,
            Text(
              detail.summary.i18n,
              style: const TextStyle(height: 1.5),
            ),
          ],
          AppStyle.vGap8,
          Text("收录 ${detail.comics.length} 部漫画".i18n, style: grey),
          AppStyle.vGap4,
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: controller.openList,
                  icon: const Icon(Remix.list_unordered, size: 20),
                  label: Text("全部专题".i18n),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: controller.subscribeAll,
                  icon: const Icon(Remix.heart_line, size: 20),
                  label: Text("订阅全部".i18n),
                ),
              ),
            ],
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: .2)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, ComicTopicComic item) {
    const grey = TextStyle(color: Colors.grey, fontSize: 14);
    return InkWell(
      onTap: () => AppNavigator.toComicDetail(item.comicId),
      child: Container(
        padding: AppStyle.edgeInsetsV12,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: .2)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetImage(
              item.cover,
              width: 80,
              height: 107,
              borderRadius: 4,
              thumbnail: true,
            ),
            AppStyle.hGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name.i18n,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.brief.isNotEmpty) ...[
                    AppStyle.vGap4,
                    Text(
                      item.brief.i18n,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: grey,
                    ),
                  ],
                  if (item.reason.isNotEmpty) ...[
                    AppStyle.vGap4,
                    Text(
                      item.reason.i18n,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: grey,
                    ),
                  ],
                ],
              ),
            ),
            Obx(() {
              final subscribed =
                  UserService.instance.subscribedComicIds.contains(item.comicId);
              return IconButton(
                tooltip: (subscribed ? "取消订阅" : "订阅").i18n,
                icon: Icon(subscribed ? Icons.favorite : Icons.favorite_border),
                onPressed: () => subscribed
                    ? UserService.instance.cancelSubscribe(
                        [item.comicId],
                        AppConstant.kTypeComic,
                      )
                    : UserService.instance.addSubscribe(
                        [item.comicId],
                        AppConstant.kTypeComic,
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
