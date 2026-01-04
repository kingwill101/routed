import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/bootstrap.dart';
import 'package:server_testing/src/browser/bootstrap/browser_json.dart';
import 'package:server_testing/src/browser/browser_exception.dart';
import 'package:server_testing/src/browser/logger.dart';

/// Browser management utilities for installing, updating, and listing browsers.
///
/// Provides functions to manage browser installations, including:
/// - Installing specific browser versions
/// - Updating browsers to latest versions
/// - Listing available browsers
/// - Getting browser version information
class BrowserManagement {
  static BrowserLogger? _logger;

  /// Gets or creates a logger instance with appropriate configuration.
  static BrowserLogger get logger {
    _logger ??= BrowserLogger(
      logDir: 'test/logs',
      verbose: false,
      enabled: BrowserLogger.defaultEnabled(),
    );
    return _logger!;
  }

  /// Sets a custom logger for browser management operations.
  static void setLogger(BrowserLogger customLogger) {
    _logger = customLogger;
  }

  /// Installs a specific browser version.
  ///
  /// [browserName] - The name of the browser to install (e.g., 'chromium', 'firefox')
  /// [version] - Optional specific version to install. If null, installs the default version
  /// [force] - Whether to force reinstallation even if already installed
  ///
  /// Returns true if installation was successful, false otherwise.
  ///
  /// Example:
  /// ```dart
  /// // Install default version of chromium
  /// await installBrowser('chromium');
  ///
  /// // Install specific version
  /// await installBrowser('firefox', version: '120.0');
  ///
  /// // Force reinstall
  /// await installBrowser('chromium', force: true);
  /// ```
  static Future<bool> installBrowser(
    String browserName, {
    String? version,
    bool force = false,
  }) async {
    final logContext =
        'installBrowser($browserName${version != null ? ', version: $version' : ''}, force: $force)';

    try {
      logger.info('$logContext: Starting installation...');

      // Validate input
      if (browserName.trim().isEmpty) {
        throw ArgumentError('Browser name cannot be empty');
      }

      // Ensure registry is initialized
      if (!_isRegistryInitialized()) {
        final error =
            'Browser registry not initialized. Call testBootstrap() first.';
        logger.error('$logContext: $error');
        throw BrowserException(error);
      }

      // Check for explicit binary override first and skip installation if present.
      final overridePath =
          TestBootstrap.getBinaryOverride(browserName) ??
          TestBootstrap.getBinaryOverride(
            _mapBrowserNameToRegistryName(browserName),
          );
      if (overridePath != null) {
        logger.info(
          '$logContext: Binary override configured at $overridePath, skipping installation.',
        );
        if (!File(overridePath).existsSync()) {
          throw BrowserException(
            'Configured override for "$browserName" points to a missing executable: $overridePath',
          );
        }
        return false;
      }

      // Map browser name to registry name
      final registryName = _mapBrowserNameToRegistryName(browserName);
      logger.info(
        '$logContext: Mapped "$browserName" to registry name "$registryName"',
      );

      // Get the executable from registry
      final executable = TestBootstrap.registry.getExecutable(registryName);
      if (executable == null) {
        final availableBrowsers = await _safeListAvailableBrowsers();
        final error =
            'Browser "$registryName" (mapped from "$browserName") not found in registry. '
            'Available browsers: $availableBrowsers';
        logger.error('$logContext: $error');
        throw BrowserException(error);
      }

      logger.info('$logContext: Found executable for ${executable.name}');

      final wasInstalled = _isBrowserInstalled(executable);

      // Check if already installed and not forcing
      if (!force && wasInstalled) {
        logger.info(
          '$logContext: Browser ${executable.name} is already installed, skipping',
        );
        return false; // Not newly installed
      }

      // Serialize installation per-browser to avoid concurrent clobbering
      final lockDir = Directory(
        path.join(Directory.systemTemp.path, 'st_browser_locks'),
      );
      if (!lockDir.existsSync()) lockDir.createSync(recursive: true);
      final lockFile = File(
        path.join(lockDir.path, 'install_${executable.name}.lock'),
      );
      final raf = lockFile.openSync(mode: FileMode.write);
      try {
        raf.lockSync(FileLock.exclusive);
        // Install the browser
        logger.info('$logContext: Installing ${executable.name}...');
        try {
          await TestBootstrap.registry.installExecutables([
            executable,
          ], force: force);
        } catch (e, stack) {
          if (force && wasInstalled && _isBrowserInstalled(executable)) {
            logger.error(
              '$logContext: Reinstall failed, keeping existing installation',
              error: e,
              stackTrace: stack,
            );
            return true;
          }
          rethrow;
        }

        // Validate installation
        logger.info('$logContext: Validating installation...');
        await TestBootstrap.registry.validateRequirements([executable], 'dart');
      } finally {
        try {
          raf.unlockSync();
          raf.closeSync();
        } catch (_) {}
      }

      // Double-check installation was successful
      if (!_isBrowserInstalled(executable)) {
        final error =
            'Installation appeared to succeed but browser is not available';
        logger.error('$logContext: $error');
        throw BrowserException(error);
      }

      logger.info('$logContext: Successfully installed ${executable.name}');
      return true;
    } catch (e, stack) {
      logger.error(
        '$logContext: Failed to install browser',
        error: e,
        stackTrace: stack,
      );

      // Provide more helpful error messages for common issues
      if (e is ArgumentError) {
        rethrow; // Don't wrap ArgumentError
      } else if (e is BrowserException) {
        rethrow;
      } else if (e.toString().contains('Permission denied')) {
        throw BrowserException(
          'Permission denied while installing $browserName. '
          'Try running with elevated permissions or check file system permissions.',
          e.toString(),
        );
      } else if (e.toString().contains('Network') ||
          e.toString().contains('Connection')) {
        throw BrowserException(
          'Network error while downloading $browserName. '
          'Check your internet connection and try again.',
          e.toString(),
        );
      } else {
        throw BrowserException(
          'Unexpected error while installing $browserName: ${e.toString()}',
          stack.toString(),
        );
      }
    }
  }

