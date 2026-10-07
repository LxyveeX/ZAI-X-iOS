import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// iPad requires a non-empty popover anchor inside the current Flutter view.
/// Read the view at invocation time so rotation and Split View are respected.
Future<ShareResult> shareSystemContent({
  required BuildContext context,
  String? text,
  List<XFile>? files,
}) {
  final view = View.of(context);
  final size = view.physicalSize / view.devicePixelRatio;
  return SharePlus.instance.share(
    ShareParams(
      text: text,
      files: files,
      sharePositionOrigin: Rect.fromCenter(
        center: size.center(Offset.zero),
        width: 1,
        height: 1,
      ),
    ),
  );
}
