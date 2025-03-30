import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/cookie.dart' show Cookie, WrappedCookie;
import 'browser.dart';

/// Handles asynchronous cookie operations for an [AsyncBrowser].
class AsyncCookieHandler implements Cookie {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;
  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous cookie handler for the given [browser].
  AsyncCookieHandler(this.browser) : driver = browser.driver;

  /// Gets the cookie with the specified [name].
  ///
  /// Returns `null` if the cookie is not found.
  @override
  Future<WrappedCookie?> getCookie(String name) async {
    final cookies = await driver.cookies.all.toList();
    try {
      return cookies.firstWhere((cookie) => cookie.name == name)
          as WrappedCookie;
    } catch (e) {
      return null;
    }
  }

  /// Gets all cookies visible to the current page.
  ///
  @override
  Future<List<WrappedCookie>> getAllCookies() async {
    final cookies = await driver.cookies.all.toList();
    return cookies.cast<WrappedCookie>();
  }

  /// Sets a cookie with the given [name] and [value].
  ///
  /// Optional parameters like [domain], [path], [expiry], and [secure]
  /// can be specified to control the cookie's properties. Note that
  /// `httpOnly` is not directly supported by the standard WebDriver protocol
  /// for adding cookies.
  @override
  Future<void> setCookie(String name, String value,
      {String? domain,
      String? path,
      DateTime? expiry,
      bool? secure,
      bool? httpOnly}) async {
    final cookie = WrappedCookie(
      name,
      value,
      domain: domain,
      path: path,
      expiry: expiry,
      secure: secure,
    );
    await driver.cookies.add(cookie);
  }

  /// Deletes the cookie with the specified [name].
  ///
  /// Note: The standard WebDriver protocol for deleting cookies primarily uses
  /// the cookie name. While [path] and [domain] parameters are included for
  /// potential future use or specific driver extensions, they might be ignored
  /// by the underlying WebDriver implementation.
  @override
  Future<void> deleteCookie(String name, [String? path, String? domain]) async {
    await driver.cookies.delete(name);
  }

  /// Deletes all cookies visible to the current page.
  ///
  @override
  Future<void> deleteAllCookies() async {
    await driver.cookies.deleteAll();
  }
}
