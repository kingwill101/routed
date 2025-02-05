import 'package:path/path.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:routed_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:routed_testing/src/browser/bootstrap/browser_paths.dart';
import 'package:test/test.dart';
import 'package:webdriver/async_io.dart' show createDriver;
import 'bootstrap/registry.dart';
import 'browser_exception.dart';

Future<void> browserTest(
  String description,
  Future<void> Function(Browser browser) callback, {
  BrowserTestConfig? config,
}) async {
  // Get the global config from bootstrap
  final globalConfig = TestBootstrap.currentConfig;

  test(description, () async {
    final browser = await launchBrowser(
      config ??
          BrowserTestConfig(
            browser: globalConfig.browser,
            headless: true,
            baseUrl: globalConfig.baseUrl,
          ),
    );

    try {
      await callback(browser);
    } finally {
      await browser.driver.quit();
    }
  });
}

void browserGroup(
  String description, {
  required void Function(Browser browser) define,
  BrowserTestConfig? config,
}) {
  group(description, () {
    late Browser browser;

    setUp(() async {
      browser = await launchBrowser(config);
    });

    tearDown(() async {
      await browser.driver.quit();
    });

    define(browser);
  });
}

class BrowserTestConfig {
  final String browser;
  final bool headless;
  final String baseUrl;
  final Duration timeout;

  BrowserTestConfig({
    this.browser = 'chrome',
    this.headless = true,
    this.baseUrl = 'http://localhost:8000',
    this.timeout = const Duration(seconds: 30),
  });
}

Uri _getDriverUrl(String browser, int port) {
  if (browser == 'firefox') {
    return Uri.parse('http://localhost:$port');
  }
  return Uri.parse('http://localhost:$port/wd/hub');
}

String _getBrowserName(String browser) {
  final browserMap = {
    'chrome': 'chrome',
    'chromium': 'chrome',
    'firefox': 'firefox',
  };
  return browserMap[browser.toLowerCase()] ?? browser;
}

Future<Browser> launchBrowser(BrowserTestConfig? config) async {
  config ??= BrowserTestConfig();

  // First ensure any existing sessions are cleaned up
  try {
    final existingDriver = await createDriver(
      uri: _getDriverUrl(config.browser, 4444),
    );
    await existingDriver.quit();
  } catch (_) {
    // Ignore errors from no existing session
  }

  final registry = Registry(
    await BrowserJsonLoader.load(),
    requestedBrowser: config.browser,
  );

  final executable = registry.getExecutable(config.browser);

  if (executable == null) {
    throw BrowserException('Browser ${config.browser} not found');
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
    'browserName': _getBrowserName(config.browser),
    if (_getBrowserName(config.browser) == 'chrome')
      'goog:chromeOptions': {
        'args': config.headless ? ['--headless'] : []
      },
    if (_getBrowserName(config.browser) == 'firefox')
      'moz:firefoxOptions': {
        'args': config.headless ? ['-headless'] : [],
        "binary": join(executable.directory ?? "", executable.executablePath())
      }
  };

  final driver = await createDriver(
    desired: capabilities,
    uri: _getDriverUrl(config.browser, 4444),
  );

  return Browser(
      driver,
      BrowserConfig(
        browserName: config.browser,
        baseUrl: config.baseUrl,
      ));
}