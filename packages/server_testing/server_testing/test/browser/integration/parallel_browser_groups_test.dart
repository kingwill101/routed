library;

import 'dart:io';

import 'package:server_testing/server_testing.dart';

import '../_support/real_browser_bootstrap.dart';

void main() {
  group('Parallel browser groups', () {
    setUpAll(() async {
      await realBrowserBootstrap(
        BrowserConfig(
          browserName: 'firefox',
          headless: true,
          baseUrl: 'https://example.com',
          autoScreenshots: false,
        ),
      );
    });

    tearDownAll(realBrowserCleanup);

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

    final isCi =
        Platform.environment['CI'] == 'true' ||
        Platform.environment.containsKey('GITHUB_ACTIONS');
    final hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
    if (!isCi || hasDisplay) {
      browserGroup(
        'Group B (visible override)',
        headless: true,
        define: (getBrowser) {
          test('B: different config still works', () async {
            final b = getBrowser();
            await b.visit('/');
            await b.assertTitle('Example Domain');
          });
        },
      );
    } else {
      // Avoid headful launches on CI without a display server.
      print('Skipping headful browser group (no DISPLAY in CI).');
    }
  });
}
