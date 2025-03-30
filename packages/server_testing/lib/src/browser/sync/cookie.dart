import 'package:webdriver/sync_core.dart' show WebDriver, Cookie;

import '../interfaces/cookie.dart' as cookie_interface;
import 'browser.dart';

/// Handles synchronous cookie operations for a [SyncBrowser].
class SyncCookieHandler implements cookie_interface.Cookie {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;
  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous cookie handler for the given [browser].
  SyncCookieHandler(this.browser) : driver = browser.driver;

  /// Gets the cookie with the specified [name].
  ///
  /// Returns `null` if the cookie is not found. This is a blocking operation.
  @override
  cookie_interface.WrappedCookie? getCookie(String name) {
    final cookies = driver.cookies.all;
    try {
      return cookies.firstWhere((cookie) => cookie.name == name)
          as cookie_interface.WrappedCookie;
    } catch (e) {
      return null;
    }
  }

  /// Gets all cookies visible to the current page. This is a blocking operation.
  @override
  List<cookie_interface.WrappedCookie> getAllCookies() =>
      driver.cookies.all as List<cookie_interface.WrappedCookie>;

      /// Sets a cookie with the given [name] and [value].
      ///
      /// Optional parameters like [domain], [path], [expiry], and [secure]
      /// can be specified. Note `httpOnly` is not supported for adding cookies
      /// via standard WebDriver. This is a blocking operation.
  @override
  void setCookie(String name, String value,
      {String? domain,
      String? path,
      DateTime? expiry,
      bool? secure,
      bool? httpOnly}) {
    final cookie = Cookie(name, value,
        domain: domain, path: path, expiry: expiry, secure: secure);
    driver.cookies.add(cookie);
  }

  /// Deletes the cookie with the specified [name]. This is a blocking operation.
  @override
  void deleteCookie(String name) {
    driver.cookies.delete(name);
  }

  /// Deletes all cookies visible to the current page. This is a blocking operation.
  @override
  void deleteAllCookies() {
    driver.cookies.deleteAll();
  }
}
