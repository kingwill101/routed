import 'package:server_testing/src/browser/bootstrap/browser_manager.dart';
import 'package:server_testing/src/browser/bootstrap/progress.dart';
import 'package:server_testing/src/browser/bootstrap/proxy.dart';
import 'package:server_testing/src/browser/bootstrap/version.dart';

Map<String, dynamic> _defaultCapabilities(String browserName) {
  final browserPath = BrowserManager.getBrowserPath(browserName);

  return {
    'browserName': browserName,
    if (browserName == 'chrome')
      'goog:chromeOptions': {
        'args': ['--headless', '--disable-gpu', '--no-sandbox'],
        if (browserPath != null) 'binary': browserPath,
      },
    if (browserName == 'firefox')
      'moz:firefoxOptions': {
        'args': ['-headless'],
        if (browserPath != null) 'binary': browserPath,
      },
  };
}

/// Configuration options for browser-based tests.
///
/// Controls browser type, WebDriver settings, timeouts, proxy configuration,
/// and other test environment options.
///
/// ```dart
/// final config = BrowserConfig(
///   browserName: 'firefox',
///   headless: false,
///   baseUrl: 'http://localhost:3000',
///   timeout: Duration(seconds: 60),
/// );
///
/// final browser = await launchBrowser(config);
/// ```
class BrowserConfig {
  /// The name of the browser to use (e.g., 'chrome', 'firefox').
  final String browserName;
  
  /// The specific version of the browser to use.
  final Version? version;
  
  /// Whether to automatically download the browser if not available.
  final bool autoDownload;
  
  /// The URL of the Selenium server.
  final String seleniumUrl;
  
  /// WebDriver capabilities to pass to the browser.
  final Map<String, dynamic> capabilities;
  
  /// The base URL for the application under test.
  final String? baseUrl;
  
  /// The directory where screenshots will be saved.
  final String screenshotPath;
  
  /// The timeout duration for browser operations.
  final Duration timeout;
  
  /// The proxy configuration for the browser.
  final ProxyConfiguration? proxy;
  
  /// Whether to enable browser cache between tests.
  final bool enableCache;
  
  /// Callback function for browser download progress updates.
  final BrowserDownloadProgress Function(BrowserDownloadProgress)?
      onDownloadProgress;
  
  /// Whether to run the browser in headless mode.
  final bool headless;
  
  /// Whether to reinstall the browser even if already installed.
  final bool forceReinstall;
  
  /// Whether to output verbose logs.
  final bool verbose;
  
  /// The directory where logs will be saved.
  final String logDir;
  
  /// Whether to enable debug mode.
  final bool debug;

  /// Creates a browser configuration with the specified options.
  ///
  /// Any unspecified options use reasonable defaults.
  BrowserConfig({
    this.browserName = 'chrome',
    this.version,
    this.debug = false,
    this.autoDownload = true,
    this.seleniumUrl = 'http://localhost:4444/wd/hub',
    Map<String, dynamic>? capabilities,
    this.baseUrl = 'http://localhost:8000',
    this.screenshotPath = 'test/screenshots',
    this.headless = true,
    this.timeout = const Duration(seconds: 30),
    this.proxy,
    this.enableCache = true,
    this.onDownloadProgress,
    this.logDir = 'test/logs',
    this.verbose = false,
    this.forceReinstall = false,
  }) : capabilities = capabilities ?? _defaultCapabilities(browserName);

  /// Creates a copy of this configuration with the specified overrides.
  BrowserConfig copyWith({
    String? browserName,
    Version? version,
    bool? autoDownload,
    String? seleniumUrl,
    Map<String, dynamic>? capabilities,
    String? baseUrl,
    String? screenshotPath,
    bool? headless,
    Duration? timeout,
    ProxyConfiguration? proxy,
    bool? enableCache,
    BrowserDownloadProgress Function(BrowserDownloadProgress)?
        onDownloadProgress,
  }) {
    return BrowserConfig(
      browserName: browserName ?? this.browserName,
      version: version ?? this.version,
      autoDownload: autoDownload ?? this.autoDownload,
      seleniumUrl: seleniumUrl ?? this.seleniumUrl,
      capabilities: capabilities ?? this.capabilities,
      baseUrl: baseUrl ?? this.baseUrl,
      screenshotPath: screenshotPath ?? this.screenshotPath,
      headless: headless ?? this.headless,
      timeout: timeout ?? this.timeout,
      proxy: proxy ?? this.proxy,
      enableCache: enableCache ?? this.enableCache,
      onDownloadProgress: onDownloadProgress ?? this.onDownloadProgress,
    );
  }
}
