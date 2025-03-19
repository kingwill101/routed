import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/session_storage.dart';
import 'browser.dart';

class AsyncSessionStorageHandler implements SessionStorage {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncSessionStorageHandler(this.browser) : driver = browser.driver;

  @override
  Future<String?> getSessionStorageItem(String key) async {
    final result = await driver
        .execute('return window.sessionStorage.getItem(arguments[0]);', [key]);
    return result as String?;
  }

  @override
  Future<void> setSessionStorageItem(String key, String value) async {
    await driver.execute(
        'window.sessionStorage.setItem(arguments[0], arguments[1]);',
        [key, value]);
  }

  @override
  Future<void> removeSessionStorageItem(String key) async {
    await driver
        .execute('window.sessionStorage.removeItem(arguments[0]);', [key]);
  }

  @override
  Future<void> clearSessionStorage() async {
    await driver.execute('window.sessionStorage.clear();', []);
  }

  @override
  Future<Map<String, String>> getAllSessionStorageItems() async {
    final result = await driver.execute('''
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
