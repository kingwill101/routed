import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/session_storage.dart';
import 'browser.dart';

/// Handles asynchronous access to the browser's session storage.
class AsyncSessionStorageHandler implements SessionStorage {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;
  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous session storage handler for the given [browser].
  AsyncSessionStorageHandler(this.browser) : driver = browser.driver;

  /// Gets the value of the session storage item with the specified [key].
  ///
  /// Returns `null` if the key doesn't exist.
  @override
  Future<String?> getSessionStorageItem(String key) async {
    final result = await driver
        .execute('return window.sessionStorage.getItem(arguments[0]);', [key]);
    return result as String?;
  }

  /// Sets the session storage item [key] to the given [value].
  ///
  @override
  Future<void> setSessionStorageItem(String key, String value) async {
    await driver.execute(
        'window.sessionStorage.setItem(arguments[0], arguments[1]);',
        [key, value]);
  }

  /// Removes the session storage item with the specified [key].
  ///
  @override
  Future<void> removeSessionStorageItem(String key) async {
    await driver
        .execute('window.sessionStorage.removeItem(arguments[0]);', [key]);
  }

  /// Clears all items from session storage.
  ///
  @override
  Future<void> clearSessionStorage() async {
    await driver.execute('window.sessionStorage.clear();', []);
  }

  /// Gets all key-value pairs currently stored in session storage.
  ///
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
