import 'dart:async';
import 'dart:io';
import 'package:routed_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:routed_testing/src/browser/bootstrap/driver_manager.dart';
import 'package:test/test.dart';
import 'package:routed_testing/src/browser/bootstrap/registry.dart';
import 'package:routed_testing/src/browser/logger.dart';

class TestBootstrapConfig {
  final String browser;
  // final String version;
  final String baseUrl;
  final bool debug;
  final bool forceReinstall;
  final Duration timeout;
  final String logDir;
  final bool verboseLogs;

  const TestBootstrapConfig({
    this.browser = 'chrome',
    // this.version = 'latest',
    this.baseUrl = 'http://localhost:8000',
    this.debug = false,
    this.forceReinstall = true,
    this.timeout = const Duration(minutes: 2),
    this.logDir = 'test/logs',
    this.verboseLogs = false,
  });
}

Future<void> testBootstrap([TestBootstrapConfig? config]) async {
  config ??= TestBootstrapConfig();

  // Initialize the global config first
  await TestBootstrap.initialize(config);

  final logger = BrowserLogger(
    logDir: config.logDir,
    verbose: config.verboseLogs,
  );

  setUpAll(() async {
    logger.startTestLog('setup');
    logger.info('Setting up browser testing environment...');

    try {
      // Ensure driver is running before browser setup
      await DriverManager.ensureDriver(config!.browser);

      final registry = Registry(
        await BrowserJsonLoader.load(),
        requestedBrowser: config.browser,
      );

      final executable = registry.getExecutable(config.browser);
      if (executable == null) {
        throw Exception('Browser ${config.browser} not available');
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

class TestBootstrap {
  static late TestBootstrapConfig currentConfig;

  static Future<void> initialize(TestBootstrapConfig config) async {
    currentConfig = config;
  }
}
