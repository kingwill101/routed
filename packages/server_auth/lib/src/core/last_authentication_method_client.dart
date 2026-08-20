import 'dart:convert';

import 'client.dart';
import 'last_authentication_method.dart';

/// Installs only the typed last-authentication-method read API.
final class AuthLastAuthenticationMethodClientPlugin
    implements AuthClientPlugin<AuthLastAuthenticationMethodClient> {
  const AuthLastAuthenticationMethodClientPlugin();

  @override
  String get id => authLastAuthenticationMethodPluginId;

  @override
  AuthLastAuthenticationMethodClient install(AuthClientPluginContext context) =>
      AuthLastAuthenticationMethodClient(context.transport);
}

/// Typed client for the optional server plugin.
final class AuthLastAuthenticationMethodClient {
  const AuthLastAuthenticationMethodClient(this._transport);

  final AuthClientTransport _transport;

  /// Reads the server projection; the HttpOnly cookie itself is never exposed.
  Future<AuthLastAuthenticationMethodReadResult?> read() async {
    final response = await _transport.request(
      'GET',
      '/last-authentication-method',
    );
    final decoded = jsonDecode(response.body);
    if (decoded == null) return null;
    if (decoded is! Map) {
      throw const FormatException(
        'Invalid last authentication method response',
      );
    }
    return AuthLastAuthenticationMethodReadResult.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}
