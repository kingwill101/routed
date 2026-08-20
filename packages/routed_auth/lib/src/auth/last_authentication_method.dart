import 'dart:io';

import 'package:routed_core/routed_core.dart' show EngineContext;
import 'package:server_auth/server_auth.dart';

/// Routed host adapter for the server plugin's Secure, HttpOnly cookie.
final class RoutedAuthLastAuthenticationMethodBrowserStore
    implements AuthLastAuthenticationMethodBrowserStore<EngineContext> {
  const RoutedAuthLastAuthenticationMethodBrowserStore();

  @override
  String? readCookie(EngineContext context, String name) =>
      context.cookie(name)?.value;

  @override
  void writeCookie(
    EngineContext context,
    AuthLastAuthenticationMethodCookie cookie,
  ) {
    context.response.setCookie(
      cookie.name,
      cookie.value,
      maxAge: cookie.maxAge,
      path: cookie.path,
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
      sameSite: switch (cookie.sameSite) {
        AuthLastAuthenticationMethodSameSite.lax => SameSite.lax,
        AuthLastAuthenticationMethodSameSite.strict => SameSite.strict,
      },
    );
  }
}
