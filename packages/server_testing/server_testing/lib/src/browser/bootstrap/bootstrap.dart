import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart'
    as bootstrap_driver; // Use prefix for clarity
import 'package:server_testing/src/browser/bootstrap/registry.dart';
import 'package:server_testing/src/browser/browser_management.dart'
    as browser_mgmt;
import 'package:server_testing/src/browser/interfaces/browser_type.dart';

/// Configures and initializes the browser testing environment.
///
/// Initializes the browser testing environment.
///
/// This function sets up the necessary infrastructure for browser testing,
/// including:
/// - Potentially installing the default browser binary if needed (most installation
///   happens just-in-time when a specific browser is launched).
/// - Starting the WebDriver server for the default browser.
/// - Configuring global test hooks (`setUpAll`, `tearDownAll`) for driver cleanup.
/// - Initializing global configuration access and override mechanisms.
///
/// [config] is an optional [BrowserConfig] that specifies the default browser
/// settings (browserName, headless, baseUrl, etc.). If not provided, a
/// default `BrowserConfig()` (usually defaulting to chromium/chrome) will be used.
///
/// Example:
/// ```dart
/// void main() async {
///   // Set up with default Chrome configuration
///   await testBootstrap();
///
///   // Or with custom configuration (e.g., default to Firefox)
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
///     // This will use the default browser ('firefox' in the second example)
///     await browser.visit('/');
///     // Test implementation
///   });
///
///   browserTest('run explicitly in chrome', (browser) async {
///     // This overrides the default and launches chrome
///   }, browserType: chromium);
/// }
/// ```
///
/// Call this function once at the beginning of your test suite, typically in
/// the `main` function of your primary test file.
Future<void> testBootstrap([BrowserConfig? config]) async {
  config ??= BrowserConfig();

  // Initialize the global config and registry/driver manager singletons first
  await TestBootstrap.initialize(config);

  final logger = BrowserLogger(
    logDir: config.logDir,
    verbose: config.verbose,
    enabled: config.loggingEnabled,
  );
  BrowserManagement.setLogger(logger);

  setUpAll(() async {
    logger.startTestLog('global_setup'); // More descriptive name
    logger.info('Setting up global browser test environment...');

    try {
      // Get the *initial* configuration used for bootstrap
      // Access the first element pushed onto the stack during initialize
      final initialConfig = TestBootstrap._configStack.first;
      logger.info(
        'Initial default browser from config: ${initialConfig.browserName}',
      );

      // Enhanced browser installation with auto-detection and better error handling
      final hasOverride =
          TestBootstrap.getBinaryOverride(initialConfig.browserName) != null;

      if (initialConfig.autoInstall && !hasOverride) {
        logger.info(
          'Auto-install is enabled, checking browser availability...',
        );

        // Try to auto-detect and install the best available browser
        final success = await _autoDetectAndInstallBrowser(
          initialConfig.browserName,
          force: initialConfig.forceReinstall,
          logger: logger,
        );

        if (!success) {
          logger.info(
            'Failed to auto-install browser, proceeding with manual installation check...',
          );
        }
      } else if (hasOverride) {
        logger.info(
          'Skipping auto-install because a binary override is configured for ${initialConfig.browserName}.',
        );
      } else {
        logger.info('Auto-install disabled via configuration.');
      }

      // 1. Ensure the DEFAULT browser binary (from initial config) is installed.
      //    This primes the environment for the most common case.
      //    Tests requesting other browsers will handle their own install via BrowserType.launch.
      logger.info(
        'Ensuring default browser binary (${initialConfig.browserName}) is installed...',
      );
      // Pass the specific initial browser name and force flag
      await TestBootstrap.ensureBrowserInstalled(
        initialConfig.browserName,
        force: initialConfig.forceReinstall,
      );
      logger.info('Default browser binary check complete.');

      // 2. Ensure the WebDriver server for the DEFAULT browser is running.
      //    This makes launching the default browser faster later.
      logger.info(
        'Ensuring WebDriver server for default browser (${initialConfig.browserName}) is running...',
      );
      // Pass the specific initial browser name
      // await bootstrap_driver.DriverManager.ensureDriver(
      //     initialConfig.browserName);
      // logger.info('WebDriver server for default browser is ready.');

      print('\nGlobal browser testing environment ready.');
    } catch (e, stack) {
      logger.error(
        'Failed to setup global browser testing environment:',
        error: e,
        stackTrace: stack,
      );
      rethrow; // Fail setup if critical parts fail
    }
  });

  tearDownAll(() async {
    print('\nCleaning up browser testing environment...');
    // Access static method directly on the class
    await bootstrap_driver.DriverManager.stopAll();
  });
}

