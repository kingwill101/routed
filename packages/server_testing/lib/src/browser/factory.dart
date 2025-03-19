import 'package:server_testing/src/browser/browser_config.dart';
import 'package:webdriver/async_core.dart' as async;
import 'package:webdriver/sync_core.dart' as sync;

import 'async/browser.dart';
import 'interfaces/browser.dart';
import 'sync/browser.dart';

/// Factory for creating browser instances with different WebDriver implementations.
///
/// This class creates [Browser] instances that wrap WebDriver implementations,
/// providing a unified API whether using the async or synchronous WebDriver API.
class BrowserFactory {
  /// Creates a browser instance using the asynchronous WebDriver API.
  ///
  /// [driver] is the async WebDriver instance to wrap.
  /// [config] is an optional browser configuration.
  ///
  /// Returns a [Browser] that uses the asynchronous WebDriver implementation.
  static Browser createAsync(async.WebDriver driver, [BrowserConfig? config]) =>
      AsyncBrowser(driver, config ?? BrowserConfig());

  /// Creates a browser instance using the synchronous WebDriver API.
  ///
  /// [driver] is the sync WebDriver instance to wrap.
  /// [config] is an optional browser configuration.
  ///
  /// Returns a [Browser] that uses the synchronous WebDriver implementation.
  static Browser createSync(sync.WebDriver driver, [BrowserConfig? config]) =>
      SyncBrowser(driver, config ?? BrowserConfig());
}
