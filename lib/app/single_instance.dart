import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:zai_x/app/log.dart';

/// 检查是否已有视窗开着；传入的 quit 用来结束这个进程
typedef SingleInstanceCheck = Future<void> Function(
    Future<void> Function() quit);

/// Windows 只开一个视窗。返回 false 表示这个进程正在结束，main() 应直接返回。
///
/// 已经开着一个视窗时，把那个视窗叫到前面，这个进程结束。
/// 前一个视窗还没完全关闭、或同时点了两次时，互斥锁还在却连不上它的管道，
/// windows_single_instance 会直接抛错；以前 main() 因此停在 runApp 之前，
/// 留下一个永远白画面的视窗。现在连不上就结束这个进程，使用者再点一次即可。
/// 插件本身出错（通道错误）时照常启动，宁可多开也不要完全打不开。
Future<bool> ensureSingleInstance({
  SingleInstanceCheck? check,
  Future<void> Function()? quit,
}) async {
  var quitting = false;
  Future<void> quitOnce() async {
    if (quitting) return;
    quitting = true;
    await (quit ?? quitApp)();
  }

  try {
    await (check ?? _check)(quitOnce);
  } on PlatformException catch (e) {
    Log.logPrint(e);
  } on MissingPluginException catch (e) {
    Log.logPrint(e);
  } catch (e) {
    Log.logPrint(e);
    await quitOnce();
  }
  return !quitting;
}

Future<void> _check(Future<void> Function() quit) =>
    WindowsSingleInstance.ensureSingleInstance(
      [],
      "com.xycz.zmhx",
      onSecondWindow: (args) => Log.logPrint(args),
      exitFunction: quit,
    );

/// 结束 App。
///
/// Windows 上关闭自己的主视窗，跟按右上角关闭走同一套流程，由 Flutter 引擎
/// 依序收尾后结束进程。不直接用 exit(0)：实测它偶尔会让进程卡在结束途中，
/// 一直占着单实例的互斥锁，之后再点开 App 都没有反应，自动更新也等不到 App
/// 结束；也不用 Flutter 的 exitApplication：它直接结束讯息循环，实测会在引擎
/// 收尾时当掉。找不到视窗，或 [fallback] 之后还没结束，才改用 exit(0)。
Future<void> quitApp({
  Duration fallback = const Duration(seconds: 5),
  bool? windows,
  bool Function()? closeWindow,
  void Function()? forceExit,
}) async {
  final force = forceExit ?? () => exit(0);
  if (!(windows ?? Platform.isWindows)) {
    force();
    return;
  }
  var closing = false;
  try {
    closing = (closeWindow ?? closeMainWindow)();
  } catch (e) {
    Log.logPrint(e);
  }
  if (!closing) {
    force();
    return;
  }
  Timer(fallback, force);
}

/// 对这个进程的主视窗送出关闭讯息（WM_CLOSE）；找不到视窗时返回 false。
bool closeMainWindow() {
  final user32 = DynamicLibrary.open('user32.dll');
  final findWindowEx = user32.lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
  final getWindowThreadProcessId = user32.lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
  final postMessage = user32.lookupFunction<
      Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)>('PostMessageW');
  // windows/runner/win32_window.cpp 注册的视窗类别
  final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final owner = calloc<Uint32>();
  try {
    var hwnd = 0;
    while ((hwnd = findWindowEx(0, hwnd, className, nullptr)) != 0) {
      getWindowThreadProcessId(hwnd, owner);
      if (owner.value == pid) {
        const wmClose = 0x0010;
        return postMessage(hwnd, wmClose, 0, 0) != 0;
      }
    }
    return false;
  } finally {
    calloc.free(className);
    calloc.free(owner);
  }
}
