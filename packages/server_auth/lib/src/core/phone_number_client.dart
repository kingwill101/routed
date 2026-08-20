import 'dart:convert';

import 'client.dart';
import 'plugin.dart';
import 'models.dart';

/// Installs only the phone-number API on an [AuthClient].
final class AuthPhoneNumberClientPlugin
    implements AuthClientPlugin<AuthPhoneNumberClient> {
  const AuthPhoneNumberClientPlugin();

  @override
  String get id => 'phone_number';

  @override
  AuthPhoneNumberClient install(AuthClientPluginContext context) =>
      AuthPhoneNumberClient(transport: context.transport);
}

final class AuthPhoneNumberClientCodeIssued {
  const AuthPhoneNumberClientCodeIssued({required this.expiresAt});

  final DateTime expiresAt;
}

final class AuthPhoneNumberClientSignIn {
  const AuthPhoneNumberClientSignIn({
    required this.phoneNumber,
    required this.session,
  });

  final String phoneNumber;
  final AuthSession session;
}

/// Typed client for an explicitly installed phone-number server plugin.
final class AuthPhoneNumberClient {
  const AuthPhoneNumberClient({required this.transport});

  final AuthClientTransport transport;

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
}

Map<String, dynamic> _mapBody(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Auth response was not a JSON object');
  }
  return Map<String, dynamic>.from(decoded);
}
