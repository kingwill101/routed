import 'dart:io' show Platform;

import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart'
    as driver_manager;

bool _hasHeadfulDisplay() {
  if (!Platform.isLinux) return true;
  final display = Platform.environment['DISPLAY'];
  if (display != null && display.trim().isNotEmpty) return true;
  final wayland = Platform.environment['WAYLAND_DISPLAY'];
  return wayland != null && wayland.trim().isNotEmpty;
}

bool _shouldForceHeadless() {
  final isCi =
      Platform.environment['CI'] == 'true' ||
      Platform.environment.containsKey('GITHUB_ACTIONS');
  if (!isCi) return !_hasHeadfulDisplay();
  return !_hasHeadfulDisplay();
}

Future<void> realBrowserBootstrap(BrowserConfig config) async {
  final effectiveConfig = (!config.headless && _shouldForceHeadless())
      ? config.copyWith(headless: true)
      : config;
  await TestBootstrap.initialize(effectiveConfig);

  final logger = BrowserLogger(
    logDir: effectiveConfig.logDir,
    verbose: effectiveConfig.verbose,
    enabled: effectiveConfig.loggingEnabled,
  );
  BrowserManagement.setLogger(logger);

  await TestBootstrap.ensureBrowserInstalled(
    effectiveConfig.browserName,
    force: effectiveConfig.forceReinstall,
  );
}

Future<void> realBrowserCleanup() async {
  await driver_manager.DriverManager.stopAll();
}
