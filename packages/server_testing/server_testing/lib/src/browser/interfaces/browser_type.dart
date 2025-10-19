import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';

import '../bootstrap/device_json.dart'; // Import Device
import '../bootstrap/proxy.dart';

/// Defines options specifically for launching a browser instance.
///
/// Used by [BrowserType.launch] to configure the browser process startup.
class BrowserLaunchOptions {
  /// Whether to run the browser in headless mode. If null, the default
  /// from the global configuration or BrowserType implementation is used.
  final bool? headless;

  /// Additional command-line arguments to pass to the browser executable.
  final List<String>? args;

  /// Browser distribution channel (e.g., 'chrome', 'msedge-dev'). If null,
  /// the default channel for the browser type is used.
  final String? channel;

  /// Path to a specific browser executable to use instead of the one
  /// managed by the registry. Use with caution.
  final String? executablePath;

  /// Environment variables to set for the browser process. Merged with
  /// the default environment.
  final Map<String, String>? env;

  /// Maximum time to wait for the browser instance to start. If null,
  /// a default timeout is used.
  final Duration? timeout;

  /// Network proxy settings for the browser instance.
  final ProxyConfiguration? proxy;

  /// Amount of time (in milliseconds) to slow down Playwright operations.
  /// Useful for debugging.
  final Duration? slowMo;

  /// For persistent contexts: Path to the user data directory.
  /// If launching a regular browser, this is usually handled internally.
  final String? userDataDir;

  /// Additional WebDriver capabilities to merge with the defaults.
  final Map<String, dynamic>? extraCapabilities;

  /// Base URL for the application under test. Overrides the global config.
  final String? baseUrl;

  /// Optional device profile to emulate. If provided, settings like viewport,
  /// userAgent, deviceScaleFactor, isMobile, and hasTouch will be configured
  /// based on the device definition, potentially overriding other options.
  final Device? device;

  /// Creates a set of browser launch options.
  const BrowserLaunchOptions({
    this.headless,
    this.args,
    this.channel,
    this.executablePath,
    this.env,
    this.timeout,
    this.proxy,
    this.slowMo,
    this.userDataDir,
    this.extraCapabilities,
    this.baseUrl,
    this.device,
  });
}

/// Abstract interface for a specific browser type (e.g., Chromium, Firefox).
///
/// Provides methods to launch browser instances and retrieve information
/// like the expected executable path. Concrete implementations handle the
/// specifics of launching and configuring each browser.
abstract class BrowserType {
  /// The canonical name of the browser type used by the registry
  /// (e.g., 'chromium', 'firefox', 'webkit').
  String get name;

  /// Launches a new browser instance with the specified options.
  ///
  /// [options]: Configuration specific to this launch operation.
  ///
  /// Returns a [Future] that completes with the launched [Browser] instance.
  /// Throws exceptions if the browser cannot be launched (e.g., binary not
  /// found, WebDriver connection fails).
  ///
  /// [useAsync]: Determines whether to launch using the asynchronous (`true`)
  /// or synchronous (`false`) WebDriver API and return the corresponding
  /// [Browser] implementation. Defaults to `true`.
  Future<Browser> launch(BrowserLaunchOptions options, {bool useAsync = true});

  /// Gets the expected path to the browser executable managed by the registry.
  ///
  /// Returns the path string. Throws if the executable information cannot be found.
  Future<String> executablePath();

  // Potential future methods (similar to Playwright):
  // Future<Browser> launchPersistentContext(String userDataDir, BrowserLaunchOptions options);
  // Future<Browser> connect(String wsEndpoint, BrowserLaunchOptions options);
  // Future<BrowserServer> launchServer(options);
}
