import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// 可续传的下载
///
/// 连到 GitHub 的线路时常中断或卡住，一次下载 29 MB 常常失败。中断或超过
/// [stallTimeout] 没有收到资料时，用 HTTP Range 从已收到的位置接着下载，
/// 最多尝试 [maxAttempts] 次。伺服器不支援 Range 时从头重新下载。
/// 取消时立即抛出取消的 [DioException]，不再重试。
Future<void> downloadWithResume(
  Dio dio,
  String url,
  File file, {
  CancelToken? cancelToken,
  void Function(int received, int total)? onProgress,
  void Function(int attempt)? onRetry,
  int expectedSize = 0,
  int maxAttempts = 6,
  Duration stallTimeout = const Duration(seconds: 30),
  Duration Function(int attempt)? retryDelay,
}) async {
  for (var attempt = 1;; attempt++) {
    try {
      await _downloadOnce(
        dio,
        url,
        file,
        cancelToken: cancelToken,
        onProgress: onProgress,
        expectedSize: expectedSize,
        stallTimeout: stallTimeout,
      );
      return;
    } catch (e) {
      final cancelError = cancelToken?.cancelError;
      if (cancelError != null) {
        throw cancelError;
      }
      if (e is DioException && CancelToken.isCancel(e)) {
        rethrow;
      }
      if (!_isRetryable(e) || attempt >= maxAttempts) {
        rethrow;
      }
    }
    onRetry?.call(attempt);
    await Future.delayed(
        retryDelay?.call(attempt) ?? Duration(seconds: 2 * attempt));
    final cancelError = cancelToken?.cancelError;
    if (cancelError != null) {
      throw cancelError;
    }
  }
}

bool _isRetryable(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    // 4xx 代表网址本身有问题（416 除外，已在下载前处理），重试也没用
    return status == null || status >= 500 || status == 416;
  }
  return e is TimeoutException ||
      e is HttpException ||
      e is SocketException ||
      e is TlsException ||
      e is _IncompleteDownload;
}

class _IncompleteDownload implements Exception {
  const _IncompleteDownload(this.received, this.total);
  final int received;
  final int total;

  @override
  String toString() => 'download ended at $received of $total bytes';
}

Future<void> _downloadOnce(
  Dio dio,
  String url,
  File file, {
  required CancelToken? cancelToken,
  required void Function(int received, int total)? onProgress,
  required int expectedSize,
  required Duration stallTimeout,
}) async {
  var offset = await file.exists() ? await file.length() : 0;
  if (expectedSize > 0 && offset > expectedSize) {
    // 残留的档案比完整档还大，不可能接得上
    await file.delete();
    offset = 0;
  }
  if (expectedSize > 0 && offset == expectedSize) {
    onProgress?.call(offset, expectedSize);
    return;
  }

  Response<ResponseBody> response;
  try {
    response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: stallTimeout,
        headers: {
          if (offset > 0) HttpHeaders.rangeHeader: 'bytes=$offset-',
        },
      ),
    );
  } on DioException catch (e) {
    if (e.response?.statusCode == 416 && await file.exists()) {
      // 伺服器上的档案变了，已下载的部分作废
      await file.delete();
    }
    rethrow;
  }

  final resumed = offset > 0 && response.statusCode == 206;
  if (!resumed) {
    // 伺服器传回整个档案，从头写起
    offset = 0;
  }
  final length = int.tryParse(
          response.headers.value(HttpHeaders.contentLengthHeader) ?? '') ??
      -1;
  final total =
      expectedSize > 0 ? expectedSize : (length >= 0 ? offset + length : -1);

  final sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
  var received = offset;
  try {
    await for (final chunk in response.data!.stream.timeout(stallTimeout)) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
  } finally {
    await sink.close();
  }
  if (total >= 0 && received != total) {
    throw _IncompleteDownload(received, total);
  }
}
