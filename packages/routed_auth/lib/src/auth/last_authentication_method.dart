import 'dart:io';

import 'package:routed_core/routed_core.dart' show EngineContext;
import 'package:server_auth/server_auth.dart';

/// Routed host adapter for the server plugin's Secure, HttpOnly cookie.
final class RoutedAuthLastAuthenticationMethodBrowserStore
    implements AuthLastAuthenticationMethodBrowserStore<EngineContext> {
  /// Creates the Routed cookie-store adapter.
  const RoutedAuthLastAuthenticationMethodBrowserStore();

  /// Reads only the named request cookie value, or null when it is absent.
  @override
  String? readCookie(EngineContext context, String name) =>
      context.cookie(name)?.value;

  /// Writes the host-owned cookie instructions to the response.
  ///
  /// The adapter preserves [AuthLastAuthenticationMethodCookie] name, value,
  /// lifetime, path, Secure, and HttpOnly settings. It maps server-auth
  /// `lax` and `strict` values to Routed's [SameSite] values.
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
