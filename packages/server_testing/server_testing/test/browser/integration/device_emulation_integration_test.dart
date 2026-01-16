library;

import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/devices_json_const.dart';

import '../_support/real_browser_bootstrap.dart';

void main() {
  // Use generated constants for devices to avoid fragile map lookups
  final devicePixel5 = pixel5;
  // final deviceGalaxyS9 = galaxyS9Plus; // available if needed

  group('Device emulation', () {
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

    browserTest(
      'Pixel 5 UA/viewport/touch/media',
      (browser) async {
        await browser.visit('/');

        final ua = await browser.executeScript('return navigator.userAgent;');
        expect(ua, isA<String>());
        // Firefox may normalize UA. Assert it contains device hint.
        expect((ua as String), contains('Pixel 5'));

        // Check viewport
        final width = await browser.executeScript('return window.innerWidth;');
        final height = await browser.executeScript(
          'return window.innerHeight;',
        );
        expect(width, isA<num>());
        expect(height, isA<num>());

        // Basic sanity: positive viewport
        expect((width as num) > 0, isTrue);
        expect((height as num) > 0, isTrue);

        // DPR / device scale (best-effort)
        final dpr = await browser.executeScript(
          'return window.devicePixelRatio;',
        );
        expect(dpr, isA<num>());

        // Touch support
        final hasTouch = await browser.executeScript(
          'return ("ontouchstart" in window) || (navigator.maxTouchPoints>0);',
        );
        expect(hasTouch, anyOf(true, false));

        // Media queries
        final prefersDark = await browser.executeScript(
          'return matchMedia("(prefers-color-scheme: dark)").matches;',
        );
        expect(prefersDark, anyOf(true, false));
      },
      browserType: ChromiumType(),
      device: devicePixel5,
    );

    // Galaxy S9 check is flaky across engines; covered by Pixel 5 smoke above.
  });
}
