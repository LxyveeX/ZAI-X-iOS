import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 下载的更新档与 GitHub 公布的内容不符，或不是完整的 Windows 包
class UpdateIntegrityException implements Exception {
  UpdateIntegrityException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 更新脚本写下的结果，App 下次启动时读取
class WindowsUpdateOutcome {
  const WindowsUpdateOutcome({
    required this.ok,
    required this.version,
    required this.detail,
  });
  final bool ok;
  final String version;
  final String detail;
}

/// Windows 自动覆盖更新
///
/// 执行中的 exe、DLL 被系统锁住，App 无法覆盖自己，所以分两段：
/// 1. App 下载 zip，核对 GitHub 公布的 SHA-256 与大小，解压到暂存资料夹；
/// 2. 启动隐藏的 PowerShell 更新脚本后 App 自行结束。脚本等 App 结束，先把
///    旧档移进安装资料夹的 .update-backup，再复制新档；全部成功才删除备份
///    并开启新版，任何一步失败都把旧档搬回原位并开启原来的版本。
///
/// 使用者资料在 %APPDATA%，不在安装资料夹，覆盖安装碰不到。
class WindowsSelfUpdate {
  WindowsSelfUpdate({required this.installDir, required this.workDir});

  factory WindowsSelfUpdate.forCurrentApp() => WindowsSelfUpdate(
        installDir: File(Platform.resolvedExecutable).parent,
        workDir: Directory(p.join(Directory.systemTemp.path, workDirName)),
      );

  static const workDirName = 'ZAI-X-update';
  static const exeName = 'ZAI-X.exe';

  /// 正式包一定有的档案；缺任何一个就不是完整的 Windows 包
  static const requiredFiles = [
    exeName,
    'flutter_windows.dll',
    'data/app.so',
    'data/icudtl.dat',
  ];

  final Directory installDir;
  final Directory workDir;

  File get zipFile => File(p.join(workDir.path, 'update.zip'));
  Directory get stagingDir => Directory(p.join(workDir.path, 'staging'));
  File get scriptFile => File(p.join(workDir.path, 'apply-update.ps1'));
  File get resultFile => File(p.join(workDir.path, 'result.json'));
  File get logFile => File(p.join(workDir.path, 'apply-update.log'));

  static String _join(Directory dir, String relative) =>
      p.joinAll([dir.path, ...relative.split('/')]);

  /// 安装资料夹是完整的正式包（开发版没有 app.so）
  bool get isInstalledBundle =>
      requiredFiles.every((f) => File(_join(installDir, f)).existsSync());

  /// 能否在安装资料夹新增、删除档案（放在 Program Files 通常不行）
  Future<bool> canWriteInstallDir() async {
    final probe = File(p.join(installDir.path, '.zaix-write-test-$pid'));
    try {
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
      return false;
    }
  }

  /// 清空工作资料夹；只删除这个功能自己建立的资料夹
  Future<void> resetWorkDir() async {
    if (!p.basename(workDir.path).startsWith(workDirName)) {
      throw StateError('unexpected update folder: ${workDir.path}');
    }
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);
  }

  /// 核对大小与 SHA-256（GitHub Release 资产的 digest）
  static Future<void> verifyDownload(
    File file, {
    required String sha256Hex,
    int size = 0,
  }) async {
    final length = await file.length();
    if (size > 0 && length != size) {
      throw UpdateIntegrityException('size $length, expected $size');
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (sha256Hex.isEmpty || digest.toString() != sha256Hex.toLowerCase()) {
      throw UpdateIntegrityException('sha256 mismatch');
    }
  }

  /// 解压 [zipPath] 到 [outDir]，回传解出的档案相对路径。
  ///
  /// 不用 archive 的 extractArchiveToDisk：它会吞掉写档错误，留下不完整的档案。
  /// 这里任何一个档案写不完整、或路径跳出目标资料夹，都直接失败。
  static List<String> extractSync(String zipPath, String outDir) {
    final root = p.normalize(p.absolute(outDir));
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final files = <String>[];
      for (final entry in archive) {
        final target = p.normalize(p.join(root, entry.name));
        if (!entry.isFile && p.equals(target, root)) continue;
        if (entry.isSymbolicLink || !p.isWithin(root, target)) {
          throw UpdateIntegrityException('unsafe entry ${entry.name}');
        }
        if (!entry.isFile) {
          Directory(target).createSync(recursive: true);
          continue;
        }
        Directory(p.dirname(target)).createSync(recursive: true);
        final output = OutputFileStream(target);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        if (File(target).lengthSync() != entry.size) {
          throw UpdateIntegrityException('incomplete ${entry.name}');
        }
        files.add(p.relative(target, from: root));
      }
      return files;
    } finally {
      input.closeSync();
    }
  }

