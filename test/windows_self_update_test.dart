import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zai_x/requests/common_request.dart';
import 'package:zai_x/services/windows_self_update.dart';

File _file(Directory root, String relative) =>
    File(p.joinAll([root.path, ...relative.split('/')]));

void _write(Directory root, Map<String, String> files) {
  files.forEach((relative, content) {
    final file = _file(root, relative);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
}

String _read(Directory root, String relative) =>
    _file(root, relative).readAsStringSync();

List<int> _zip(Map<String, String> files, {List<String> dirs = const []}) {
  final archive = Archive();
  for (final dir in dirs) {
    archive.addFile(ArchiveFile.directory(dir));
  }
  files.forEach((name, content) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
  });
  return ZipEncoder().encodeBytes(archive);
}

const _bundle = {
  'ZAI-X.exe': 'exe',
  'flutter_windows.dll': 'dll',
  'data/app.so': 'aot',
  'data/icudtl.dat': 'icu',
  'data/flutter_assets/AssetManifest.bin': 'assets',
};

void main() {
  group('release parsing', () {
    Map<String, dynamic> release({bool digest = true}) => {
          'tag_name': 'v2.1.1',
          'html_url': 'https://example.invalid/releases/v2.1.1',
          'body': ' notes ',
          'assets': [
            {
              'name': 'ZAI-X-android.apk',
              'browser_download_url': 'https://example.invalid/app.apk',
              'size': 10,
              if (digest) 'digest': 'sha256:AA11',
            },
            {
              'name': 'ZAI-X-windows-x64.zip',
              'browser_download_url': 'https://example.invalid/app.zip',
              'size': 20,
              if (digest) 'digest': 'sha256:BB22',
            },
          ],
        };

    test('each platform takes its own asset with digest and size', () {
      final windows =
          CommonRequest.parseRelease(release(), android: false, windows: true);
      expect(windows.version, '2.1.1');
      expect(windows.versionNum, 20101);
      expect(windows.versionDesc, 'notes');
      expect(windows.downloadUrl, endsWith('app.zip'));
      expect(windows.sha256, 'bb22');
      expect(windows.size, 20);

      final android =
          CommonRequest.parseRelease(release(), android: true, windows: false);
      expect(android.downloadUrl, endsWith('app.apk'));
      expect(android.sha256, 'aa11');

      final other =
          CommonRequest.parseRelease(release(), android: false, windows: false);
      expect(other.downloadUrl, endsWith('/releases/v2.1.1'));
      expect(other.sha256, isEmpty);
    });

    test('a release without digests leaves the hash empty', () {
      final windows = CommonRequest.parseRelease(release(digest: false),
          android: false, windows: true);
      expect(windows.downloadUrl, endsWith('app.zip'));
      expect(windows.sha256, isEmpty);
    });
  });

  group('download check', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('zaix-verify-');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('accepts the published hash and rejects anything else', () async {
      final file = File(p.join(dir.path, 'update.zip'))
        ..writeAsBytesSync([1, 2, 3]);
      final hash = sha256.convert([1, 2, 3]).toString();
      await WindowsSelfUpdate.verifyDownload(file,
          sha256Hex: hash.toUpperCase(), size: 3);
      await expectLater(
          WindowsSelfUpdate.verifyDownload(file, sha256Hex: hash, size: 4),
          throwsA(isA<UpdateIntegrityException>()));
      await expectLater(
          WindowsSelfUpdate.verifyDownload(file, sha256Hex: 'ab' * 32),
          throwsA(isA<UpdateIntegrityException>()));
      await expectLater(WindowsSelfUpdate.verifyDownload(file, sha256Hex: ''),
          throwsA(isA<UpdateIntegrityException>()));
    });
  });

  group('extraction and results', () {
    late Directory root;
    late WindowsSelfUpdate updater;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('zaix-extract-');
      updater = WindowsSelfUpdate(
        installDir: Directory(p.join(root.path, 'app')),
        workDir: Directory(p.join(root.path, WindowsSelfUpdate.workDirName)),
      );
      await updater.resetWorkDir();
    });
    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('extracts a complete package including folder entries', () async {
      updater.zipFile.writeAsBytesSync(
          _zip(_bundle, dirs: ['data/', 'data/flutter_assets/packages/']));
      final files = await updater.extract();
      expect(files.map((f) => f.replaceAll(r'\', '/')).toSet(),
          _bundle.keys.toSet());
      for (final entry in _bundle.entries) {
        expect(_read(updater.stagingDir, entry.key), entry.value);
      }
      expect(
          Directory(p.join(updater.stagingDir.path, 'data', 'flutter_assets',
                  'packages'))
              .existsSync(),
          isTrue);
    });

    test('rejects entries that would leave the staging folder', () async {
      updater.zipFile
          .writeAsBytesSync(_zip({..._bundle, '../escaped.txt': 'x'}));
      await expectLater(
          updater.extract(), throwsA(isA<UpdateIntegrityException>()));
      expect(File(p.join(updater.workDir.path, 'escaped.txt')).existsSync(),
          isFalse);
    });

    test('rejects a package without the Flutter runtime', () async {
      updater.zipFile
          .writeAsBytesSync(_zip(Map.of(_bundle)..remove('data/app.so')));
      await expectLater(
          updater.extract(), throwsA(isA<UpdateIntegrityException>()));
    });

    test('only deletes its own work folder', () async {
      final unrelated = WindowsSelfUpdate(installDir: root, workDir: root);
      await expectLater(unrelated.resetWorkDir(), throwsStateError);
      expect(root.existsSync(), isTrue);
    });

    test('the result is shown once and temporary files are removed', () async {
      updater.resultFile.writeAsStringSync(jsonEncode({
        'status': 'ok',
        'version': '2.1.1',
        'detail': '',
        // Same folder, written differently: case and trailing separator.
        'installDir': '${updater.installDir.path.toUpperCase()}\\',
      }));
      updater.zipFile.writeAsBytesSync([1]);
      updater.stagingDir.createSync();
      updater.logFile.writeAsStringSync('log');
      final outcome = await updater.takeOutcome(currentVersion: '2.1.1');
      expect(outcome!.ok, isTrue);
      expect(outcome.version, '2.1.1');
      expect(updater.resultFile.existsSync(), isFalse);
      expect(updater.zipFile.existsSync(), isFalse);
      expect(updater.stagingDir.existsSync(), isFalse);
      expect(updater.logFile.existsSync(), isTrue);
      expect(await updater.takeOutcome(currentVersion: '2.1.1'), isNull);
    });

    test('a result from another installation is left for that copy', () async {
      updater.resultFile.writeAsStringSync(jsonEncode({
        'status': 'ok',
        'version': '2.1.1',
        'detail': '',
        'installDir': p.join(root.path, 'another copy'),
      }));
      updater.zipFile.writeAsBytesSync([1]);
      expect(await updater.takeOutcome(currentVersion: '2.1.1'), isNull);
      expect(updater.resultFile.existsSync(), isTrue);
      expect(updater.zipFile.existsSync(), isTrue);
    });

    test('a success that does not match the running version is not shown',
        () async {
      updater.resultFile.writeAsStringSync(jsonEncode({
        'status': 'ok',
        'version': '2.1.1',
        'detail': '',
        'installDir': updater.installDir.path,
      }));
      expect(await updater.takeOutcome(currentVersion: '2.0.9'), isNull);
      expect(updater.resultFile.existsSync(), isFalse);
    });

    test('a failure is reported to the version that was kept', () async {
      updater.resultFile.writeAsStringSync(jsonEncode({
        'status': 'failed',
        'version': '2.1.1',
        'detail': 'app did not exit',
        'installDir': updater.installDir.path,
      }));
      final outcome = await updater.takeOutcome(currentVersion: '2.0.9');
      expect(outcome!.ok, isFalse);
      expect(outcome.detail, 'app did not exit');
    });
  });

  group('update helper', () {
    late Directory root;
    late Directory install;
    late WindowsSelfUpdate updater;
    late File exe;
    late String exeVersion;
    const old = {
      'ZAI-X.exe': 'old exe',
      'flutter_windows.dll': 'old dll',
      'data/app.so': 'old aot',
      'data/icudtl.dat': 'old icu',
      'keep.txt': 'not part of the package',
    };

    setUp(() async {
      root = await Directory.systemTemp.createTemp('zaix-helper-');
      // A space and CJK text in the path exercise argument quoting.
      install = Directory(p.join(root.path, 'App 再漫畫'))..createSync();
      updater = WindowsSelfUpdate(
        installDir: install,
        workDir: Directory(p.join(root.path, WindowsSelfUpdate.workDirName)),
      );
      await updater.resetWorkDir();
      _write(install, old);
      // Any real executable carries a ProductVersion for the helper to check.
      exe = File(p.join(
          Platform.environment['SystemRoot']!, 'System32', 'whoami.exe'));
      final staging = updater.stagingDir..createSync(recursive: true);
      final staged = exe.copySync(p.join(staging.path, 'ZAI-X.exe'));
      _write(staging, {
        'flutter_windows.dll': 'new dll',
        'data/app.so': 'new aot',
        'data/icudtl.dat': 'new icu',
        'added.txt': 'new root file',
        'data/flutter_assets/new.txt': 'new asset',
      });
      // Read the copy: the system file reports the version of its MUI file.
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        "[System.Diagnostics.FileVersionInfo]::GetVersionInfo('${staged.path}').ProductVersion",
      ]);
      exeVersion = (result.stdout as String).trim().split('+').first;
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    Future<Process> fakeApp(int seconds) => Process.start(
        'powershell.exe', ['-NoProfile', '-Command', 'Start-Sleep $seconds']);

    Future<String> runHelper(int appPid, String version,
        {int waitSeconds = 30}) async {
      await updater.launch(
        appPid: appPid,
        version: version,
        relaunch: false,
        waitSeconds: waitSeconds,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (true) {
        final log = updater.logFile.existsSync()
            ? updater.logFile.readAsStringSync()
            : '';
        if (log.contains('finished')) return log;
        if (DateTime.now().isAfter(deadline)) fail('helper stuck: $log');
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    test('replaces the package after the app exits and keeps other files',
        () async {
      final app = await fakeApp(2);
      final log = await runHelper(app.pid, exeVersion);
      expect(await app.exitCode, 0);
      expect(log, contains('replaced 4 files, added 2 files'));
      expect(_file(install, 'ZAI-X.exe').lengthSync(), exe.lengthSync());
      expect(_read(install, 'flutter_windows.dll'), 'new dll');
      expect(_read(install, 'data/app.so'), 'new aot');
      expect(_read(install, 'data/icudtl.dat'), 'new icu');
      expect(_read(install, 'added.txt'), 'new root file');
      expect(_read(install, 'data/flutter_assets/new.txt'), 'new asset');
      expect(_read(install, 'keep.txt'), 'not part of the package');
      expect(Directory(p.join(install.path, '.update-backup')).existsSync(),
          isFalse);
      expect(updater.stagingDir.existsSync(), isFalse);
      final outcome = await updater.takeOutcome(currentVersion: exeVersion);
      expect(outcome!.ok, isTrue);
      expect(outcome.version, exeVersion);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('puts every file back when one file cannot be replaced', () async {
      // Holding the file open without delete sharing blocks the rename.
      final lock = _file(install, 'data/app.so').openSync();
      try {
        final app = await fakeApp(1);
        final log = await runHelper(app.pid, exeVersion);
        expect(log, contains('restored 2 files'));
      } finally {
        lock.closeSync();
      }
      for (final entry in old.entries) {
        expect(_read(install, entry.key), entry.value);
      }
      expect(_file(install, 'added.txt').existsSync(), isFalse);
      expect(
          _file(install, 'data/flutter_assets/new.txt').existsSync(), isFalse);
      expect(Directory(p.join(install.path, '.update-backup')).existsSync(),
          isFalse);
      final outcome = await updater.takeOutcome();
      expect(outcome!.ok, isFalse);
      expect(outcome.detail, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('refuses a package whose version does not match', () async {
      final app = await fakeApp(1);
      final log = await runHelper(app.pid, '0.0.1');
      expect(log, contains('does not match'));
      for (final entry in old.entries) {
        expect(_read(install, entry.key), entry.value);
      }
      expect((await updater.takeOutcome())!.ok, isFalse);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('leaves everything alone while the app is still running', () async {
      final app = await fakeApp(60);
      try {
        final log = await runHelper(app.pid, exeVersion, waitSeconds: 1);
        expect(log, contains('app did not exit'));
      } finally {
        app.kill();
      }
      for (final entry in old.entries) {
        expect(_read(install, entry.key), entry.value);
      }
      expect((await updater.takeOutcome())!.ok, isFalse);
    }, timeout: const Timeout(Duration(seconds: 90)));
  }, skip: Platform.isWindows ? false : 'Windows only');
}
