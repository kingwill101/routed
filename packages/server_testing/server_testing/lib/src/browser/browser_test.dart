import 'package:meta/meta.dart';
import 'package:server_testing/src/browser/bootstrap/device_json.dart';
import 'package:server_testing/src/browser/interfaces/browser_type.dart';
import 'package:test/test.dart';

import '../../browser.dart';
import 'bootstrap/driver/driver_manager.dart';

/// Defines an individual browser test case using the `package:test` framework.
///
/// Creates an isolated browser test with automatic setup and teardown.
///
/// Sets up a test with a browser instance launched according to the provided
/// configuration overrides or global defaults. After the test completes,
/// the browser is automatically closed.
///
/// ```dart
/// void main() async {
///   // Configure default settings (e.g., default browser, headless mode)
///   await testBootstrap(BrowserConfig(browserName: 'chromium', headless: true));
///
///   // Simple test using defaults
///   browserTest('user can log in', (browser) async {
///     await browser.visit('/login');
///     // ... assertions ...
///   });
///
///   // Test overriding the browser type and headless mode
///   browserTest('run firefox visibly', (browser) async {
///      await browser.visit('/');
///     // ... assertions ...
///   }, browserType: firefox, headless: false);
/// }
/// ```
///
/// The [description] identifies the test in output.
/// The [callback] receives the configured browser instance.
/// Optional parameters like [browserType], [headless], [baseUrl], [timeout],
/// [device], etc., allow overriding the global configuration set by
/// [testBootstrap] specifically for this test.
/// The [useAsync] flag determines whether to use async or sync WebDriver API.
@isTest
Future<void> browserTest(
  String description,
  Future<void> Function(Browser browser) callback, {
  BrowserType? browserType,
  bool? headless,
  List<String>? args,
  String? baseUrl,
  Duration? timeout, // Operation timeout for BrowserConfig
  Duration? launchTimeout, // Timeout for the launch itself
  Map<String, dynamic>? extraCapabilities, // Use core.Map prefix
  ProxyConfiguration? proxy,
  Device? device,
  bool useAsync = true,
}) async {
  tearDown(() async {
    print("Tearing down browser test: $description");
    await DriverManager.stopAll();
  });
  test(description, () async {
    bool configOverridden = false;
    // Apply configuration overrides for this test if provided
    // Check if *any* override relevant to config needs pushing
    if (browserType != null ||
        headless != null ||
        baseUrl != null ||
        timeout != null ||
        proxy != null) {
      TestBootstrap.pushConfigOverride(
        // Pass browserName only if browserType is also explicitly provided
        browserName: browserType?.name,
        headless: headless,
        baseUrl: baseUrl,
        timeout: timeout,
        // This sets the default operation timeout
        proxy: proxy,
      );
      configOverridden = true;
    }

    try {
      // Ensure no stale WebDriver servers remain from prior tests
      await DriverManager.stopAll();
      // Use the potentially overridden currentConfig for launch decisions
      final config = TestBootstrap.currentConfig;
      // Determine BrowserType based on explicit param or potentially overridden config
      final type =
          browserType ?? TestBootstrap.browserTypes[config.browserName];
      if (type == null) {
        throw ArgumentError(
          'Could not find BrowserType for ${config.browserName}. Ensure testBootstrap is configured correctly and the browser name is supported.',
        );
      }

      // Create Launch Options: These are specific instructions for *this* launch,
      // potentially differing from the overridden `currentConfig` (e.g., args).
      final launchOptions = BrowserLaunchOptions(
        // Use the explicitly passed headless value for launch,
        // falling back to the *effective* current config's headless value
        headless: headless ?? config.headless,
        args: args,
        // Base URL for the browser instance comes from effective config,
        // but BrowserLaunchOptions could override if needed.
        baseUrl: config.baseUrl,
        timeout: launchTimeout,
        // Specific timeout for the launch process
        extraCapabilities: extraCapabilities,
        // Proxy for the browser instance comes from effective config
        proxy: config.proxy,
        device: device, // Pass the device parameter for emulation
        // channel, executablePath, env, slowMo could be added here if needed
      );

      // Launch the browser using the determined type and options
      // BrowserType.launch now handles creating the final BrowserConfig for runtime
      // and selects async/sync implementation based on useAsync
      final browser = await type.launch(launchOptions, useAsync: useAsync);

      // The launched 'browser' instance now contains a BrowserConfig reflecting
      // the state after launch (including overrides applied via pushConfigOverride).

      try {
        await callback(browser);
      } finally {
        // Browser interface uses FutureOr, so 'await' works for both sync/async quit
        await browser.quit();
      }
    } finally {
      // Always restore the original configuration if we pushed an override
      if (configOverridden) {
        TestBootstrap.popConfigOverride();
      }
    }
  });
}

