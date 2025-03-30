import 'package:path/path.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:webdriver/async_io.dart' as wdasync;
import 'package:webdriver/sync_io.dart' as sync;

import 'bootstrap/registry.dart';
import 'browser_exception.dart';

/// Defines an individual browser test case using the `package:test` framework.
///
/// Creates an isolated browser test with automatic setup and teardown.
///
/// Sets up a test with a browser instance launched according to the provided
/// configuration. After the test completes, the browser is automatically closed.
///
/// ```dart
/// void main() async {
///   await testBootstrap();
///
///   browserTest('user can log in', (browser) async {
///     await browser.visit('/login');
///     await browser.type('input[name="email"]', 'user@example.com');
///     await browser.type('input[name="password"]', 'password');
///     await browser.click('button[type="submit"]');
///     await browser.assertSee('Welcome back');
///   });
/// }
/// ```
///
/// The [description] identifies the test in output.
/// The [callback] receives the configured browser instance.
/// The [config] overrides default browser settings when provided.
/// The [useAsync] flag determines whether to use async or sync WebDriver API.
///
/// This function simplifies writing browser tests by:
/// 1.  Registering a test case with the given [description] using `test()`.
/// 2.  Launching a new browser instance before the test runs, configured according
///     to the optional [config] or the global configuration set by [testBootstrap].
/// 3.  Providing the launched [Browser] instance to the asynchronous [callback]
///     function where the test logic resides.
/// 4.  Automatically quitting the browser instance after the [callback] completes,
///     whether it passes or fails.
///
/// It assumes that [testBootstrap] has been called previously to set up the
/// overall testing environment.
///
/// ### Usage
///
/// ```dart
/// void main() async {
///   await testBootstrap(); // Ensure environment is set up
///
///   browserTest('User login succeeds with valid credentials', (browser) async {
///     await browser.visit('/login');
///     await browser.type('#email', 'test@example.com');
///     await browser.type('#password', 'secret');
///     await browser.click('button[type=submit]');
///     await browser.assertPathIs('/dashboard');
///     await browser.assertSee('Welcome, Test User!');
///   });
/// }
/// ```
///
/// Use [useAsync] to choose between the asynchronous (`true`, default) or
/// synchronous (`false`) [Browser] implementation. The choice must match the
/// expectation within the [callback].
Future<void> browserTest(
  String description,
  Future<void> Function(Browser browser) callback, {
  BrowserConfig? config,
  bool useAsync = true,
}) async {
  // Get the global config from bootstrap
  final globalConfig = TestBootstrap.currentConfig;

  test(description, () async {
    final browser = await launchBrowser(
        config ??
            BrowserConfig(
              browserName: globalConfig.browserName,
              headless: true,
              baseUrl: globalConfig.baseUrl,
            ),
        useAsync);

    try {
      await callback(browser);
    } finally {
      if (useAsync) {
        await (browser).quit();
      } else {
        browser.quit();
      }
    }
  });
}

