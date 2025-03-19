import 'package:webdriver/sync_core.dart' show WebDriver, Cookie;

import '../interfaces/cookie.dart' as cookie_interface;
import 'browser.dart';

class SyncCookieHandler implements cookie_interface.Cookie {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncCookieHandler(this.browser) : driver = browser.driver;

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

  @override
  List<cookie_interface.WrappedCookie> getAllCookies() =>
      driver.cookies.all as List<cookie_interface.WrappedCookie>;

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

  @override
  void deleteCookie(String name) {
    driver.cookies.delete(name);
  }

  @override
  void deleteAllCookies() {
    driver.cookies.deleteAll();
  }
}
