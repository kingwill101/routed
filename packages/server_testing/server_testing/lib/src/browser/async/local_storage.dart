import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/local_storage.dart';
import 'browser.dart';

/// Handles asynchronous access to the browser's local storage.
class AsyncLocalStorageHandler implements LocalStorage {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;

  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous local storage handler for the given [browser].
  AsyncLocalStorageHandler(this.browser) : driver = browser.driver;

  /// Gets the value of the local storage item with the specified [key].
  ///
  /// Returns `null` if the key doesn't exist.
  @override
  Future<String?> getLocalStorageItem(String key) async {
    final result = await driver.execute(
      'return window.localStorage.getItem(arguments[0]);',
      [key],
    );
    return result as String?;
  }

  /// Sets the local storage item [key] to the given [value].
  ///
  @override
  Future<void> setLocalStorageItem(String key, String value) async {
    await driver.execute(
      'window.localStorage.setItem(arguments[0], arguments[1]);',
      [key, value],
    );
  }

  /// Removes the local storage item with the specified [key].
  ///
  @override
  Future<void> removeLocalStorageItem(String key) async {
    await driver.execute('window.localStorage.removeItem(arguments[0]);', [
      key,
    ]);
  }

  /// Clears all items from local storage.
  ///
  @override
  Future<void> clearLocalStorage() async {
    await driver.execute('window.localStorage.clear();', []);
  }

  /// Gets all key-value pairs currently stored in local storage.
  ///
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