/// Defines a group of related browser test cases that share a single browser instance.
///
/// Creates a group of browser tests that share a single browser instance.
///
/// Launches a browser once for all tests in the group, improving test
/// efficiency. The browser automatically closes after all tests complete.
///
/// ```dart
/// void main() async {
///   await testBootstrap();
///
///   browserGroup('user authentication', define: (browser) {
///     test('can log in', () async {
///       await browser.visit('/login');
///       await browser.type('input[name="email"]', 'user@example.com');
///       await browser.type('input[name="password"]', 'password');
///       await browser.click('button[type="submit"]');
///       await browser.assertSee('Welcome back');
///     });
///
///     test('can log out', () async {
///       await browser.click('.logout-button');
///       await browser.assertSee('You have been logged out');
///     });
///   });
/// }
/// ```
///
/// The [description] identifies the test group in output.
/// The [define] function receives the browser instance for defining tests.
/// The [config] overrides default browser settings when provided.
/// The [useAsync] flag determines whether to use async or sync WebDriver API.
///
/// This function uses the `package:test` framework's `group()` function to
/// organize tests. It enhances the standard grouping by:
/// 1.  Launching a single browser instance before any test in the group runs (`setUp`).
/// 2.  Providing this shared [Browser] instance to the [define] function.
/// 3.  Allowing multiple `test()` or `browserTest()` calls within the [define] function
///     to reuse the same browser session, improving efficiency.
/// 4.  Automatically quitting the shared browser instance after all tests in the
///     group have completed (`tearDown`).
///
/// It assumes that [testBootstrap] has been called previously. The optional
/// [config] allows overriding the global configuration for this specific group.
/// Use [useAsync] to choose the browser implementation type.
///
/// ### Usage
///
/// ```dart
/// void main() async {
///   await testBootstrap();
///
///   browserGroup('Shopping Cart Interactions', define: (browser) {
///     // Test 1 uses the shared browser
///     test('Adding an item increases cart count', () async {
///       await browser.visit('/products/1');
///       await browser.click('.add-to-cart');
///       await browser.assertSeeIn('.cart-count', '1');
///     });
///
///     // Test 2 uses the same shared browser session
///     test('Removing an item decreases cart count', () async {
///       // Assumes item was added in a previous step or setUp
///       await browser.visit('/cart');
///       await browser.click('.remove-item');
///       await browser.assertSeeIn('.cart-count', '0');
///     });
///   });
/// }
/// ```
void browserGroup(
  String description, {
  required void Function(Browser browser) define,
  BrowserConfig? config,
  bool useAsync = true,
}) {
  group(description, () {
    late Browser browser;

    setUp(() async {
      browser = await launchBrowser(config, useAsync);
    });

    tearDown(() async {
      if (useAsync) {
        await browser.quit();
      } else {
        browser.quit();
      }
    });

    define(browser);
  });
}

/// Determines the correct WebDriver endpoint URI for the given [browser] name and [port].
///
/// Gets the WebDriver server URL for the specified browser.
///
/// Different browsers use different URL paths for their WebDriver servers.
///
/// Different WebDriver implementations (ChromeDriver, GeckoDriver) might use
/// different base paths. This function standardizes the URL creation.
/// Firefox (GeckoDriver) typically uses the root path, while ChromeDriver uses `/wd/hub`.
Uri _getDriverUrl(String browser, int port) {
  if (browser == 'firefox') {
    return Uri.parse('http://localhost:$port');
  }
  return Uri.parse('http://localhost:$port/wd/hub');
}

/// Maps common browser names (like 'chromium') to the name expected by WebDriver
/// in the capabilities map (like 'chrome').
/// Maps browser names to their WebDriver capability names.
///
/// Returns the normalized browser name suitable for WebDriver capabilities.
String _getBrowserName(String browser) {
  final browserMap = {
    'chrome': 'chrome',
    'chromium': 'chrome',
    'firefox': 'firefox',
  };
  return browserMap[browser.toLowerCase()] ?? browser;
}

