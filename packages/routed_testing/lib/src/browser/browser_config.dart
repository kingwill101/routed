import 'package:routed_testing/src/browser/bootstrap/browser_manager.dart';
import 'package:routed_testing/src/browser/bootstrap/progress.dart';
import 'package:routed_testing/src/browser/bootstrap/proxy.dart';
import 'package:routed_testing/src/browser/bootstrap/version.dart';

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

  BrowserConfig({
    this.browserName = 'chrome',
    this.version,
    this.autoDownload = true,
    this.seleniumUrl = 'http://localhost:4444/wd/hub',
    Map<String, dynamic>? capabilities,
    this.baseUrl,
    this.screenshotPath = 'test/screenshots',
    this.timeout = const Duration(seconds: 30),
    this.proxy,
    this.enableCache = true,
    this.onDownloadProgress,
  }) : capabilities = capabilities ?? _defaultCapabilities(browserName);

  static Map<String, dynamic> _defaultCapabilities(String browserName) {
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
}
