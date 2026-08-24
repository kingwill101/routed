import 'dart:convert';

import 'client.dart';
import 'plugin.dart';
import 'models.dart';

/// Installs only the phone-number API on an [AuthClient].
final class AuthPhoneNumberClientPlugin
    implements AuthClientPlugin<AuthPhoneNumberClient> {
  /// Creates the phone-number client plugin.
  const AuthPhoneNumberClientPlugin();

  @override
  String get id => 'phone_number';

  @override
  AuthPhoneNumberClient install(AuthClientPluginContext context) =>
      AuthPhoneNumberClient(transport: context.transport);
}

/// Client result returned after a verification code is sent.
final class AuthPhoneNumberClientCodeIssued {
  /// Creates the response returned after a verification code is sent.
  const AuthPhoneNumberClientCodeIssued({required this.expiresAt});

  /// Time at which the issued verification code expires.
  final DateTime expiresAt;
}

/// Client result returned after phone authentication succeeds.
final class AuthPhoneNumberClientSignIn {
  /// Creates a phone-number authentication result.
  const AuthPhoneNumberClientSignIn({
    required this.phoneNumber,
    required this.session,
  });

  /// Canonical phone number authenticated by the server.
  final String phoneNumber;

  /// Session returned by the server.
  final AuthSession session;
}

/// Typed client for an explicitly installed phone-number server plugin.
final class AuthPhoneNumberClient {
  /// Creates a phone-number client using [transport].
  const AuthPhoneNumberClient({required this.transport});

  /// Transport used for phone-number requests.
  final AuthClientTransport transport;

  /// Requests that the server send a verification code.
  Future<AuthPhoneNumberClientCodeIssued> sendCode({
    required String phoneNumber,
  }) async {
    final response = await transport.request(
      'POST',
      const AuthRoutePath('/phone-number/send-code'),
      body: <String, dynamic>{'phoneNumber': phoneNumber},
    );
    final body = _mapBody(response.body);
    final expiresAt = DateTime.tryParse(body['expiresAt']?.toString() ?? '');
    if (body['status'] != 'verification_sent' || expiresAt == null) {
      throw const FormatException('Invalid phone code response');
    }
    return AuthPhoneNumberClientCodeIssued(expiresAt: expiresAt.toUtc());
  }

  /// Verifies a code and returns the resulting authenticated session.
  Future<AuthPhoneNumberClientSignIn> verifyCode({
    required String phoneNumber,
    required String code,
    String? name,
  }) async {
    final response = await transport.request(
      'POST',
      const AuthRoutePath('/phone-number/verify-code'),
      body: <String, dynamic>{
        'phoneNumber': phoneNumber,
        'code': code,
        'name': ?name,
      },
    );
    final body = _mapBody(response.body);
    final rawUser = body['user'];
    if (body['status'] != 'authenticated' || rawUser is! Map) {
      throw const FormatException('Invalid phone verification response');
    }
    final returnedPhone = body['phoneNumber']?.toString();
    final expires = body['expires'] == null
        ? null
        : DateTime.tryParse(body['expires'].toString());
    final strategyName = body['strategy']?.toString();
    final strategy = AuthSessionStrategy.values
        .where((value) => value.name == strategyName)
        .firstOrNull;
    if (returnedPhone == null || returnedPhone.isEmpty) {
      throw const FormatException('Invalid phone verification response');
    }
    return AuthPhoneNumberClientSignIn(
      phoneNumber: returnedPhone,
      session: AuthSession(
        user: AuthUser.fromJson(Map<String, dynamic>.from(rawUser)),
        expiresAt: expires,
        strategy: strategy,
        token: body['token']?.toString(),
      ),
    );
  }

  /// Removes the current phone identity after the server validates its
  /// recent-authentication or step-up policy.
  Future<void> remove() async {
    await transport.mutate(
      'POST',
      const AuthRoutePath('/phone-number/remove'),
      const <String, dynamic>{},
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
