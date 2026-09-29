import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/app/single_instance.dart';

void main() {
  group('ensureSingleInstance', () {
    test('keeps starting when this is the only window', () async {
      var quits = 0;
      final keepGoing = await ensureSingleInstance(
        check: (quit) async {},
        quit: () async => quits++,
      );
      expect(keepGoing, isTrue);
      expect(quits, 0);
    });

    test('stops starting after handing over to the open window', () async {
      var quits = 0;
      final keepGoing = await ensureSingleInstance(
        // 套件把参数交给已开的视窗后，呼叫传入的 quit 结束这个进程
        check: (quit) => quit(),
        quit: () async => quits++,
      );
      expect(keepGoing, isFalse);
      expect(quits, 1);
    });

    test('stops starting when the open window cannot be reached', () async {
      var quits = 0;
      final keepGoing = await ensureSingleInstance(
        // 连不上前一个视窗的管道时，套件丢出的是 Win32 错误
        check: (quit) async => throw Exception('pipe not found'),
        quit: () async => quits++,
      );
      expect(keepGoing, isFalse);
      expect(quits, 1);
    });

    test('keeps starting when the plugin channel itself fails', () async {
      var quits = 0;
      for (final error in [
        MissingPluginException('no plugin'),
        PlatformException(code: 'error'),
      ]) {
        final keepGoing = await ensureSingleInstance(
          check: (quit) async => throw error,
          quit: () async => quits++,
        );
        expect(keepGoing, isTrue);
      }
      expect(quits, 0);
    });
  });

  group('quitApp', () {
    test('closes the main window and forces the exit only if still running',
        () async {
      var closed = 0;
      var forced = 0;
      await quitApp(
        windows: true,
        fallback: const Duration(milliseconds: 20),
        closeWindow: () {
          closed++;
          return true;
        },
        forceExit: () => forced++,
      );
      expect(closed, 1);
      // 正常关闭会结束整个进程；还活着才在期限后强制结束
      expect(forced, 0);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(forced, 1);
    });

    test('forces the exit at once when the window cannot be closed', () async {
      for (final closeWindow in <bool Function()>[
        () => false,
        () => throw StateError('user32 unavailable'),
      ]) {
        var forced = 0;
        await quitApp(
          windows: true,
          fallback: const Duration(milliseconds: 20),
          closeWindow: closeWindow,
          forceExit: () => forced++,
        );
        expect(forced, 1);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(forced, 1);
      }
    });

    test('exits directly on other platforms', () async {
      var closed = 0;
      var forced = 0;
      await quitApp(
        windows: false,
        closeWindow: () {
          closed++;
          return true;
        },
        forceExit: () => forced++,
      );
      expect(closed, 0);
      expect(forced, 1);
    });

    test('finds no main window in a process without one', () {
      // 测试进程没有 App 的主视窗：绑定要能载入，而且不能误关别的视窗
      expect(closeMainWindow(), isFalse);
    }, skip: !Platform.isWindows);
  });
}
