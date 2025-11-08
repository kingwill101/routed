import 'package:server_testing/src/browser/bootstrap/browser_paths.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserPaths.getDownloadUrls', () {
    test('falls back from ubuntu24.04 to ubuntu22.04', () {
      final urls = BrowserPaths.getDownloadUrls(
        'chromium',
        '123',
        platformOverride: 'ubuntu24.04-x64',
      );

      expect(urls, isNotEmpty);
      expect(urls.first, contains('builds/chromium/123/chromium-linux.zip'));
    });

    test('falls back for future ubuntu release when no direct match', () {
      final urls = BrowserPaths.getDownloadUrls(
        'chromium',
        '123',
        platformOverride: 'ubuntu26.04-x64',
      );

      expect(urls, isNotEmpty);
      expect(urls.first, contains('builds/chromium/123/chromium-linux.zip'));
    });

    test('strips architecture suffix for mac downloads when necessary', () {
      final urls = BrowserPaths.getDownloadUrls(
        'chromium',
        '123',
        platformOverride: 'mac14-x64',
      );

      expect(urls, isNotEmpty);
      expect(urls.first, contains('builds/chromium/123/chromium-mac.zip'));
    });

    test('returns empty list for unknown browsers', () {
      final urls = BrowserPaths.getDownloadUrls(
        'unknown',
        '123',
        platformOverride: 'ubuntu24.04-x64',
      );

      expect(urls, isEmpty);
    });
  });
}
