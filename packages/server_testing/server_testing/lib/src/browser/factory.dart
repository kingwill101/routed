import 'package:server_testing/src/browser/browser_config.dart';
import 'package:webdriver/async_core.dart' as async;
import 'package:webdriver/sync_core.dart' as sync;

import 'async/browser.dart';
import 'interfaces/browser.dart';
import 'sync/browser.dart';

/// Creates browser instances with different WebDriver implementations.
///
/// Wraps WebDriver implementations with the unified [Browser] interface,
/// allowing tests to use the same API regardless of the underlying
/// implementation (async or sync).
class BrowserFactory {
  /// Creates a browser instance using the asynchronous WebDriver API.
  ///
  /// The [driver] is the async WebDriver instance to wrap.
  /// Returns a [Browser] using the asynchronous implementation.
  static Browser createAsync(async.WebDriver driver, [BrowserConfig? config]) =>
      AsyncBrowser(driver, config ?? BrowserConfig());

  /// Creates a browser instance using the synchronous WebDriver API.
  ///
  /// The [driver] is the sync WebDriver instance to wrap.
  /// Returns a [Browser] using the synchronous implementation.
  static Browser createSync(sync.WebDriver driver, [BrowserConfig? config]) =>
      SyncBrowser(driver, config ?? BrowserConfig());
}
