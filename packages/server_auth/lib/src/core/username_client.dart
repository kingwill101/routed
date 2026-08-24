import 'dart:convert';

import 'client.dart';
import 'plugin.dart';
import 'models.dart';

/// Installs only the username-first API on an [AuthClient].
final class AuthUsernameClientPlugin
    implements AuthClientPlugin<AuthUsernameClient> {
  /// Creates the username client plugin.
  const AuthUsernameClientPlugin();

  @override
  String get id => 'username';

  @override
  AuthUsernameClient install(AuthClientPluginContext context) =>
      AuthUsernameClient(transport: context.transport);
}

/// Client result returned after username authentication succeeds.
final class AuthUsernameClientAuthentication {
  /// Creates a username authentication result.
  const AuthUsernameClientAuthentication({
    required this.username,
    required this.session,
  });

  /// Canonical username authenticated by the server.
  final String username;

  /// Session returned by the server.
  final AuthSession session;
}

/// Client result returned after a username change.
final class AuthUsernameClientChange {
  /// Creates a username-change result.
  const AuthUsernameClientChange({
    required this.username,
    required this.user,
    required this.changed,
  });

  /// Canonical username returned by the server.
  final String username;

  /// User whose username was evaluated.
  final AuthUser user;

  /// Whether the username changed rather than already matching.
  final bool changed;
}

/// Typed client for an explicitly installed username server plugin.
final class AuthUsernameClient {
  /// Creates a username client using [transport].
  const AuthUsernameClient({required this.transport});

  /// Transport used for username requests.
  final AuthClientTransport transport;

  /// Registers a username and password, optionally with an email address.
  Future<AuthUsernameClientAuthentication> register({
    required String username,
    required String password,
    String? email,
    String? captchaToken,
  }) => _authenticate(
    const AuthRoutePath('/username/register'),
    <String, dynamic>{
      'username': username,
      'email': ?email,
      'password': password,
      'captchaToken': ?captchaToken,
    },
  );

  /// Authenticates with a username or other supported identifier.
  Future<AuthUsernameClientAuthentication> signIn({
    required String identifier,
    required String password,
    String? captchaToken,
  }) =>
      _authenticate(const AuthRoutePath('/username/sign-in'), <String, dynamic>{
        'identifier': identifier,
        'password': password,
        'captchaToken': ?captchaToken,
      });

  /// Changes the username for the current authenticated user.
  Future<AuthUsernameClientChange> change({required String username}) async {
    final response = await transport.request(
      'POST',
      const AuthRoutePath('/username/change'),
      body: <String, dynamic>{'username': username},
    );
    final body = _mapBody(response.body);
    final status = body['status'];
    final user = body['user'];
    final canonical = body['username'];
    if ((status != 'username_changed' && status != 'username_unchanged') ||
        canonical is! String ||
        canonical.isEmpty ||
        user is! Map) {
      throw const FormatException('Invalid username change response');
    }
    return AuthUsernameClientChange(
      username: canonical,
      user: AuthUser.fromJson(Map<String, dynamic>.from(user)),
      changed: status == 'username_changed',
    );
  }

  /// Removes the current user's username credential.
  Future<void> remove() async {
    final response = await transport.request(
      'POST',
      const AuthRoutePath('/username/remove'),
      body: const <String, dynamic>{},
    );
    if (_mapBody(response.body)['status'] != 'username_removed') {
      throw const FormatException('Invalid username removal response');
    }
  }

  Future<AuthUsernameClientAuthentication> _authenticate(
    AuthRoutePath path,
    Map<String, dynamic> request,
  ) async {
    final response = await transport.request('POST', path, body: request);
    final body = _mapBody(response.body);
    if (body['status'] == 'two_factor_required') {
      final expiresAt = DateTime.tryParse(body['expiresAt']?.toString() ?? '');
      final challengeToken = body['challengeToken']?.toString() ?? '';
      if (expiresAt == null || challengeToken.isEmpty) {
        throw const FormatException('Invalid two-factor challenge response');
      }
      throw AuthClientTwoFactorRequiredException(
        challengeToken: challengeToken,
        expiresAt: expiresAt.toUtc(),
      );
    }
    final user = body['user'];
    final username = body['username'];
    if (body['status'] != 'authenticated' ||
        username is! String ||
        username.isEmpty ||
        user is! Map) {
      throw const FormatException('Invalid username authentication response');
    }
    final expires = body['expires'] == null
        ? null
        : DateTime.tryParse(body['expires'].toString());
    final strategyName = body['strategy']?.toString();
    final strategy = AuthSessionStrategy.values
        .where((value) => value.name == strategyName)
        .firstOrNull;
    return AuthUsernameClientAuthentication(
      username: username,
      session: AuthSession(
        user: AuthUser.fromJson(Map<String, dynamic>.from(user)),
        expiresAt: expires?.toUtc(),
        strategy: strategy,
        token: body['token']?.toString(),
      ),
    );
  }
}

Map<String, dynamic> _mapBody(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Auth response was not a JSON object');
  }
  return Map<String, dynamic>.from(decoded);
}
