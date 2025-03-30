import 'dart:io';

import 'package:path/path.dart' as path;

import '../browser_paths.dart';
import 'chrome_driver_manager.dart';
import 'driver_interface.dart';
import 'gecko_driver_manager.dart';

/// Manages instances of different [WebDriverManager] implementations,
/// providing a central point for ensuring drivers are set up and running.
class DriverManager {
  /// A map storing registered [WebDriverManager] instances, keyed by browser name.
  static final Map<String, WebDriverManager> _drivers = {
    'chrome': ChromeDriverManager(),
    'firefox': GeckoDriverManager(),
  };

  /// Tracks the ports currently used by active driver processes managed by this class.
  static final Map<String, int> _activePorts = {};

  /// Ensures that the WebDriver for the specified [browser] is set up and running
  /// on the given [port].
  ///
  /// Retrieves the appropriate [WebDriverManager], ensures the driver
  /// directory exists, calls the manager's `setup` method, and then starts
  /// the driver process using the manager's `start` method. Tracks the active port.
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

  /// Stops all active WebDriver server processes managed by this [DriverManager].
  ///
  /// Iterates through the registered drivers and calls their `stop` method.
  /// Clears the record of active ports.
  static Future<void> stopAll() async {
    for (final entry in _drivers.entries) {
      await entry.value.stop();
    }
    _activePorts.clear();
  }

  /// Retrieves the appropriate [WebDriverManager] instance for the specified
  /// [browser] name (e.g., 'chrome', 'firefox').
  ///
  /// Handles mapping common names if necessary (e.g., 'chrome' maps to the
  /// 'chrome' manager). Throws an exception if no manager is registered for
  /// the given browser name.
  static WebDriverManager _getDriver(String browser) {
    // Map chrome to chromium if needed
    final driverName = browser == 'chrome' ? 'chrome' : browser;
    final driver = _drivers[driverName];
    if (driver == null) {
      throw Exception('No driver implementation for browser: $browser');
    }
    return driver;
  }

  /// Gets the port number currently used by the active driver process for the
  /// specified [browser], if one is running and managed by this manager.
  ///
  /// Returns `null` if no driver for the given [browser] is active.
  static int? getActivePort(String browser) => _activePorts[browser];
}
