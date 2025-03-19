import 'package:path/path.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:webdriver/async_io.dart' as wdasync;
import 'package:webdriver/sync_io.dart' as sync;

import 'bootstrap/registry.dart';
import 'browser_exception.dart';

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

main() {}
