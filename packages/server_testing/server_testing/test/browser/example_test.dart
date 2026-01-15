@Tags(['real-browser'])
import 'package:server_testing/server_testing.dart';

import '_support/real_browser_bootstrap.dart';
import 'package:server_testing/src/browser/bootstrap/devices_json_const.dart';

// Import device definitions explicitly
// Example Page Object (Optional but good practice)
class ExamplePage extends Page {
  ExamplePage(super.browser) : super();

  // URL is relative to the baseUrl configured
  @override
  String get url => '/'; // Assuming example.com is the base

  // Elements
  String get heading => 'h1';

  // Actions
  Future<String> getHeadingText() async {
    final element = await browser.findElement(heading);
    return (await element.text) as String;
  }

  Future<void> assertOnExampleDomain() async {
    await browser.assertTitle('Example Domain');
    await browser.assertSeeIn(heading, 'Example Domain');
  }
}

void main() {
  final chromium = ChromiumType();

  group('Real browser examples', () {
    setUpAll(() async {
      await realBrowserBootstrap(
        BrowserConfig(
          browserName: 'firefox',
          // Default is now Firefox
          headless: true,
          baseUrl: 'https://example.com',
          // Default base URL for relative visits
          logDir: 'test_logs',
          // Customize log directory
          verbose: false, // Less verbose by default
        ),
      );
    });

    tearDownAll(realBrowserCleanup);

    // Test runs using the DEFAULTS from testBootstrap (Firefox, headless)
    // No need to specify browser type or options for the common case.
    browserTest(
      'Homepage title is correct (Default Browser)',
      (browser) async {
        await browser.visit('/');
        await browser.assertTitle('Example Domain');
      },
      // Run with global defaults (Firefox, headless) for stability in CI
      headless: true,
      timeout: const Duration(seconds: 60),
    );

    // Test runs using the DEFAULTS from testBootstrap (Firefox, headless)
    browserTest('Homepage heading is correct (Default Browser)', (
      browser,
    ) async {
      final page = ExamplePage(browser);
      await page.navigate(); // Uses baseUrl from config
      final heading = await page.getHeadingText();
      expect(heading, equals('Example Domain'));
    });

    // --- Overriding Defaults ---

    // Run a specific test in Chromium instead of the default Firefox.
    // Use the top-level 'chromium' instance.
    browserTest('Run specifically in Chromium', (browser) async {
      await browser.visit('/'); // Use baseUrl for stability in CI
      await browser.assertTitle('Example Domain');
    }, browserType: chromium);

    // Run a specific test visibly (overriding default headless: true).
    browserTest(
      'Run Firefox visibly',
      (browser) async {
        await browser.visit('/');
        await browser.assertTitle('Example Domain');
        await browser.waiter.wait(const Duration(seconds: 2)); // Pause to see
      },
      // No need for browserType: firefox (it's the default from bootstrap),
      // just override headless.
      headless: false,
    );

    // --- Device Emulation Test (REFINED) ---
    // Use Chromium for device emulation in CI-friendly runs.
    browserTest(
      'Emulate iPhone 13 (${chromium.name}) - Check User Agent',
      (browser) async {
        await browser.visit('/'); // Visit base URL (example.com)

        // Verify the user agent string set by the capabilities
        final userAgent = await browser.executeScript(
          'return navigator.userAgent;',
        );
        print('  [iPhone Test] Detected User Agent: $userAgent');
        expect(userAgent, equals(iphone13.userAgent));

        // Perform other checks relevant to mobile layout if desired
        await browser.assertSee('Example Domain'); // Basic check still works

        // Example: Check viewport size (might need slight adjustment for scrollbars etc.)
        final width = await browser.executeScript('return window.innerWidth;');
        final height = await browser.executeScript(
          'return window.innerHeight;',
        );
        print('  [iPhone Test] Detected Viewport: ${width}x$height');
        // Note: InnerWidth/Height might differ slightly from device viewport due to browser UI/scrollbars
        expect(
          width,
          closeTo(iphone13.viewport.width, 20),
        ); // Allow some tolerance
        // Height is often more variable due to toolbars etc.
        // expect(height, closeTo(iphone13.viewport.height, 50));
      },
      browserType: chromium,
      headless: false, // Often best to run visible for emulation tests
      // Simply pass the device object in launch options!
      device: iphone13,
    );

    // --- Grouping ---

    // This group uses the default browser (Firefox, headless)
    browserGroup(
      'Default browser group',
      define: (make) {
        final browser = make();
        test('Test A in group', () async {
          await browser.visit('/');
          await browser.assertSee('More information...');
        });
        test('Test B in group', () async {
          // Assumes browser is still at '/'
          await browser.assertSee('IANA');
        });
      },
      device: devicesJsonData['iPhone 13'],
    );

    // This group explicitly uses Chromium and runs visibly
    browserGroup(
      'Chromium visible group',
      browserType: chromium,
      headless: false,
      define: (make) {
        final browser = make();

        test('Test C in Chromium group', () async {
          await browser.visit('/');
          await browser.assertTitle('Example Domain');
        });
      },
    );

    // --- Sync Driver Usage (Still possible) ---
    browserTest(
      'Synchronous Test (uses default Firefox)',
      (browser) async {
        // Callback still marked async for compatibility with test runner
        // API calls inside are sync
        browser.visit('/');
        browser.assertTitle('Example Domain');
        print('  [Sync Test] Completed synchronous checks.');
      },
      useAsync: false, // Explicitly choose sync driver
    );
  }, tags: ['real-browser']);
}