  static Future<List<String>> _extractInBackground(String zip, String out) =>
      Isolate.run(() => extractSync(zip, out));

  /// 解压到暂存资料夹，并确认必要档案都在
  Future<List<String>> extract() async {
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }
    final files = await _extractInBackground(zipFile.path, stagingDir.path);
    final missing = requiredFiles
        .where((f) => !File(_join(stagingDir, f)).existsSync())
        .toList();
    if (missing.isNotEmpty) {
      throw UpdateIntegrityException('missing ${missing.join(', ')}');
    }
    return files;
  }

  /// 写出并启动更新脚本。确认脚本已经开始执行才回传，App 接着就可以结束；
  /// 逾时代表脚本没跑起来，App 不能结束。
  Future<void> launch({
    required int appPid,
    required String version,
    bool relaunch = true,
    int waitSeconds = 60,
    Duration startTimeout = const Duration(seconds: 15),
  }) async {
    await scriptFile.writeAsString(applyUpdateScript, flush: true);
    for (final file in [resultFile, logFile]) {
      if (await file.exists()) await file.delete();
    }
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final powershell = p.join(
        systemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    // 不能用 ProcessStartMode.detached：那样 PowerShell 5.1 没有主控台，
    // 脚本根本不会执行。一般模式从 GUI 程式启动时拿到的是看不见的主控台，
    // App 结束后脚本也会继续跑完。
    final helper = await Process.start(
      powershell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptFile.path,
        '-AppPid',
        '$appPid',
        '-InstallDir',
        installDir.path,
        '-StagingDir',
        stagingDir.path,
        '-Version',
        version,
        '-ResultPath',
        resultFile.path,
        '-LogPath',
        logFile.path,
        '-WaitSeconds',
        '$waitSeconds',
        if (!relaunch) '-NoRelaunch',
      ],
    );
    // App 还在的期间持续读掉输出，免得管线塞满卡住脚本
    unawaited(helper.stdout.drain<void>());
    unawaited(helper.stderr.drain<void>());
    unawaited(helper.stdin.close());
    int? exitCode;
    unawaited(helper.exitCode.then((code) => exitCode = code));

    Future<bool> started() async {
      try {
        return await logFile.exists() &&
            (await logFile.readAsString()).contains('started');
      } on FileSystemException {
        // 脚本正在写入，下一轮再读
        return false;
      }
    }

    final deadline = DateTime.now().add(startTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await started()) {
        return;
      }
      if (exitCode != null) {
        if (await started()) {
          return;
        }
        throw StateError('update helper exited early with code $exitCode');
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('update helper did not start');
  }

  /// 读取并清掉上次更新留下的结果与暂存档；没有更新过就回传 null。
  ///
  /// 暂存资料夹是所有安装共用的：结果属于别的安装资料夹时原封不动留给那一份；
  /// 成功但版本和 [currentVersion] 不同（例如重新开启的是旧版），视为过时不显示。
  Future<WindowsUpdateOutcome?> takeOutcome({String? currentVersion}) async {
    if (!await workDir.exists()) return null;
    WindowsUpdateOutcome? outcome;
    if (await resultFile.exists()) {
      try {
        final json = jsonDecode(await resultFile.readAsString()) as Map;
        final owner = json['installDir'];
        if (owner is String &&
            owner.isNotEmpty &&
            !_sameDirectory(owner, installDir.path)) {
          return null;
        }
        final ok = json['status'] == 'ok';
        final version = '${json['version'] ?? ''}';
        final stale = ok && currentVersion != null && version != currentVersion;
        if (!stale) {
          outcome = WindowsUpdateOutcome(
            ok: ok,
            version: version,
            detail: '${json['detail'] ?? ''}',
          );
        }
      } catch (e) {
        outcome = WindowsUpdateOutcome(ok: false, version: '', detail: '$e');
      }
    }
    for (final entity in <FileSystemEntity>[
      resultFile,
      zipFile,
      scriptFile,
      stagingDir,
    ]) {
      try {
        if (await entity.exists()) await entity.delete(recursive: true);
      } catch (_) {}
    }
    return outcome;
  }

  /// Windows 路径不分大小写，结尾的分隔符号也不影响
  static bool _sameDirectory(String a, String b) {
    String normalize(String path) => p
        .normalize(p.absolute(path))
        .replaceAll(RegExp(r'[\\/]+$'), '')
        .toLowerCase();
    return normalize(a) == normalize(b);
  }
}

