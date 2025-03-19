import 'package:server_testing/server_testing.dart';
// import 'package:test/test.dart';

// import 'components/nav_menu.dart';
// import 'pages/login_page.dart';

void main() async {
  final config = BrowserConfig(
      browserName: 'firefox',
      baseUrl: 'https://wikipedia.org',
      debug: true,
      forceReinstall: false,
      logDir: 'test/logs',
      verbose: true,
      headless: false,
      timeout: const Duration(seconds: 30),
      capabilities: {
        // Firefox-specific options go under the "moz:firefoxOptions" key.
        // Pass any command-line arguments for Firefox.
        // You can set window size via arguments, but it's often easier to adjust later.
        'prefs': {
          // Override the user agent.
          'general.useragent.override':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.7049.17 Safari/537.36',
          // Emulate HiDPI by setting the device scale factor to 2.
          'layout.css.devPixelsPerPx': '2',
          // 'layout.css.dpi': '240',
        },
        'args': ['--width=412', '--height=883'],
      });
  await testBootstrap(
    config,
  );
  // Single test example
  await browserTest('guest can view the homepage', (browser) async {
    await browser.visit('/');

    await browser.assertSee('Bahasa');
    await browser.assertTitle('Wikipedia');
    await browser.waiter.wait(Duration(seconds: 3));
  }, useAsync: true, config: config);
}
