import 'package:webdriver/sync_core.dart' show WebDriver;

import '../interfaces/session_storage.dart';
import 'browser.dart';

class SyncSessionStorageHandler implements SessionStorage {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncSessionStorageHandler(this.browser) : driver = browser.driver;

  @override
  String? getSessionStorageItem(String key) {
    final result = driver
        .execute('return window.sessionStorage.getItem(arguments[0]);', [key]);
    return result as String?;
  }

  @override
  void setSessionStorageItem(String key, String value) {
    driver.execute('window.sessionStorage.setItem(arguments[0], arguments[1]);',
        [key, value]);
  }

  @override
  void removeSessionStorageItem(String key) {
    driver.execute('window.sessionStorage.removeItem(arguments[0]);', [key]);
  }

  @override
  void clearSessionStorage() {
    driver.execute('window.sessionStorage.clear();', []);
  }

  @override
  Map<String, String> getAllSessionStorageItems() {
    final result = driver.execute('''
      var items = {};
      for (var i = 0; i < window.sessionStorage.length; i++) {
        var key = window.sessionStorage.key(i);
        items[key] = window.sessionStorage.getItem(key);
      }
      return items;
    ''', []);

    if (result is Map) {
      return result.cast<String, String>();
    }

    return {};
  }
}
