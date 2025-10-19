import 'package:webdriver/sync_core.dart' show WebDriver;

import '../interfaces/local_storage.dart';
import 'browser.dart';

/// Handles synchronous access to the browser's local storage.
class SyncLocalStorageHandler implements LocalStorage {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;

  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous local storage handler for the given [browser].
  SyncLocalStorageHandler(this.browser) : driver = browser.driver;

  /// Gets the value of the local storage item with the specified [key].
  ///
  /// Returns `null` if the key doesn't exist. This is a blocking operation.
  @override
  String? getLocalStorageItem(String key) {
    final result = driver.execute(
      'return window.localStorage.getItem(arguments[0]);',
      [key],
    );
    return result as String?;
  }

  /// Sets the local storage item [key] to the given [value].
  /// This is a blocking operation.
  @override
  void setLocalStorageItem(String key, String value) {
    driver.execute('window.localStorage.setItem(arguments[0], arguments[1]);', [
      key,
      value,
    ]);
  }

  /// Removes the local storage item with the specified [key].
  /// This is a blocking operation.
  @override
  void removeLocalStorageItem(String key) {
    driver.execute('window.localStorage.removeItem(arguments[0]);', [key]);
  }

  /// Clears all items from local storage. This is a blocking operation.
  @override
  void clearLocalStorage() {
    driver.execute('window.localStorage.clear();', []);
  }

  /// Gets all key-value pairs currently stored in local storage.
  /// This is a blocking operation.
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
