import 'package:server_testing/server_testing.dart';

void main() async {
  await testBootstrap(
    BrowserConfig(
      browserName: 'chromium',
      headless: false,
      baseUrl: 'https://example.com',
      autoScreenshots: false,
    ),
  );

  browserTest('chromium can launch and load example.com', (browser) async {
    await browser.visit('/');
    await browser.assertTitle('Example Domain');
    await browser.waiter.wait(const Duration(seconds: 4));
  }, browserType: ChromiumType());
}
