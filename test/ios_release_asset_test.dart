import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/requests/common_request.dart';

void main() {
  test(
    'iOS update chooses IPA when Android and Windows assets are also present',
    () {
      final release = CommonRequest.parseRelease(
        {
          'tag_name': 'v2.4.1',
          'html_url': 'https://github.com/example/zai/releases/tag/v2.4.1',
          'assets': [
            {
              'name': 'app.apk',
              'browser_download_url': 'https://example.com/app.apk',
            },
            {
              'name': 'app.zip',
              'browser_download_url': 'https://example.com/app.zip',
            },
            {
              'name': 'ZAI-X-iOS-2.4.1-unsigned.ipa',
              'browser_download_url': 'https://example.com/app.ipa',
              'digest': 'sha256:abcd',
              'size': 12345,
            },
          ],
        },
        android: false,
        windows: false,
        ios: true,
      );
      expect(release.downloadUrl, 'https://example.com/app.ipa');
      expect(release.sha256, 'abcd');
      expect(release.size, 12345);
    },
  );
}
