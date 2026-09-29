import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:zai_x/modules/hitomi/author_unlock.dart';

Future<void> _tapAuthor(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text('funkeyyou'));
  }
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String command) async {
  await tester.enterText(find.byType(TextField), command);
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
}

void main() {
  var unlocks = 0;
  Widget screen() => MaterialApp(
        home: Scaffold(
          body: AuthorUnlock(onUnlock: () async {
            unlocks++;
          }),
        ),
      );
  setUp(() => unlocks = 0);

  testWidgets('ten taps ask for a command without revealing it',
      (tester) async {
    await tester.pumpWidget(screen());
    await _tapAuthor(tester, 9);
    expect(find.byType(TextField), findsNothing);
    await _tapAuthor(tester, 1);
    expect(find.byType(TextField), findsOneWidget);
    expect(unlocks, 0);
    expect(find.textContaining(RegExp('hitomi', caseSensitive: false)),
        findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    // The keyboard must not correct, suggest or remember the command.
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
  });

  testWidgets('the right command opens the entry', (tester) async {
    await tester.pumpWidget(screen());
    await _tapAuthor(tester, 10);
    await _submit(tester, 'hitomi');
    expect(unlocks, 1);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('keyboard submit tolerates capitals and stray spaces',
      (tester) async {
    await tester.pumpWidget(screen());
    await _tapAuthor(tester, 10);
    await tester.enterText(find.byType(TextField), ' Hitomi ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(unlocks, 1);
  });

  testWidgets('a wrong command does nothing and shows nothing', (tester) async {
    await tester.pumpWidget(screen());
    await _tapAuthor(tester, 10);
    await _submit(tester, 'hitomi2');
    expect(unlocks, 0);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Only the author name is left on screen: no message of any kind.
    expect(find.byType(Text), findsOneWidget);
    // Another attempt needs a full ten taps again.
    await _tapAuthor(tester, 9);
    expect(find.byType(TextField), findsNothing);
    await _tapAuthor(tester, 1);
    await _submit(tester, 'hitomi');
    expect(unlocks, 1);
  });

  testWidgets('empty input, cancel and tapping outside do nothing',
      (tester) async {
    await tester.pumpWidget(screen());
    await _tapAuthor(tester, 10);
    await _submit(tester, '');
    await _tapAuthor(tester, 10);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await _tapAuthor(tester, 10);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Text), findsOneWidget);
    expect(unlocks, 0);
  });

  testWidgets('reopening resets a partial sequence', (tester) async {
    await tester.pumpWidget(screen());
    await _tapAuthor(tester, 5);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await _tapAuthor(tester, 5);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the prompt closes before the about dialog is dismissed',
      (tester) async {
    Get.testMode = true;
    var opened = 0;
    await tester.pumpWidget(GetMaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'app',
              children: [
                AuthorUnlock(onUnlock: () async {
                  opened++;
                  Get.back();
                }),
              ],
            ),
            child: const Text('about'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('about'));
    await tester.pumpAndSettle();
    await _tapAuthor(tester, 10);
    await _submit(tester, 'hitomi');
    expect(opened, 1);
    expect(find.byType(AboutDialog), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('about'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}
