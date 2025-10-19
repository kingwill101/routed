import 'package:webdriver/sync_core.dart' show WebDriver;

import '../interfaces/session_storage.dart';
import 'browser.dart';

/// Handles synchronous access to the browser's session storage.
class SyncSessionStorageHandler implements SessionStorage {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;

  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous session storage handler for the given [browser].
  SyncSessionStorageHandler(this.browser) : driver = browser.driver;

  /// Gets the value of the session storage item with the specified [key].
  ///
  /// Returns `null` if the key doesn't exist. This is a blocking operation.
  @override
  String? getSessionStorageItem(String key) {
    final result = driver.execute(
      'return window.sessionStorage.getItem(arguments[0]);',
      [key],
    );
    return result as String?;
  }

  /// Sets the session storage item [key] to the given [value].
  /// This is a blocking operation.
  @override
  void setSessionStorageItem(String key, String value) {
    driver.execute(
      'window.sessionStorage.setItem(arguments[0], arguments[1]);',
      [key, value],
    );
  }

  /// Removes the session storage item with the specified [key].
  /// This is a blocking operation.
  @override
  void removeSessionStorageItem(String key) {
    driver.execute('window.sessionStorage.removeItem(arguments[0]);', [key]);
  }

  /// Clears all items from session storage. This is a blocking operation.
  @override
  void clearSessionStorage() {
    driver.execute('window.sessionStorage.clear();', []);
  }

  /// Gets all key-value pairs currently stored in session storage.
  /// This is a blocking operation.
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