/// Defines a group of related browser test cases that share a single browser instance.
///
/// Creates a group of browser tests that share a single browser instance.
///
/// Launches a browser once before all tests in the group run (`setUpAll`), configured
/// according to the provided overrides or global defaults. The shared browser is
/// automatically closed after all tests in the group complete (`tearDownAll`).
///
/// ```dart
/// void main() async {
///   await testBootstrap(BrowserConfig(baseUrl: 'http://localhost:8080'));
///
///   // Group uses default browser from bootstrap
///   browserGroup('user authentication', define: (browser) {
///     test('can log in', () async { /* ... use browser ... */ });
///     test('can log out', () async { /* ... use browser ... */ });
///   });
///
///   // Group explicitly uses chromium, overriding the default
///    browserGroup('admin tests', browserType: chromium, define: (browser) {
///      // ... admin tests using chromium ...
///   });
/// }
/// ```
///
/// The [description] identifies the test group in output.
/// The [define] function receives the shared browser instance for defining tests.
/// Optional parameters like [browserType], [headless], [baseUrl], [timeout],
/// [device], etc., allow overriding the global configuration set by
/// [testBootstrap] specifically for this group.
/// The [useAsync] flag determines whether to use async or sync WebDriver API for the shared instance.
@isTestGroup
void browserGroup(
  String description, {
  required void Function(Browser Function() browser) define,
  BrowserType? browserType,
  bool? headless,
  List<String>? args,
  String? baseUrl,
  Duration? timeout, // Operation timeout override for the group's config
  Duration? launchTimeout, // Timeout for the group's browser launch itself
  Map<String, dynamic>? extraCapabilities, // Use core.Map prefix
  ProxyConfiguration? proxy,
  bool useAsync = true,
  Device? device,
}) {
  group(description, () {
    Browser? browser;
    bool configOverridden =
        false; // Track if override was pushed for this group

    setUpAll(() async {
      // Apply configuration overrides for this group if provided
      // Check if *any* override relevant to config needs pushing
      if (browserType != null ||
          headless != null ||
          baseUrl != null ||
          timeout != null ||
          proxy != null) {
        TestBootstrap.pushConfigOverride(
          // Pass browserName only if browserType is also explicitly provided
          browserName: browserType?.name,
          headless: headless,
          baseUrl: baseUrl,
          timeout: timeout,
          // This sets the default operation timeout
          proxy: proxy,
        );
        configOverridden = true;
      }

      // Get the potentially overridden current config for launch decisions
      final config = TestBootstrap.currentConfig;

      // Determine BrowserType based on explicit param or potentially overridden config
      final type =
          browserType ?? TestBootstrap.browserTypes[config.browserName];
      if (type == null) {
        // Clean up config stack if setup fails prematurely
        if (configOverridden) TestBootstrap.popConfigOverride();
        throw ArgumentError(
          'Could not find BrowserType for ${config.browserName}. Ensure testBootstrap is configured correctly and the browser name is supported.',
        );
      }

      // Create Launch Options using the current (possibly overridden) configuration
      final launchOptions = BrowserLaunchOptions(
        headless: config.headless,
        // Use config value (reflects override)
        args: args,
        // Args are specific to this launch, not from config stack
        baseUrl: config.baseUrl,
        // Use config value (reflects override)
        timeout: launchTimeout,
        // Specific timeout for the launch process
        extraCapabilities: extraCapabilities,
        // Specific to this launch
        proxy: config.proxy,
        // Use config value (reflects override)
        device: device, // Specific to this launch
      );

      // Launch the browser once for the group
      try {
        browser = await type.launch(launchOptions, useAsync: useAsync);
      } catch (e) {
        // Clean up config stack if launch fails
        if (configOverridden) TestBootstrap.popConfigOverride();
        rethrow;
      }

      // Note: The 'timeout' parameter (if provided) has already modified
      // `TestBootstrap.currentConfig`. The `browser` instance created by `type.launch`
      // will receive a `BrowserConfig` reflecting this potentially overridden timeout.
      if (timeout != null) {
        print("Group will use overridden operation timeout: $timeout");
      }
    });

    tearDownAll(() async {
      // Quit the shared browser first
      try {
        if (browser != null) {
          await browser!.quit();
        }
      } finally {
        // Always restore the original configuration if we pushed an override
        if (configOverridden) {
          TestBootstrap.popConfigOverride();
        }
      }
    });

    // Define the tests using the shared browser instance lazily via accessor
    if (browser != null) {
      define(() => browser!);
    }
  });
}
