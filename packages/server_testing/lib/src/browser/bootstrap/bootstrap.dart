import 'dart:async';
import 'dart:io';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart';
import 'package:server_testing/src/browser/bootstrap/registry.dart';
import 'package:server_testing/src/browser/logger.dart';

/// Initializes the browser testing environment.
///
/// This function sets up the necessary infrastructure for browser testing,
/// including:
/// - Installing browser binaries if needed
/// - Starting WebDriver servers
/// - Configuring test hooks for proper cleanup
///
/// [config] is an optional [BrowserConfig] that specifies browser settings.
/// If not provided, a default configuration will be used.
///
/// Example:
/// ```dart
/// void main() async {
///   // Set up with default Chrome configuration
///   await testBootstrap();
///
///   // Or with custom configuration
///   await testBootstrap(
///     BrowserConfig(
///       browserName: 'firefox',
///       headless: false,
///       baseUrl: 'https://example.com',
///     )
///   );
///
///   // Run your browser tests
///   browserTest('should display homepage', (browser) async {
///     // Test implementation
///   });
/// }
/// ```
Future<void> testBootstrap([BrowserConfig? config]) async {
  config ??= BrowserConfig();

  // Initialize the global config first
  await TestBootstrap.initialize(config);

  final logger = BrowserLogger(
    logDir: config.logDir,
    verbose: config.verbose,
  );

  setUpAll(() async {
    logger.startTestLog('setup');
    logger.info('Setting up browser testing environment...');

    try {
      // Ensure driver is running before browser setup
      await DriverManager.ensureDriver(config!.browserName);

      final registry = Registry(
        await BrowserJsonLoader.load(),
        requestedBrowser: config.browserName,
      );

      final executable = registry.getExecutable(config.browserName);
      if (executable == null) {
        throw Exception('Browser ${config.browserName} not available');
      }

      if ((executable.directory != null &&
              !Directory(executable.directory!).existsSync()) ||
          config.forceReinstall) {
        await registry.installExecutables(
          [executable],
          force: config.forceReinstall,
        );
      } else {
        logger.info('Browser already installed, skipping installation.');
      }

      await registry.validateRequirements([executable], 'dart');

      print('\nBrowser testing environment ready.');
    } catch (e, stack) {
      logger.error('Failed to setup browser testing environment:', e, stack);
      rethrow;
    }
  });

  tearDownAll(() async {
    print('\nCleaning up browser testing environment...');
    await DriverManager.stopAll();
  });
}

/// Internal class that maintains the global browser configuration.
///
/// This class stores configuration used across multiple browser test
/// instances to ensure consistent settings.
class TestBootstrap {
  /// The global browser configuration used by all tests.
  static late BrowserConfig currentConfig;

  /// Initializes the global browser configuration.
  ///
  /// [config] is the configuration to use for browser tests.
  static Future<void> initialize(BrowserConfig config) async {
    currentConfig = config;
  }
}
