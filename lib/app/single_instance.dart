import 'dart:io';

import 'package:flutter/services.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:zai_x/app/log.dart';

/// Windows 只开一个视窗：已经开着就把那个视窗叫到前面，这个进程直接结束。
///
/// 前一个视窗还没完全关闭、或同时点了两次时，互斥锁还在却连不上它的管道，
/// windows_single_instance 会直接抛错。main() 因此停在 runApp 之前，留下一个
/// 永远白画面的视窗；它还占着互斥锁，之后再开也会一样变白。
/// 所以连不上另一个视窗时就安静结束，使用者再点一次即可正常开启。
/// 插件本身出错（通道错误）时照常启动，宁可多开也不要完全打不开。
Future<void> ensureSingleInstance({
  Future<void> Function()? check,
  void Function()? exitApp,
}) async {
  try {
    await (check ?? _check)();
  } on PlatformException catch (e) {
    Log.logPrint(e);
  } on MissingPluginException catch (e) {
    Log.logPrint(e);
  } catch (e) {
    Log.logPrint(e);
    (exitApp ?? _exit)();
  }
}

Future<void> _check() => WindowsSingleInstance.ensureSingleInstance(
      [],
      "com.xycz.zmhx",
      onSecondWindow: (args) => Log.logPrint(args),
    );

void _exit() => exit(0);