/// Creates, configures, and launches a new browser instance using WebDriver.
///
/// Launches a browser with the specified configuration.
///
/// This function sets up and launches a browser instance using WebDriver.
/// It handles browser installation, driver setup, and browser configuration.
///
/// [config] is the browser configuration.
/// [useAsync] determines whether to use the async or sync WebDriver API.
///
/// Returns a [Browser] instance.
///
/// This is the core function responsible for initiating a browser session for testing.
/// It performs the following steps:
/// 1.  Ensures any potentially lingering WebDriver sessions from previous runs are closed
///     using [_quitExistingSession].
/// 2.  Initializes a [Registry] based on the loaded `browsers.json` and the requested
///     browser from the [config].
/// 3.  Retrieves the [Executable] information for the requested browser.
/// 4.  Ensures the browser is installed using [Registry.installExecutables].
/// 5.  Validates host requirements using [Registry.validateRequirements].
/// 6.  Constructs the WebDriver capabilities map, including browser-specific options
///     (like headless mode) based on the [config].
/// 7.  Creates the WebDriver instance (`async` or `sync` based on [useAsync]) by
///     connecting to the appropriate driver URL ([_getDriverUrl]).
/// 8.  Wraps the WebDriver instance in the corresponding [Browser] implementation
///     ([AsyncBrowser] or [SyncBrowser]) using [BrowserFactory].
///
/// The [config] object provides settings like browser name, headless mode, base URL, etc.
/// If [config] is null, a default [BrowserConfig] is used.
/// The [useAsync] flag determines which WebDriver API (and corresponding [Browser]
/// implementation) is used.
///
/// Returns the ready-to-use [Browser] instance. Throws [BrowserException] or other
/// exceptions if any step fails (e.g., browser not found, installation fails,
/// WebDriver connection fails).
Future<Browser> launchBrowser(BrowserConfig? config,
    [bool useAsync = true]) async {
  config ??= BrowserConfig();

  // First ensure any existing sessions are cleaned up
  await _quitExistingSession(config, useAsync);

  final registry = Registry(
    await BrowserJsonLoader.load(),
    requestedBrowser: config.browserName,
  );

  final executable = registry.getExecutable(config.browserName);

  if (executable == null) {
    throw BrowserException('Browser ${config.browserName} not found');
  }

  await registry.installExecutables(
    [executable],
    force: false,
  );

  await registry.validateRequirements(
    [executable],
    'dart',
  );

  // Launch browser instance
  final capabilities = {
    'browserName': _getBrowserName(config.browserName),
    if (_getBrowserName(config.browserName) == 'chrome')
      'goog:chromeOptions': {
        'args': [
          if (config.headless) '--headless',
        ]
      },
    if (_getBrowserName(config.browserName) == 'firefox')
      'moz:firefoxOptions': {
        'args': [
          if (config.headless) '--headless',
        ],
        "binary": join(executable.directory ?? "", executable.executablePath()),
        ...config.capabilities,
      },
  };

  Object driver;
  if (useAsync) {
    driver = await wdasync.createDriver(
      desired: capabilities,
      uri: _getDriverUrl(config.browserName, 4444),
    );
  } else {
    driver = sync.createDriver(
      desired: capabilities,
      uri: _getDriverUrl(config.browserName, 4444),
    );
  }

  if (useAsync) {
    return BrowserFactory.createAsync(
        driver as wdasync.WebDriver,
        BrowserConfig(
          browserName: config.browserName,
          baseUrl: config.baseUrl,
        ));
  } else {
    return BrowserFactory.createSync(
        driver as sync.WebDriver,
        BrowserConfig(
          browserName: config.browserName,
          baseUrl: config.baseUrl,
        ));
  }
}

/// Attempts to gracefully quit any existing WebDriver session that might be listening
/// on the target driver URL.
///
/// Quits any existing WebDriver session.
///
/// This prevents conflicts with previous test runs that might not have
/// cleaned up properly.
///
/// This is a cleanup measure to prevent issues caused by improperly terminated
/// previous test runs. It tries to create a new driver session pointed at the
/// expected URL and immediately quits it. Errors (e.g., if no server is running)
/// are ignored.
///
/// Uses the appropriate WebDriver API ([useAsync] flag) based on the context.
Future<void> _quitExistingSession(BrowserConfig config,
    [bool useAsync = true]) async {
  try {
    if (useAsync) {
      final existingDriver = await wdasync.createDriver(
        uri: _getDriverUrl(config.browserName, 4444),
      );
      await existingDriver.quit();
    } else {
      final existingDriver = sync.createDriver(
        uri: _getDriverUrl(config.browserName, 4444),
      );
      existingDriver.quit();
    }
  } catch (_) {
    // Ignore errors from no existing session
  }
}
