import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zai_x/app/system_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final calls = <Map<dynamic, dynamic>>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.arguments as Map<dynamic, dynamic>);
          return 'shared';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'link and CBZ sharing keep the anchor inside the resized iPad view',
    (tester) async {
      late BuildContext context;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (final physicalSize in [
        const Size(1536, 2048),
        const Size(2048, 1536),
        const Size(640, 1536),
      ]) {
        tester.view.physicalSize = physicalSize;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (value) {
                context = value;
                return const SizedBox.expand();
              },
            ),
          ),
        );
        await shareSystemContent(context: context, text: 'https://example.com');
        await shareSystemContent(
          context: context,
          files: [XFile('/tmp/comic.cbz')],
        );
        final logical = physicalSize / 2;
        for (final call in calls.skip(calls.length - 2)) {
          final rect = Rect.fromLTWH(
            call['originX'] as double,
            call['originY'] as double,
            call['originWidth'] as double,
            call['originHeight'] as double,
          );
          expect(rect.isEmpty, isFalse);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(logical.width));
          expect(rect.bottom, lessThanOrEqualTo(logical.height));
        }
        expect(calls[calls.length - 2]['text'], 'https://example.com');
        expect(calls.last['paths'], ['/tmp/comic.cbz']);
      }
    },
  );
}
