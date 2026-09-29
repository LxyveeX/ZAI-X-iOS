const githubProxyPrefix = 'https://gh-proxy.com/';

/// GitHub 更新资源优先走加速代理；其他服务的网址保持原样。
String githubProxyUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !const {
        'github.com',
        'api.github.com',
        'raw.githubusercontent.com',
      }.contains(uri.host)) {
    return url;
  }
  return '$githubProxyPrefix$url';
}

/// 加速代理连不上时，接着尝试 GitHub 原站。
List<String> githubSources(String url) {
  final accelerated = githubProxyUrl(url);
  return accelerated == url ? [url] : [accelerated, url];
}