/// 更新脚本（Windows PowerShell 5.1，内容只用 ASCII，路径都由参数传入）
const applyUpdateScript = r'''
param(
  [Parameter(Mandatory = $true)][int]$AppPid,
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$StagingDir,
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$ResultPath,
  [Parameter(Mandatory = $true)][string]$LogPath,
  [string]$ExeName = 'ZAI-X.exe',
  [int]$WaitSeconds = 60,
  [switch]$NoRelaunch
)
# ZAI-X updater: waits for the app to exit, replaces the app files, then starts
# the app again. Replaced files stay in .update-backup until every new file is
# copied, so any failure moves the previous files back.
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Log([string]$Message) {
  $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $Message + [Environment]::NewLine
  [System.IO.File]::AppendAllText($LogPath, $line, $utf8)
}
function Invoke-WithRetry([scriptblock]$Action) {
  $attempt = 0
  while ($true) {
    try {
      & $Action
      return
    } catch {
      $attempt++
      if ($attempt -ge 20) { throw }
      Start-Sleep -Milliseconds 500
    }
  }
}
Write-Log "started pid=$AppPid version=$Version"
$InstallDir = $InstallDir.TrimEnd('\')
$StagingDir = $StagingDir.TrimEnd('\')
$backupDir = [System.IO.Path]::Combine($InstallDir, '.update-backup')
$moved = New-Object System.Collections.Generic.List[string]
$created = New-Object System.Collections.Generic.List[string]
$status = 'failed'
$detail = ''
$appExited = $true
try {
  $app = Get-Process -Id $AppPid -ErrorAction SilentlyContinue
  if ($app -and -not $app.WaitForExit($WaitSeconds * 1000)) {
    $appExited = $false
    throw 'app did not exit'
  }
  $stagedExe = [System.IO.Path]::Combine($StagingDir, $ExeName)
  if (-not [System.IO.File]::Exists($stagedExe)) { throw 'staged exe missing' }
  $stagedVersion = ([string][System.Diagnostics.FileVersionInfo]::GetVersionInfo($stagedExe).ProductVersion).Split('+')[0]
  if ($stagedVersion -ne $Version) { throw "staged version $stagedVersion does not match $Version" }
  if ([System.IO.Directory]::Exists($backupDir)) { [System.IO.Directory]::Delete($backupDir, $true) }
  $files = [System.IO.Directory]::GetFiles($StagingDir, '*', [System.IO.SearchOption]::AllDirectories)
  foreach ($source in $files) {
    $relative = $source.Substring($StagingDir.Length + 1)
    $target = [System.IO.Path]::Combine($InstallDir, $relative)
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target))
    if ([System.IO.File]::Exists($target)) {
      $backup = [System.IO.Path]::Combine($backupDir, $relative)
      [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($backup))
      Invoke-WithRetry { [System.IO.File]::Move($target, $backup) }
      $moved.Add($relative)
    } else {
      $created.Add($relative)
    }
    Invoke-WithRetry { [System.IO.File]::Copy($source, $target, $true) }
  }
  $status = 'ok'
  Write-Log "replaced $($moved.Count) files, added $($created.Count) files"
} catch {
  $detail = $_.Exception.Message
  Write-Log "failed: $detail"
  $restoreFailed = $false
  foreach ($relative in $created) {
    $target = [System.IO.Path]::Combine($InstallDir, $relative)
    try {
      if ([System.IO.File]::Exists($target)) { [System.IO.File]::Delete($target) }
    } catch { Write-Log "cleanup failed: $relative" }
  }
  foreach ($relative in $moved) {
    $target = [System.IO.Path]::Combine($InstallDir, $relative)
    $backup = [System.IO.Path]::Combine($backupDir, $relative)
    try {
      Invoke-WithRetry {
        if ([System.IO.File]::Exists($target)) { [System.IO.File]::Delete($target) }
        [System.IO.File]::Move($backup, $target)
      }
    } catch {
      $restoreFailed = $true
      Write-Log "restore failed: $relative"
    }
  }
  if ($moved.Count -gt 0) { Write-Log "restored $($moved.Count) files" }
  if (-not $restoreFailed -and [System.IO.Directory]::Exists($backupDir)) {
    try { [System.IO.Directory]::Delete($backupDir, $true) } catch { Write-Log 'backup cleanup failed' }
  }
}
$result = ConvertTo-Json -Compress -InputObject @{ status = $status; version = $Version; detail = $detail; installDir = $InstallDir }
[System.IO.File]::WriteAllText($ResultPath, $result, $utf8)
if ($status -eq 'ok') {
  foreach ($dir in @($backupDir, $StagingDir)) {
    try {
      if ([System.IO.Directory]::Exists($dir)) { [System.IO.Directory]::Delete($dir, $true) }
    } catch { Write-Log "cleanup: $($_.Exception.Message)" }
  }
}
if (-not $NoRelaunch -and $appExited) {
  try {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = [System.IO.Path]::Combine($InstallDir, $ExeName)
    $start.WorkingDirectory = $InstallDir
    $start.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($start)
    Write-Log 'relaunched'
  } catch { Write-Log "relaunch failed: $($_.Exception.Message)" }
}
Write-Log 'finished'
''';
