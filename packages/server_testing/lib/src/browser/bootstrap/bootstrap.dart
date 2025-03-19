import 'dart:async';
import 'dart:io';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart';
import 'package:server_testing/src/browser/bootstrap/registry.dart';
import 'package:server_testing/src/browser/logger.dart';

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

class TestBootstrap {
  static late BrowserConfig currentConfig;

  static Future<void> initialize(BrowserConfig config) async {
    currentConfig = config;
  }
}
