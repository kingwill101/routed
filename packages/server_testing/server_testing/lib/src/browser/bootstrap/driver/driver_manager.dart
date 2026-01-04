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
  static Future<int> ensureDriver(
    String browser, {
    bool force = false,
    int? driverMajor,
    String? driverExact,
  }) async {
    final driver = _getDriver(browser);
    final targetDir = path.join(BrowserPaths.getRegistryDirectory(), 'drivers');

    print('Ensuring driver directory exists: $targetDir');
    await Directory(targetDir).create(recursive: true);

    // Resolve expected driver binary name via manager implementation
    final bin = driver.driverBinaryName();
    final existing = File(path.join(targetDir, bin));

    // Serialize setup per driver to avoid concurrent downloads
    final lockFile = File(path.join(targetDir, 'setup_$bin.lock'));
    RandomAccessFile? raf;
    try {
      raf = lockFile.openSync(mode: FileMode.write);
      raf.lockSync(FileLock.exclusive);

      final exists = await existing.exists();
      if (!force && exists) {
        final needsUpdate = await _driverNeedsUpdate(
          browser,
          existing,
          driverMajor: driverMajor,
          driverExact: driverExact,
        );
        if (needsUpdate) {
          force = true;
          print('Driver version mismatch detected, forcing reinstall.');
        } else {
          print('$bin already present at: ${existing.path}');
        }
      }

      if (!force && exists) {
        // no-op, driver already present and matches requested version
      } else {
        if (force && await existing.exists()) {
          print(
            'Force reinstall requested: deleting existing driver at ${existing.path}',
          );
          try {
            await existing.delete();
          } catch (_) {}
        }
        print('Setting up driver...');
        await driver.setup(
          targetDir,
          major: driverMajor,
          exactVersion: driverExact,
        );
      }
    } finally {
      try {
        raf?.unlockSync();
        raf?.closeSync();
      } catch (_) {}
    }

    final driverPort = await _findAvailablePort();

    print('Starting driver:');
    print("$browser on port $driverPort");
    await driver.start(driverPort);
    _activePorts[browser] = driverPort;
    return driverPort;
  }

  /// Stops all active WebDriver server processes managed by this [DriverManager].
  ///
  /// Iterates through the registered drivers and calls their `stop` method.
  /// Clears the record of active ports.
  static Future<void> stopAll() async {
    for (final entry in _drivers.entries) {
      final browser = entry.key;
      final driver = entry.value;
      final port = _activePorts[browser];
      await driver.stop();
      if (port != null) {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (DateTime.now().isBefore(deadline)) {
          final running = await driver.isRunning(port);
          if (!running) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
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
    final driver = _drivers[browser];
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

  static Future<int> _findAvailablePort() async {
    ServerSocket? socket;
    int port = 0;

    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = socket.port;
    } finally {
      await socket?.close();
    }

    return port;
  }

  static Future<bool> _driverNeedsUpdate(
    String browser,
    File existing, {
    int? driverMajor,
    String? driverExact,
  }) async {
    if (browser != 'chrome') return false;
    if (driverMajor == null && driverExact == null) return false;

    final output = await _readDriverVersion(existing.path);
    if (output == null) return true;

    final currentFull = _extractFullVersion(output);
    final currentMajor = _extractMajorVersion(output);

    if (driverExact != null && driverExact.isNotEmpty) {
      if (currentFull == null) return true;
      return currentFull != driverExact;
    }

    if (driverMajor != null) {
      if (currentMajor == null) return true;
      return currentMajor != driverMajor;
    }

    return false;
  }

  static Future<String?> _readDriverVersion(String path) async {
    try {
      final result = await Process.run(path, ['--version']);
      if (result.exitCode != 0) return null;
      return result.stdout.toString().trim();
    } catch (_) {
      return null;
    }
  }

  static String? _extractFullVersion(String output) {
    final match = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(output);
    return match?.group(1);
  }

  static int? _extractMajorVersion(String output) {
    final match = RegExp(r'(\d+)\.').firstMatch(output);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }
}
