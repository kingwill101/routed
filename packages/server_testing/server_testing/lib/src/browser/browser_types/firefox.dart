import 'dart:async';
import 'dart:io' show Directory, ProcessSignal;

import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart'
    as bootstrap_driver; // Use prefix to avoid conflict if needed elsewhere
import 'package:server_testing/src/browser/interfaces/browser_type.dart';
import 'package:webdriver/async_io.dart' as wdasync;
import 'package:webdriver/sync_io.dart' as wdsync;

/// Implements the [BrowserType] interface for Mozilla Firefox.
class FirefoxType implements BrowserType {
  @override
  String get name => 'firefox';

  @override
  Future<String> executablePath() async {
    return TestBootstrap.resolveExecutablePath(name);
  }

  @override
  Future<Browser> launch(
    BrowserLaunchOptions options, {
    bool useAsync = true,
  }) async {
    // 1. Ensure Firefox binary is installed *just before launch*
    //    Pass the force flag from the *current* effective configuration.
    await TestBootstrap.ensureBrowserInstalled(
      name,
      force: TestBootstrap.currentConfig.forceReinstall,
    );

    // 2. Ensure GeckoDriver server is running
    // Access static method directly on the class
    final port = await bootstrap_driver.DriverManager.ensureDriver(
      name,
      force: TestBootstrap.currentConfig.forceReinstall,
    );

    // 3. Determine final launch parameters from effective configuration
    final config =
        TestBootstrap.currentConfig; // Use the potentially overridden config
    final headless = config.headless; // Headless state from effective config
    final effectiveBaseUrl =
        options.baseUrl ?? config.baseUrl; // Prioritize launch option override

    // --- Start Capability/Args/Prefs Building ---
    final List<String> effectiveArgs = [
      if (headless) '--headless',
      ...?options.args, // Add explicit args from launch options FIRST
    ];
    final Map<String, dynamic> firefoxPrefs = {
      // Start with user prefs from extraCapabilities under 'prefs'
      ...?options.extraCapabilities?['moz:firefoxOptions']?['prefs']
          as Map<String, dynamic>?,
    };

    // Ensure a unique Firefox profile directory to avoid lock contention
    final hasProfileArg = effectiveArgs.any(
      (a) => a == '-profile' || a.startsWith('-profile'),
    );
    final uniqueProfileDir = _freshProfileDirPath();
    if (hasProfileArg) {
      // Replace existing -profile value with unique dir
      for (var i = 0; i < effectiveArgs.length; i++) {
        if (effectiveArgs[i] == '-profile' && i + 1 < effectiveArgs.length) {
          effectiveArgs[i + 1] = uniqueProfileDir;
        } else if (effectiveArgs[i].startsWith('-profile')) {
          effectiveArgs[i] = '-profile=$uniqueProfileDir';
        }
      }
    } else {
      effectiveArgs.addAll(['-profile', uniqueProfileDir]);
    }

    // --- Apply Device Emulation (if provided) ---
    if (options.device != null) {
      final device = options.device!;
      // Override/add settings for Firefox emulation
      effectiveArgs.addAll([
        // Firefox might not directly support setting size via args like this reliably,
        // WindowManager.resize might be needed post-launch.
        // Consider adding '--width=${device.viewport.width}',
        // Consider adding '--height=${device.viewport.height}',
      ]);
      firefoxPrefs.addAll({
        'general.useragent.override': device.userAgent,
        'layout.css.devPixelsPerPx': device.deviceScaleFactor.toString(),
        // Firefox touch event emulation via prefs might be less direct than Chrome's mobileEmulation
        // 'dom.w3c_touch_events.enabled': device.hasTouch ? 1 : 0, // Example, check actual pref name
      });
      print("[FirefoxType] Applying device emulation for: ${device.userAgent}");
      // Warn if size args aren't reliable for Firefox
      print(
        "[FirefoxType] Warning: Viewport size emulation via args might be unreliable for Firefox. Use browser.window.resize() post-launch if needed.",
      );
    }
    // --- End Apply Device Emulation ---

    // 4. Build final capabilities map
    final Map<String, dynamic> firefoxOptions = {
      'args': effectiveArgs,
      'prefs': firefoxPrefs,
      'binary': await executablePath(),
      // Merge other user options provided under moz:firefoxOptions (excluding args/prefs)
      // Need to carefully merge maps to avoid overwriting what we just built
      ...?options.extraCapabilities?['moz:firefoxOptions']
          as Map<String, dynamic>?,
    };
    // Ensure our built args/prefs/binary overwrite any potentially conflicting ones from extraCapabilities
    firefoxOptions['args'] = effectiveArgs;
    firefoxOptions['prefs'] = firefoxPrefs;
    firefoxOptions['binary'] = await executablePath();

    final capabilities = <String, dynamic>{
      'browserName': 'firefox',
      'moz:firefoxOptions': firefoxOptions,
      // Merge top-level extra capabilities (those NOT under moz:firefoxOptions)
      ...?options.extraCapabilities,
    };

    // 5. Determine Driver URL (GeckoDriver uses root)
    final driverUri = Uri.parse('http://localhost:$port');

    // 6. Create WebDriver instance (async or sync)
    Object webDriver; // Use Object to hold either type
    try {
      if (useAsync) {
        webDriver = await wdasync.createDriver(
          uri: driverUri,
          desired: capabilities,
          // TODO: Incorporate options.timeout (launchTimeout) for connection?
        );
      } else {
        webDriver = wdsync.createDriver(
          uri: driverUri,
          desired: capabilities,
          // TODO: Incorporate options.timeout (launchTimeout) for connection?
        );
      }
    } catch (e, s) {
      print("[FirefoxType] Failed to create WebDriver instance: $e");
      print("Capabilities sent: $capabilities");
      print(s);
      throw BrowserException(
        'Failed to connect to GeckoDriver at $driverUri',
        '$e\n$s',
      );
    }

    // 7. Create final BrowserConfig for the runtime instance
    final finalBrowserConfig = config.copyWith(
      // Ensure the runtime config knows the *actual* browser name used ('firefox')
      browserName: name,
      // Reflect actual launch state in the runtime config
      headless: headless,
      // Use the base URL determined earlier (override takes precedence)
      baseUrl: effectiveBaseUrl,
      // Pass through capabilities used, might be useful for Browser instance
      capabilities: capabilities,
      // Pass other relevant runtime options from config like operation timeout
      timeout: config.timeout,
    );

    // 8. Wrap WebDriver in Browser interface using the factory
    if (useAsync) {
      return BrowserFactory.createAsync(
        webDriver as wdasync.WebDriver,
        finalBrowserConfig,
      );
    } else {
      return BrowserFactory.createSync(
        webDriver as wdsync.WebDriver,
        finalBrowserConfig,
      );
    }
  }

  String _freshProfileDirPath() {
    final dir = Directory.systemTemp.createTempSync('st_ff_profile_');
    try {
      ProcessSignal.sigint.watch().listen((_) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
    } catch (_) {}
    return dir.path;
  }
}
