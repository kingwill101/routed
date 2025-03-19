import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/local_storage.dart';
import 'browser.dart';

class AsyncLocalStorageHandler implements LocalStorage {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncLocalStorageHandler(this.browser) : driver = browser.driver;

  @override
  Future<String?> getLocalStorageItem(String key) async {
    final result = await driver
        .execute('return window.localStorage.getItem(arguments[0]);', [key]);
    return result as String?;
  }

  @override
  Future<void> setLocalStorageItem(String key, String value) async {
    await driver.execute(
        'window.localStorage.setItem(arguments[0], arguments[1]);',
        [key, value]);
  }

  @override
  Future<void> removeLocalStorageItem(String key) async {
    await driver
        .execute('window.localStorage.removeItem(arguments[0]);', [key]);
  }

  @override
  Future<void> clearLocalStorage() async {
    await driver.execute('window.localStorage.clear();', []);
  }

  @override
  Future<Map<String, String>> getAllLocalStorageItems() async {
    final result = await driver.execute('''
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
