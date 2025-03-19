import 'package:server_testing/src/browser/browser_config.dart';
import 'package:webdriver/async_core.dart' as async;
import 'package:webdriver/sync_core.dart' as sync;

import 'async/browser.dart';
import 'interfaces/browser.dart';
import 'sync/browser.dart';

class BrowserFactory {
  static Browser createAsync(async.WebDriver driver, [BrowserConfig? config]) =>
      AsyncBrowser(driver, config ?? BrowserConfig());

  static Browser createSync(sync.WebDriver driver, [BrowserConfig? config]) =>
      SyncBrowser(driver, config ?? BrowserConfig());
}
