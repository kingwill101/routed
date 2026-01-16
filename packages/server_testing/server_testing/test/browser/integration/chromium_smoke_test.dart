library;

import 'package:server_testing/server_testing.dart';

import '../_support/real_browser_bootstrap.dart';

void main() {
  group('Chromium smoke', () {
    setUpAll(() async {
      await realBrowserBootstrap(
        BrowserConfig(
          browserName: 'chromium',
          headless: true,
          baseUrl: 'https://example.com',
          autoScreenshots: false,
        ),
      );
    });

    tearDownAll(realBrowserCleanup);

    browserTest('chromium can launch and load example.com', (browser) async {
      await browser.visit('/');
      await browser.assertTitle('Example Domain');
      await browser.waiter.wait(const Duration(seconds: 4));
    }, browserType: ChromiumType());
  });
}