  /// Updates a browser to the latest available version.
  ///
  /// [browserName] - The name of the browser to update
  ///
  /// Returns true if the browser was updated, false if already up to date.
  ///
  /// Example:
  /// ```dart
  /// // Update chromium to latest version
  /// await updateBrowser('chromium');
  /// ```
  static Future<bool> updateBrowser(String browserName) async {
    final logContext = 'updateBrowser($browserName)';

    try {
      logger.info('$logContext: Starting update...');

      // Validate input
      if (browserName.trim().isEmpty) {
        throw ArgumentError('Browser name cannot be empty');
      }

      // Check if browser is currently installed
      final isInstalled = await isBrowserInstalled(browserName);
      if (!isInstalled) {
        logger.info(
          '$logContext: Browser not currently installed, performing fresh installation',
        );
        return await installBrowser(browserName);
      }

      logger.info(
        '$logContext: Browser is installed, forcing reinstallation to update',
      );

      // For now, updating means reinstalling with force=true
      // In a more sophisticated implementation, this could check for newer versions
      final result = await installBrowser(browserName, force: true);

      logger.info('$logContext: Update completed successfully');
      return result;
    } catch (e, stack) {
      logger.error(
        '$logContext: Failed to update browser',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Lists all available browsers that can be installed.
  ///
  /// Returns a list of browser names that are available for installation.
  ///
  /// Example:
  /// ```dart
  /// final browsers = await listAvailableBrowsers();
  /// print('Available browsers: $browsers');
  /// // Output: Available browsers: [chromium, firefox, webkit]
  /// ```
  static Future<List<String>> listAvailableBrowsers() async {
    const logContext = 'listAvailableBrowsers()';

    try {
      logger.info('$logContext: Listing available browsers...');

      // Ensure registry is initialized
      if (!_isRegistryInitialized()) {
        final error =
            'Browser registry not initialized. Call testBootstrap() first.';
        logger.error('$logContext: $error');
        throw BrowserException(error);
      }

      final executables = TestBootstrap.registry.executables;
      final browserNames = executables.map((e) => e.name).toList();

      logger.info(
        '$logContext: Found ${browserNames.length} available browsers: $browserNames',
      );
      return browserNames;
    } catch (e, stack) {
      logger.error(
        '$logContext: Failed to list available browsers',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Internal helper for safely listing browsers without throwing exceptions.
  static Future<List<String>> _safeListAvailableBrowsers() async {
    try {
      return await listAvailableBrowsers();
    } catch (e) {
      logger.info('Failed to list available browsers: $e');
      return ['chromium', 'firefox']; // Fallback list
    }
  }

  /// Gets version information for installed browsers.
  ///
  /// Returns a map where keys are browser names and values are version strings.
  /// Only includes browsers that are currently installed.
  ///
  /// Example:
  /// ```dart
  /// final versions = await getBrowserVersions();
  /// print('Installed versions: $versions');
  /// // Output: Installed versions: {chromium: 120.0.6099.109, firefox: 121.0}
  /// ```
  static Future<Map<String, String>> getBrowserVersions() async {
    const logContext = 'getBrowserVersions()';

    try {
      logger.info('$logContext: Getting browser versions...');

      // Ensure registry is initialized
      if (!_isRegistryInitialized()) {
        final error =
            'Browser registry not initialized. Call testBootstrap() first.';
        logger.error('$logContext: $error');
        throw BrowserException(error);
      }

      final Map<String, String> versions = {};
      final executables = TestBootstrap.registry.executables;

      logger.info(
        '$logContext: Checking ${executables.length} executables for installation status',
      );

      for (final executable in executables) {
        try {
          final overridePath = TestBootstrap.getBinaryOverride(
            executable.name,
          );
          if (overridePath != null) {
            final overrideFile = File(overridePath);
            if (overrideFile.existsSync()) {
              final version =
                  await _readBrowserVersion(overridePath) ??
                  executable.browserVersion ??
                  'unknown';
              versions[executable.name] = version;
              logger.info(
                '$logContext: Found override for ${executable.name} version $version',
              );
            } else {
              logger.info(
                '$logContext: Override for ${executable.name} not found at $overridePath',
              );
            }
            continue;
          }

          if (_isBrowserInstalled(executable)) {
            // Use browserVersion from the executable if available
            final version = executable.browserVersion ?? 'unknown';
            versions[executable.name] = version;
            logger.info(
              '$logContext: Found installed browser ${executable.name} version $version',
            );
          } else {
            logger.info(
              '$logContext: Browser ${executable.name} is not installed',
            );
          }
        } catch (e) {
          logger.info('$logContext: Error checking ${executable.name}: $e');
          // Continue with other browsers
        }
      }

      logger.info(
        '$logContext: Found ${versions.length} installed browsers: ${versions.keys.toList()}',
      );
      return versions;
    } catch (e, stack) {
      logger.error(
        '$logContext: Failed to get browser versions',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Checks if a browser is currently installed.
  ///
  /// [browserName] - The name of the browser to check
  ///
  /// Returns true if the browser is installed, false otherwise.
  ///
  /// Example:
  /// ```dart
  /// final isInstalled = await isBrowserInstalled('chromium');
  /// if (!isInstalled) {
  ///   await installBrowser('chromium');
  /// }
  /// ```
  static Future<bool> isBrowserInstalled(String browserName) async {
    final logContext = 'isBrowserInstalled($browserName)';

    try {
      logger.info('$logContext: Checking installation status...');

      // Validate input
      if (browserName.trim().isEmpty) {
        logger.info('$logContext: Empty browser name provided');
        return false;
      }

      // Ensure registry is initialized
      if (!_isRegistryInitialized()) {
        logger.info('$logContext: Registry not initialized');
        return false;
      }

      final registryName = _mapBrowserNameToRegistryName(browserName);
      final overridePath =
          TestBootstrap.getBinaryOverride(browserName) ??
          TestBootstrap.getBinaryOverride(registryName);
      if (overridePath != null) {
        final exists = File(overridePath).existsSync();
        logger.info(
          '$logContext: Binary override configured at $overridePath (exists=$exists)',
        );
        return exists;
      }
      logger.info(
        '$logContext: Mapped "$browserName" to registry name "$registryName"',
      );

      final executable = TestBootstrap.registry.getExecutable(registryName);

      if (executable == null) {
        logger.info('$logContext: Executable not found in registry');
        return false;
      }

      final isInstalled = _isBrowserInstalled(executable);
      logger.info('$logContext: Installation status: $isInstalled');
      return isInstalled;
    } catch (e) {
      logger.error('$logContext: Error checking installation status', error: e);
      return false;
    }
  }

  /// Internal helper to check if registry is initialized.
  static bool _isRegistryInitialized() {
    try {
      // Try to access the registry - this will throw if not initialized
      // ignore: unnecessary_statements
      TestBootstrap.registry;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Internal helper to check if an executable is installed.
  static bool _isBrowserInstalled(Executable executable) {
    if (executable.directory == null) {
      return false;
    }

    return Directory(executable.directory!).existsSync();
  }

  static Future<String?> _readBrowserVersion(String binaryPath) async {
    try {
      final result = await Process.run(binaryPath, ['--version']);
      if (result.exitCode != 0) return null;
      return result.stdout.toString().trim();
    } catch (_) {
      return null;
    }
  }

  /// Maps common user-facing browser names to internal registry names.
  static String _mapBrowserNameToRegistryName(String browserName) {
    final Map<String, String> browserMap = {
      'chromium': 'chromium',
      'chrome': 'chromium',
      'firefox': 'firefox',
      'safari': 'webkit', // Example mapping
    };
    return browserMap[browserName.toLowerCase()] ??
        browserName; // Return original if no mapping
  }
}
