import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/cookie.dart' show Cookie, WrappedCookie;
import 'browser.dart';

class AsyncCookieHandler implements Cookie {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncCookieHandler(this.browser) : driver = browser.driver;

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

  @override
  Future<List<WrappedCookie>> getAllCookies() async {
    final cookies = await driver.cookies.all.toList();
    return cookies.cast<WrappedCookie>();
  }

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

  @override
  Future<void> deleteCookie(String name, [String? path, String? domain]) async {
    await driver.cookies.delete(name);
  }

  @override
  Future<void> deleteAllCookies() async {
    await driver.cookies.deleteAll();
  }
}
