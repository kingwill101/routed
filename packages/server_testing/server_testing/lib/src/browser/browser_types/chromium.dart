import 'dart:async';
import 'dart:io' show Platform, File, Process;

import 'package:path/path.dart' as path;
import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart'
    as bootstrap_driver;
import 'package:server_testing/src/browser/browser_exception.dart';
import 'package:server_testing/src/browser/interfaces/browser_type.dart';
import 'package:webdriver/async_io.dart' as wdasync;
import 'package:webdriver/sync_io.dart' as wdsync;

/// Implements the [BrowserType] interface for Google Chrome/Chromium.
class ChromiumType implements BrowserType {
  // Assume Registry is accessible via TestBootstrap singleton
  // DriverManager is accessed statically

  @override
  String get name => 'chromium'; // Use the internal registry name

  /// Gets the WebDriver browser name capability ('chrome').
  String get _webDriverBrowserName => 'chrome';

  @override
  Future<String> executablePath() async {
    // Allow specifying executable path via launch options first
    // This logic might need refinement depending on how BrowserLaunchOptions.executablePath is intended
    // final optionsExecutablePath = /* Get from some context if needed */;
    // if (optionsExecutablePath != null) return optionsExecutablePath;

    // Otherwise, get from registry
    final executable = TestBootstrap.registry.getExecutable(name);
    if (executable?.directory == null || executable?.executablePath == null) {
      throw BrowserException(
        'Chromium executable information not found in registry.',
      );
    }
    // Ensure executablePath() is called to get the relative path function result
    final relativePath = executable!.executablePath();
    return path.join(executable.directory!, relativePath);
  }

  @override
  Future<Browser> launch(
    BrowserLaunchOptions options, {
    bool useAsync = true,
  }) async {
    // 1. Determine the target executable name (handle channel override)
    final executableName = options.channel ?? name;

    // 1b. Ensure the correct Chromium binary (potentially a specific channel) is installed.
    //     Pass the force flag from the *current* effective configuration.
    await TestBootstrap.ensureBrowserInstalled(
      executableName,
      force: TestBootstrap.currentConfig.forceReinstall,
    );

    // 2. Ensure ChromeDriver server is running
    //    ChromeDriver itself usually corresponds to the base 'chrome' name.

    // Resolve driver hint from options/env
    final driverMajor = options.extraCapabilities?['driver:major'] as int?;
    final driverExact = options.extraCapabilities?['driver:version'] as String?;
    final port = await bootstrap_driver.DriverManager.ensureDriver(
      _webDriverBrowserName,
      force: TestBootstrap.currentConfig.forceReinstall,
      driverMajor: driverMajor,
      driverExact: driverExact,
    );

    // 3. Determine final launch parameters from effective configuration
    final config =
        TestBootstrap.currentConfig; // Use the potentially overridden config
    final headless = config.headless; // Headless state from effective config
    final effectiveBaseUrl =
        options.baseUrl ?? config.baseUrl; // Prioritize launch option override

    // Ensure browser binary and crashpad handler are executable (Linux)
    final chromeBin = await _executablePathFor(executableName);
    try {
      if (Platform.isLinux) {
        await Process.run('chmod', ['+x', chromeBin]);
        final crashpad = path.join(
          path.dirname(chromeBin),
          'chrome_crashpad_handler',
        );
        if (await File(crashpad).exists()) {
          await Process.run('chmod', ['+x', crashpad]);
        }
      }
    } catch (_) {}

    // 4. Build chromeOptions capabilities map
    final Map<String, dynamic> chromeOptions = {
      'args': (() {
        final args = <String>[
          if (headless) '--headless',
          '--disable-gpu',
          '--no-sandbox',
          '--disable-dev-shm-usage',
          '--disable-setuid-sandbox',
          '--no-first-run',
          '--no-default-browser-check',
          '--window-size=1280,800',
          if (Platform.isLinux) '--use-gl=swiftshader',
          '--remote-debugging-port=0',
        ];
        if (options.args != null) {
          args.addAll(options.args!);
        }
        // Do not force a user-data-dir; let ChromeDriver decide. Respect explicit user value only.
        if (options.userDataDir != null &&
            !args.any((a) => a.startsWith('--user-data-dir'))) {
          args.add('--user-data-dir=${options.userDataDir}');
        }
        return args;
      })(),
      // Explicitly use the registry-installed Chromium matching ChromeDriver
      'binary': chromeBin,
      'excludeSwitches': ['enable-automation', 'load-extension'],
      'prefs': {
        'plugins.always_open_pdf_externally': true,
        'profile.default_content_setting_values.notifications': 2,
        'protocol_handler.excluded_schemes.javascript': false,
        'credentials_enable_service': false,
        'download.prompt_for_download': false,
        'download.default_directory': config.screenshotPath,
        'savefile.default_directory': config.screenshotPath,
        'disk-cache-size': 100 * 1024 * 1024, // 100MB
        'profile.password_manager_enabled': false,
      },
      // Merge extra capabilities provided under 'goog:chromeOptions'
      ...?options.extraCapabilities?['goog:chromeOptions']
          as Map<String, dynamic>?,
    };

    // Apply device emulation settings if provided in launch options
    if (options.device != null) {
      final device = options.device!;
      chromeOptions['mobileEmulation'] = {
        'deviceMetrics': {
          'width': device.viewport.width,
          'height': device.viewport.height,
          'pixelRatio': device.deviceScaleFactor,
          'mobile': device.isMobile,
          'touch': device.hasTouch,
          'landscape': device.viewport.width > device.viewport.height,
        },
        'userAgent': device.userAgent,
      };
      print(
        "[ChromiumType] Applying device emulation for: ${device.userAgent}",
      );
    }

    // 5. Build final capabilities map
    final capabilities = <String, dynamic>{
      'browserName': _webDriverBrowserName,
      'goog:chromeOptions': chromeOptions,
      // Merge top-level extra capabilities provided by the user
      ...?options.extraCapabilities,
    };
    // Ensure goog:chromeOptions isn't duplicated at the top level
    // capabilities.remove('goog:chromeOptions');

    // 6. Determine Driver URL
    final driverUri = Uri.parse('http://localhost:$port');

    // 7. Create WebDriver instance (async or sync)
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
      print("Capabilities sent: $capabilities");
      throw BrowserException(
        'Failed to connect to ChromeDriver at $driverUri',
        '$e\n$s',
      );
    }

    // 8. Create final BrowserConfig for the runtime instance
    //    Use the effective configuration state (potentially overridden)
    final finalBrowserConfig = config.copyWith(
      // Ensure the runtime config knows the *actual* browser name used ('chromium')
      // even if WebDriver uses 'chrome'
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

    // 9. Wrap WebDriver in Browser interface using the factory
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

  // Helper to get executable path for a specific name (channel or default)
  Future<String> _executablePathFor(String executableName) async {
    final executable = TestBootstrap.registry.getExecutable(executableName);
    if (executable?.directory == null || executable?.executablePath == null) {
      throw BrowserException(
        'Executable info for "$executableName" not found in registry.',
      );
    }
    final relativePath = executable!.executablePath();
    return path.join(executable.directory!, relativePath);
  }
}
