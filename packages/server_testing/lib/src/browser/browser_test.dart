import 'package:path/path.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:webdriver/async_io.dart' as wdasync;
import 'package:webdriver/sync_io.dart' as sync;

import 'bootstrap/registry.dart';
import 'browser_exception.dart';

/// Creates a browser test.
///
/// This function sets up an isolated test with a browser instance. The browser
/// is launched with the provided configuration (or falls back to the global config
/// from [testBootstrap]), then passed to the test callback. After the test completes,
/// the browser is automatically closed.
///
/// [description] is the name of the test.
/// [callback] is the test function that receives the browser instance.
/// [config] is an optional configuration for this specific browser test.
/// [useAsync] determines whether to use the async or sync WebDriver API.
///
/// Example:
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

/// Creates a group of browser tests that share a browser instance.
///
/// This function sets up a test group where all tests share the same browser instance.
/// The browser is launched once at the beginning of the group and closed after all
/// tests in the group have completed. This is more efficient than creating a new
/// browser for each test.
///
/// [description] is the name of the test group.
/// [define] is a function that defines the tests in the group.
/// [config] is an optional configuration for the browser.
/// [useAsync] determines whether to use the async or sync WebDriver API.
///
/// Example:
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

/// Gets the WebDriver server URL for the specified browser.
///
/// Different browsers use different URL paths for their WebDriver servers.
Uri _getDriverUrl(String browser, int port) {
  if (browser == 'firefox') {
    return Uri.parse('http://localhost:$port');
  }
  return Uri.parse('http://localhost:$port/wd/hub');
}

/// Maps browser names to their WebDriver capability names.
String _getBrowserName(String browser) {
  final browserMap = {
    'chrome': 'chrome',
    'chromium': 'chrome',
    'firefox': 'firefox',
  };
  return browserMap[browser.toLowerCase()] ?? browser;
}

/// Launches a browser with the specified configuration.
///
/// This function sets up and launches a browser instance using WebDriver.
/// It handles browser installation, driver setup, and browser configuration.
///
/// [config] is the browser configuration.
/// [useAsync] determines whether to use the async or sync WebDriver API.
///
/// Returns a [Browser] instance.
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

/// Quits any existing WebDriver session.
///
/// This prevents conflicts with previous test runs that might not have
/// cleaned up properly.
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
