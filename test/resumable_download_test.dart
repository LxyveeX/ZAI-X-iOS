import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zai_x/services/resumable_download.dart';

/// Local server that can drop or stall the first responses to mimic a flaky
/// link to GitHub's release CDN.
class _Server {
  _Server(this.payload);
  final Uint8List payload;
  late HttpServer server;
  final ranges = <String?>[];
  final held = <Socket>[];

  /// Behaviour per request, in order; later requests are served normally.
  final plan = <String>[];
  bool honourRange = true;

  String get url => 'http://127.0.0.1:${server.port}/app.zip';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    var start = 0;
    if (honourRange && range != null) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    }
    final body = Uint8List.sublistView(payload, start);
    final response = request.response;
    response.statusCode = start > 0 ? 206 : 200;
    response.headers.contentType = ContentType.binary;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.contentLength = body.length;
    final action = plan.isEmpty ? 'ok' : plan.removeAt(0);
    if (action == 'ok') {
      response.add(body);
      await response.close();
      return;
    }
    final socket = await response.detachSocket();
    socket.add(Uint8List.sublistView(body, 0, body.length ~/ 3));
    await socket.flush();
    if (action == 'drop') {
      socket.destroy();
    } else {
      held.add(socket); // stall: keep the connection open without data
    }
  }

  Future<void> stop() async {
    for (final socket in held) {
      socket.destroy();
    }
    await server.close(force: true);
  }
}

void main() {
  late Directory dir;
  late _Server server;
  late File file;
  final payload =
      Uint8List.fromList(List.generate(300 * 1024, (i) => (i * 31) % 251));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zaix-resume-');
    file = File(p.join(dir.path, 'update.zip'));
    server = _Server(payload);
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<List<int>> run({
    CancelToken? cancelToken,
    int maxAttempts = 4,
    int expectedSize = 0,
    void Function(int, int)? onProgress,
    void Function(int)? onRetry,
  }) async {
    final progress = <int>[];
    await downloadWithResume(
      Dio(),
      server.url,
      file,
      cancelToken: cancelToken,
      expectedSize: expectedSize,
      maxAttempts: maxAttempts,
      stallTimeout: const Duration(milliseconds: 400),
      retryDelay: (_) => Duration.zero,
      onRetry: onRetry,
      onProgress: (received, total) {
        progress.add(received);
        onProgress?.call(received, total);
      },
    );
    return progress;
  }

  test('resumes from the received bytes after the connection drops', () async {
    server.plan.add('drop');
    var retries = 0;
    final progress =
        await run(expectedSize: payload.length, onRetry: (_) => retries++);
    expect(await file.readAsBytes(), payload);
    expect(server.ranges.first, isNull);
    expect(server.ranges[1], 'bytes=${payload.length ~/ 3}-');
    expect(retries, 1);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(progress.last, payload.length);
  });

  test('a stalled connection is abandoned and resumed', () async {
    server.plan.add('stall');
    await run(expectedSize: payload.length);
    expect(await file.readAsBytes(), payload);
    expect(server.ranges, hasLength(2));
    expect(server.ranges[1], startsWith('bytes='));
  });

  test('starts over when the server ignores the range request', () async {
    server
      ..honourRange = false
      ..plan.add('drop');
    await run(expectedSize: payload.length);
    expect(await file.readAsBytes(), payload);
  });

  test('works without a known size', () async {
    server.plan.add('drop');
    await run();
    expect(await file.readAsBytes(), payload);
  });

  test('gives up after the last attempt', () async {
    server.plan.addAll(['drop', 'drop', 'drop']);
    await expectLater(run(maxAttempts: 3), throwsA(anything));
    expect(server.ranges, hasLength(3));
  });

  test('cancelling stops at once without retrying', () async {
    server.plan.add('stall');
    final token = CancelToken();
    Object? error;
    try {
      await run(
        cancelToken: token,
        onProgress: (received, _) {
          if (received > 0 && !token.isCancelled) token.cancel();
        },
      );
    } catch (e) {
      error = e;
    }
    expect(error, isA<DioException>());
    expect(CancelToken.isCancel(error as DioException), isTrue);
    expect(server.ranges, hasLength(1));
  });
}
