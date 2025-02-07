import 'dart:async';

import 'package:webdriver/sync_core.dart' as wd;

class WrappedCookie extends wd.Cookie {
  WrappedCookie(
    super.name,
    super.value, {
    super.path,
    super.domain,
    super.secure,
    super.expiry,
  });
}

abstract class Cookie {
  FutureOr<WrappedCookie?> getCookie(String name);

  FutureOr<List<WrappedCookie>> getAllCookies();

  FutureOr<void> setCookie(String name, String value,
      {String? domain,
      String? path,
      DateTime? expiry,
      bool? secure,
      bool? httpOnly});

  FutureOr<void> deleteCookie(String name);

  FutureOr<void> deleteAllCookies();
}
