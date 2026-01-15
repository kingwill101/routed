import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart'
    as driver_manager;

Future<void> realBrowserBootstrap(BrowserConfig config) async {
  await TestBootstrap.initialize(config);

  final logger = BrowserLogger(
    logDir: config.logDir,
    verbose: config.verbose,
    enabled: config.loggingEnabled,
  );
  BrowserManagement.setLogger(logger);

  await TestBootstrap.ensureBrowserInstalled(
    config.browserName,
    force: config.forceReinstall,
  );
}

Future<void> realBrowserCleanup() async {
  await driver_manager.DriverManager.stopAll();
}
