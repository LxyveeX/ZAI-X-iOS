import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/app/i18n.dart';
import 'package:zai_x/models/comic/comic_topic_model.dart';
import 'package:zai_x/modules/comic/special/special_list_controller.dart';
import 'package:zai_x/widgets/net_image.dart';
import 'package:zai_x/widgets/page_grid_view.dart';
import 'package:zai_x/widgets/shadow_card.dart';

/// 专题合集：横幅卡片，手机一栏，折叠机与平板依宽度增加栏数
class SpecialListPage extends StatelessWidget {
  /// [controller] 只给测试替换资料来源用
  SpecialListPage({SpecialListController? controller, super.key})
      : controller = controller ??
            Get.put(
              SpecialListController(),
              tag: 'special-list-${_instances++}',
            );

  static int _instances = 0;

  final SpecialListController controller;

  /// 每栏至少约 360 宽
  static int columns(double width) {
    final count = (width - 12) ~/ 372;
    if (count < 1) return 1;
    return count > 4 ? 4 : count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("专题合集".i18n)),
      body: LayoutBuilder(
        builder: (context, constraints) => PageGridView(
          pageController: controller,
          firstRefresh: true,
          showPageLoadding: true,
          crossAxisCount: columns(constraints.maxWidth),
          padding: AppStyle.edgeInsetsA12,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          itemBuilder: (context, i) => _buildItem(context, controller.list[i]),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, ComicTopic item) {
    return ShadowCard(
      onTap: () => controller.open(item),
      radius: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2.5,
            child: NetImage(
              item.cover,
              width: 840,
              height: 336,
              thumbnail: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.title.i18n,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.createTime.isNotEmpty) ...[
                  AppStyle.hGap8,
                  Text(
                    item.createTime,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