/// Manages global state for the browser test bootstrap process.
///
/// Internal class that maintains the global browser configuration and provides
/// methods for overriding configurations in specific contexts.
class TestBootstrap {
  /// The *currently effective* global browser configuration. This can be
  /// temporarily changed by [pushConfigOverride] and restored by [popConfigOverride].
  /// Initialized by [testBootstrap] and accessible by test helpers.
  static late BrowserConfig currentConfig;

  /// Stack of configuration overrides for nested test contexts.
  /// The first element is always the initial base configuration.
  static final List<BrowserConfig> _configStack = [];

  /// Initializes the global [TestBootstrap] state with the provided [config].
  ///
  /// This should only be called once by [testBootstrap].
  static Future<void> initialize(BrowserConfig config) async {
    currentConfig = config;
    _configStack.clear(); // Ensure stack is clear on init
    _configStack.add(currentConfig); // Start stack with initial base config

    // Initialize singletons needed by BrowserType implementations
    // Registry now loads all browser definitions
    registry = Registry(await BrowserJsonLoader.load());
    // DriverManager instantiation
    driverManager = bootstrap_driver.DriverManager();
    // Initialize browser types (add more as implemented)
    // Ensure this happens *after* registry/driverManager if BrowserType constructors need them.
    // Assuming BrowserType constructors don't need them immediately.
    _initializeBrowserTypes();
  }

  /// Initializes the map of available browser types.
  /// Called by [initialize].
  static void _initializeBrowserTypes() {
    browserTypes = {
      'firefox': FirefoxType(),
      'chromium': ChromiumType(),
      // Add 'webkit': WebkitType() when implemented
    };
  }

  /// Temporarily overrides the current configuration for a specific context.
  ///
  /// Pushes the current config to the stack and applies overrides based on
  /// non-null parameters provided. Returns the newly calculated `currentConfig`.
  static BrowserConfig pushConfigOverride({
    String? browserName,
    bool? headless,
    String? baseUrl,
    ProxyConfiguration? proxy,
    Duration? timeout, // Operation timeout
  }) {
    // Save the current config to the stack before overriding
    _configStack.add(currentConfig);

    // Create a new config by applying overrides to the *current* one
    final newConfig = currentConfig.copyWith(
      browserName: browserName,
      // Only override if provided
      headless: headless,
      baseUrl: baseUrl,
      proxy: proxy,
      timeout: timeout,
    );

    // Update the current effective config
    currentConfig = newConfig;
    print(
      "Pushed config override. New effective config: browserName=${currentConfig.browserName}, headless=${currentConfig.headless}",
    );
    return newConfig;
  }

  /// Restores the previous configuration from the stack.
  ///
  /// Must be called in a `finally` block or `tearDown` corresponding to
  /// where `pushConfigOverride` was called.
  static void popConfigOverride() {
    if (_configStack.length <= 1) {
      // We should never pop the initial base config pushed during initialize
      print(
        'Warning: Configuration stack has only base config. Cannot pop further.',
      );
      // Optionally throw an error if this indicates a logic bug
      // throw StateError('Configuration stack underflow during pop.');
      // If we allow it, reset to the last known state (which is the base)
      if (_configStack.isNotEmpty) currentConfig = _configStack.last;
      return;
    }
    // Restore the previous config from the stack
    currentConfig = _configStack.removeLast();
    print(
      "Popped config override. Restored config: browserName=${currentConfig.browserName}, headless=${currentConfig.headless}",
    );
  }

