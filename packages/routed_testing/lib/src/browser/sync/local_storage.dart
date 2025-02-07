import 'package:webdriver/sync_core.dart' show WebDriver;

import '../interfaces/local_storage.dart';
import 'browser.dart';

class SyncLocalStorageHandler implements LocalStorage {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncLocalStorageHandler(this.browser) : driver = browser.driver;

  @override
  String? getLocalStorageItem(String key) {
    final result = driver
        .execute('return window.localStorage.getItem(arguments[0]);', [key]);
    return result as String?;
  }

  @override
  void setLocalStorageItem(String key, String value) {
    driver.execute('window.localStorage.setItem(arguments[0], arguments[1]);',
        [key, value]);
  }

  @override
  void removeLocalStorageItem(String key) {
    driver.execute('window.localStorage.removeItem(arguments[0]);', [key]);
  }

  @override
  void clearLocalStorage() {
    driver.execute('window.localStorage.clear();', []);
  }

  @override
  Map<String, String> getAllLocalStorageItems() {
    final result = driver.execute('''
      var items = {};
      for (var i = 0; i < window.localStorage.length; i++) {
        var key = window.localStorage.key(i);
        items[key] = window.localStorage.getItem(key);
      }
      return items;
    ''', []);

    if (result is Map) {
      return result.cast<String, String>();
    }

    return {};
  }
}
