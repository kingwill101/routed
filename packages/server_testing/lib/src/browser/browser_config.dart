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

class BrowserConfig {
  final String browserName;
  final Version? version;
  final bool autoDownload;
  final String seleniumUrl;
  final Map<String, dynamic> capabilities;
  final String? baseUrl;
  final String screenshotPath;
  final Duration timeout;
  final ProxyConfiguration? proxy;
  final bool enableCache;
  final BrowserDownloadProgress Function(BrowserDownloadProgress)?
      onDownloadProgress;
  final bool headless;
  final bool forceReinstall;
  final bool verbose;
  final String logDir;
  final bool debug;

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