  /// Globally accessible Registry instance. Initialized by [initialize].
  static late Registry registry;

  /// Globally accessible DriverManager instance. Initialized by [initialize].
  /// Note: Methods on DriverManager are static, so this instance might not be strictly needed
  /// for calling methods like `ensureDriver`, but good to have if non-static methods are added.
  static late bootstrap_driver.DriverManager driverManager;

  /// Globally accessible map of browser type implementations. Initialized by [initialize].
  static late Map<String, BrowserType> browserTypes;

  /// Ensures that the specified browser is downloaded and installed.
  ///
  /// Uses the provided [browserName] or falls back to the *current* effective
  /// configuration (`currentConfig.browserName`). It looks up the browser
  /// in the fully loaded registry and triggers installation if needed.
  ///
  /// Returns true if the browser was newly installed or installation was successful,
  /// false otherwise (e.g., installation failed, or it was already present).
  static Future<bool> ensureBrowserInstalled(
    String? browserName, {
    bool force = false,
  }) async {
    // Use the provided name or the *current* config's name
    final targetBrowserName = browserName ?? currentConfig.browserName;
    print("Ensuring installation for: $targetBrowserName");

    final overridePath = _binaryOverrideFor(targetBrowserName);
    if (overridePath != null) {
      print(
        'Binary override detected for $targetBrowserName -> $overridePath. Skipping installation.',
      );
      if (!File(overridePath).existsSync()) {
        throw BrowserException(
          'Browser override for "$targetBrowserName" points to a missing executable: $overridePath',
        );
      }
      return false;
    }

    // Handle potential alias (e.g., 'chrome' -> 'chromium')
    final registryName = _mapBrowserNameToRegistryName(targetBrowserName);

    final executable = registry.getExecutable(registryName);
    if (executable == null) {
      throw BrowserException(
        'Browser definition for "$registryName" (mapped from "$targetBrowserName") not found in registry.',
      );
    }

    // Check if installation is needed
    bool needsInstall = force;
    if (!force && executable.directory != null) {
      needsInstall = !Directory(executable.directory!).existsSync();
      // Could add more checks here, e.g., using InstallationValidator.isValid
    } else if (!force) {
      // If directory is null, we might assume it doesn't need install or handle differently
      needsInstall = false; // Or perhaps throw? Depends on Executable contract
      print(
        "Warning: Executable for $registryName has no directory, skipping installation check.",
      );
    }

    bool installedNow = false;
    if (needsInstall) {
      print('Installing ${executable.name}...');
      try {
        // Pass force flag to installExecutables if needed, though install() method inside Executable should handle it
        await registry.installExecutables([executable], force: force);
        installedNow = true;
        print('Installation successful for ${executable.name}.');
      } catch (e, s) {
        print('ERROR: Failed to install ${executable.name}: $e\n$s');
        rethrow; // Propagate the error
      }
    } else {
      print(
        '${executable.name} is already installed or installation not forced.',
      );
    }

    // Always validate requirements after attempting install (or confirming presence)
    try {
      await registry.validateRequirements([executable], 'dart');
    } catch (e, s) {
      print('ERROR: Failed validation for ${executable.name}: $e\n$s');
      // Decide if validation failure should prevent proceeding
      rethrow;
    }

    return installedNow; // Return true mainly if a new installation happened.
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

  /// Returns the configured binary override for [browserName], if any.
  static String? getBinaryOverride(String browserName) {
    return _binaryOverrideFor(browserName);
  }

  /// Resolves the executable path for [browserName], honoring overrides when set.
  static Future<String> resolveExecutablePath(String browserName) async {
    final override = _binaryOverrideFor(browserName);
    if (override != null) {
      final file = File(override);
      if (!file.existsSync()) {
        throw BrowserException(
          'Browser override for "$browserName" points to a missing executable: $override',
        );
      }
      return override;
    }

    final registryName = _mapBrowserNameToRegistryName(browserName);
    final executable = registry.getExecutable(registryName);
    if (executable?.directory == null || executable?.executablePath == null) {
      throw BrowserException(
        'Browser definition for "$registryName" (from "$browserName") not found in registry.',
      );
    }

    final relative = executable!.executablePath();
    final resolved = p.join(executable.directory!, relative);
    if (!File(resolved).existsSync()) {
      throw BrowserException(
        'Expected browser binary for "$registryName" at $resolved but it was not found. '
        'Install the browser or configure a binary override.',
      );
    }
    return resolved;
  }

  static String? _binaryOverrideFor(String browserName) {
    final candidates = _overrideCandidateKeys(browserName);
    for (final key in candidates) {
      final direct = currentConfig.binaryOverrides[key.toLowerCase()];
      if (direct != null && direct.isNotEmpty) {
        return direct;
      }
    }

    for (final key in candidates) {
      final envKey = 'SERVER_TESTING_${_normalizeEnvKeySegment(key)}_BINARY';
      final envValue = Platform.environment[envKey];
      if (envValue != null && envValue.trim().isNotEmpty) {
        return envValue.trim();
      }
    }

    return null;
  }

  static List<String> _overrideCandidateKeys(String browserName) {
    final normalized = browserName.toLowerCase();
    final registryName = _mapBrowserNameToRegistryName(
      browserName,
    ).toLowerCase();
    final base = normalized.split('-').first;

    final candidates = <String>{browserName, normalized, registryName, base};

    return candidates
        .where((value) => value.isNotEmpty)
        .map((value) => value.toLowerCase())
        .toList();
  }

  static String _normalizeEnvKeySegment(String key) {
    return key.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '_');
  }
}

