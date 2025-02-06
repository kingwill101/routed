import 'package:routed_testing/routed_testing.dart';
// import 'package:test/test.dart';

// import 'components/nav_menu.dart';
// import 'pages/login_page.dart';

void main() async {
  await testBootstrap(
    TestBootstrapConfig(
      browser: 'firefox',
      baseUrl: 'https://wikipedia.org',
      debug: true,
      forceReinstall: false,
      logDir: 'test/logs',
      verboseLogs: true,
    ),
  );
  // Single test example
  await browserTest('guest can view the homepage', (browser) async {
    await browser.visit('/');

    await browser.assertSee('Bahasa');
    await browser.assertTitle('Wikwsssipedia');

  },useAsync: false);
}
