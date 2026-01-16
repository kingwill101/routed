library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_testing/server_testing.dart';

import '../_support/real_browser_bootstrap.dart';

void main() {
  group('Screenshot integration', () {
    setUpAll(() async {
      // Use Firefox headless for consistency
      await realBrowserBootstrap(
        BrowserConfig(
          browserName: 'firefox',
          headless: true,
          baseUrl: 'https://example.com',
          // ensure screenshots go to the default test_screenshots directory
          autoScreenshots: false,
        ),
      );
    });

    tearDownAll(realBrowserCleanup);

    browserTest('captures real screenshots (default and custom name)', (
      browser,
    ) async {
      await browser.visit('/');

      // Ensure a decent viewport size then capture
      await browser.window.resize(1280, 800);

      // Default name
      await browser.takeScreenshot();

      // Custom name
      const custom = 'real-browser-homepage';
      await browser.takeScreenshot(custom);

      // Verify at least one PNG file exists in the screenshot directory
      final dir = Directory('test_screenshots');
      expect(await dir.exists(), isTrue);

      final pngs = await dir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
          .toList();

      expect(pngs.isNotEmpty, isTrue, reason: 'No PNG screenshots found');

      // Basic sanity for non-empty file
      final first = pngs.first as File;
      final bytes = await first.length();
      expect(bytes, greaterThan(50), reason: 'Screenshot file seems too small');
      final header = await first
          .openRead(0, 8)
          .fold<List<int>>(<int>[], (p, e) => p..addAll(e));
      expect(
        header,
        equals([137, 80, 78, 71, 13, 10, 26, 10]),
        reason: 'Not a PNG signature',
      );

      // Ensure custom-named file exists
      final match = await dir
          .list()
          .where((e) => e is File && p.basename(e.path).contains(custom))
          .toList();
      expect(
        match.isNotEmpty,
        isTrue,
        reason: 'Custom-named screenshot missing',
      );
    });
  });
}