/// Auto-detects and installs the best available browser.
///
/// Tries to install the requested browser, and if that fails, tries fallback browsers
/// in order of preference. Provides better error handling and logging.
Future<bool> _autoDetectAndInstallBrowser(
  String preferredBrowser, {
  bool force = false,
  required BrowserLogger logger,
}) async {
  // List of browsers to try in order of preference
  final browserPreferences = [
    preferredBrowser,
    'chromium',
    'firefox',
    'webkit',
  ];

  // Remove duplicates while preserving order
  final uniqueBrowsers = <String>[];
  for (final browser in browserPreferences) {
    if (!uniqueBrowsers.contains(browser)) {
      uniqueBrowsers.add(browser);
    }
  }

  logger.info('Attempting to auto-install browsers in order: $uniqueBrowsers');

  for (final browserName in uniqueBrowsers) {
    try {
      logger.info('Trying to install: $browserName');

      // Check if browser is available in registry
      final available =
          await browser_mgmt.BrowserManagement.listAvailableBrowsers();
      final registryName = TestBootstrap._mapBrowserNameToRegistryName(
        browserName,
      );

      if (!available.contains(registryName)) {
        logger.info(
          'Browser $browserName ($registryName) not available in registry, skipping...',
        );
        continue;
      }

      // Try to install the browser
      final installed = await browser_mgmt.BrowserManagement.installBrowser(
        browserName,
        force: force,
      );

      if (installed ||
          await browser_mgmt.BrowserManagement.isBrowserInstalled(
            browserName,
          )) {
        logger.info('Successfully installed/verified browser: $browserName');
        return true;
      }
    } catch (e) {
      logger.info('Failed to install $browserName: $e');
      continue; // Try next browser
    }
  }

  logger.error(
    'Failed to auto-install any browser from preferences: $uniqueBrowsers',
  );
  return false;
}
