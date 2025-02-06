import 'dart:io';

import 'package:path/path.dart' as path;

import 'browser_paths.dart';
import 'chrome_driver_manager.dart';
import 'driver_interface.dart';
import 'gecko_driver_manager.dart';

class DriverManager {
  static final Map<String, WebDriverManager> _drivers = {
    'chrome': ChromeDriverManager(),
    'firefox': GeckoDriverManager(),
  };

  static final Map<String, int> _activePorts = {};

  static Future<void> ensureDriver(String browser, {int port = 4444}) async {
    final driver = _getDriver(browser);
    final targetDir = path.join(BrowserPaths.getRegistryDirectory(), 'drivers');

    print('Ensuring driver directory exists: $targetDir');
    await Directory(targetDir).create(recursive: true);

    // Always run setup first
    print('Setting up driver...');
    await driver.setup(targetDir);

    print('Starting driver...');
    await driver.start(port: port);
    _activePorts[browser] = port;
  }

  static Future<void> stopAll() async {
    for (final entry in _drivers.entries) {
      await entry.value.stop();
    }
    _activePorts.clear();
  }

  static WebDriverManager _getDriver(String browser) {
    // Map chrome to chromium if needed
    final driverName = browser == 'chrome' ? 'chrome' : browser;
    final driver = _drivers[driverName];
    if (driver == null) {
      throw Exception('No driver implementation for browser: $browser');
    }
    return driver;
  }

  static int? getActivePort(String browser) => _activePorts[browser];
}
