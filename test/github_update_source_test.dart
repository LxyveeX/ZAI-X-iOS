import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/requests/common/github_proxy.dart';
import 'package:zai_x/requests/common_request.dart';

const _latest =
    'https://api.github.com/repos/funkeyyou/zaimanhua/releases/latest';
const _release = {
  'tag_name': 'v2.2.0',
  'body': '更新说明',
  'html_url': 'https://github.com/funkeyyou/zaimanhua/releases/tag/v2.2.0',
  'assets': [
    {
      'name': 'ZAI-X-android.apk',
      'browser_download_url':
          'https://github.com/funkeyyou/zaimanhua/releases/download/v2.2.0/app.apk',
      'digest': 'sha256:1234',
      'size': 100,
    },
    {
      'name': 'ZAI-X-windows-x64.zip',
      'browser_download_url':
          'https://github.com/funkeyyou/zaimanhua/releases/download/v2.2.0/app.zip',
      'digest': 'sha256:abcd',
      'size': 200,
    },
  ],
};

class _Sources implements HttpClientAdapter {
  _Sources({this.proxyStatus = 200, this.proxyData = _release});

  final int proxyStatus;
  final Object proxyData;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final proxy = options.uri.host == 'gh-proxy.com';
    return ResponseBody.fromString(
      jsonEncode(proxy ? proxyData : _release),
      proxy ? proxyStatus : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('latest release uses the proxy without contacting the original',
      () async {
    final sources = _Sources();
    final version = await CommonRequest(dio: Dio()..httpClientAdapter = sources)
        .checkUpdate();
    expect(version.version, '2.2.0');
    expect(sources.requests.single.uri.toString().split('?').first,
        '$githubProxyPrefix$_latest');
    expect(sources.requests.single.queryParameters, contains('ts'));
    expect(version.downloadUrl, startsWith('https://github.com/'));
  });

  for (final status in [403, 502]) {
    test('proxy HTTP $status falls back to the original release API', () async {
      final sources = _Sources(proxyStatus: status);
      final version =
          await CommonRequest(dio: Dio()..httpClientAdapter = sources)
              .checkUpdate();
      expect(version.version, '2.2.0');
      expect(
        sources.requests.map((r) => r.uri.toString().split('?').first),
        ['$githubProxyPrefix$_latest', _latest],
      );
    });
  }

  test('invalid proxy release data falls back to the original', () async {
    final sources = _Sources(proxyData: {'message': 'not available'});
    final version = await CommonRequest(dio: Dio()..httpClientAdapter = sources)
        .checkUpdate();
    expect(version.version, '2.2.0');
    expect(sources.requests.last.uri.toString().split('?').first, _latest);
  });

  test('proxy URLs stay intact and other services are not redirected', () {
    expect(githubSources('$githubProxyPrefix$_latest'),
        ['$githubProxyPrefix$_latest']);
    expect(githubSources('https://example.com/github.com/file.apk'),
        ['https://example.com/github.com/file.apk']);
    expect(githubSources('https://github.com.example.com/file.apk'),
        ['https://github.com.example.com/file.apk']);
  });
}
