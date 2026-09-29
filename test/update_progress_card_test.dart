import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/services/app_update_service.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final entry in {
    'dark': AppStyle.darkTheme,
    'light': AppStyle.lightTheme,
  }.entries) {
    testWidgets('update progress title stays readable in ${entry.key} theme',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: entry.value,
        home: const Material(
          color: Colors.transparent,
          // The dialog layer hands its content a default style that does not
          // follow the app theme; the title must not depend on it.
          child: DefaultTextStyle(
            style: TextStyle(color: Colors.black87),
            child: Center(child: UpdateProgressCard()),
          ),
        ),
      ));
      final title = tester.renderObject<RenderParagraph>(find.text('正在下载新版本'));
      final color = title.text.style!.color!;
      expect(_contrast(color, entry.value.cardColor), greaterThan(4.5));
      expect(find.text('取消'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
