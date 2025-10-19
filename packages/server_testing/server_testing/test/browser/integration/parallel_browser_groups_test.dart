import 'package:server_testing/server_testing.dart';

void main() async {
  await testBootstrap(
    BrowserConfig(
      browserName: 'firefox',
      headless: true,
      baseUrl: 'https://example.com',
      autoScreenshots: false,
    ),
  );

  // Two groups with different overrides should not cross-talk
  browserGroup(
    'Group A (headless)',
    headless: true,
    define: (getBrowser) {
      test('A: title check', () async {
        final b = getBrowser();
        await b.visit('/');
        await b.assertTitle('Example Domain');
      });
    },
  );

  browserGroup(
    'Group B (visible override)',
    headless: false,
    define: (getBrowser) {
      test('B: different config still works', () async {
        final b = getBrowser();
        await b.visit('/');
        await b.assertTitle('Example Domain');
      });
    },
  );
}
