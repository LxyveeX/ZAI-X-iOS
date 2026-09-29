import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/app/single_instance.dart';

void main() {
  test('exits quietly when the running window cannot be reached', () async {
    var exited = 0;
    await ensureSingleInstance(
      // 套件连不上另一个视窗的管道时丢出的是 Win32 错误，不是通道错误
      check: () async => throw Exception('pipe not found'),
      exitApp: () => exited++,
    );
    expect(exited, 1);
  });

  test('keeps starting when this is the only window', () async {
    var exited = 0;
    await ensureSingleInstance(check: () async {}, exitApp: () => exited++);
    expect(exited, 0);
  });

  test('keeps starting when the plugin channel itself fails', () async {
    var exited = 0;
    await ensureSingleInstance(
      check: () async => throw MissingPluginException('no plugin'),
      exitApp: () => exited++,
    );
    await ensureSingleInstance(
      check: () async => throw PlatformException(code: 'error'),
      exitApp: () => exited++,
    );
    expect(exited, 0);
  });
}
