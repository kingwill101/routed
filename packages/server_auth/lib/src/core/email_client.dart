import 'dart:convert';

import 'client.dart';
import 'plugin.dart';
import 'email_otp_store.dart';
import 'models.dart';
import 'magic_link.dart' show MagicLinkPlugin;

/// Installs the email magic-link API on an [AuthClient].
///
/// The server must configure a [MagicLinkPlugin] with the matching provider
/// ID. This client plugin does not enable email authentication by itself.
final class AuthMagicLinkClientPlugin
    implements AuthClientPlugin<AuthMagicLinkClient> {
  const AuthMagicLinkClientPlugin({this.provider = 'email'});

  final String provider;

  @override
  String get id => 'magic_link:$provider';

  @override
  AuthMagicLinkClient install(AuthClientPluginContext context) {
    return AuthMagicLinkClient(
      transport: context.transport,
      provider: provider,
    );
  }
}

/// Typed client for email magic-link authentication.
final class AuthMagicLinkClient {
  AuthMagicLinkClient({required this.transport, this.provider = 'email'}) {
    _validateProvider(provider);
  }

  final AuthClientTransport transport;
  final String provider;

  /// Requests a one-time sign-in link for [email].
  Future<AuthClientVerificationSent> send({
    required String email,
    String? callbackUrl,
  }) async {
    final response = await transport.mutate(
      'POST',
      authSignInProviderRoute,
      {'email': email, 'callbackUrl': ?callbackUrl},
      pathParameters: <AuthRouteParameterKey, String>{
        authProviderRouteParameter: _providerPath,
      },
    );
    final body = _mapBody(response.body);
    return AuthClientVerificationSent(
      email: body['email']?.toString() ?? email,
    );
  }

  /// Verifies [token] and returns the session or server redirect.
  Future<AuthClientAuthResult> verify({
    required String email,
    required String token,
  }) async {
    final response = await transport.request(
      'GET',
      authCallbackProviderRoute,
      pathParameters: <AuthRouteParameterKey, String>{
        authProviderRouteParameter: _providerPath,
      },
      queryParameters: {'email': email, 'token': token},
      followRedirects: false,
    );
    return _authResult(response);
  }

  String get _providerPath => _pathSegment(provider);
}

/// Installs the email OTP API on an [AuthClient].
final class AuthEmailOtpClientPlugin
    implements AuthClientPlugin<AuthEmailOtpClient> {
  const AuthEmailOtpClientPlugin();

  @override
  String get id => 'email_otp';

  @override
  AuthEmailOtpClient install(AuthClientPluginContext context) {
    return AuthEmailOtpClient(transport: context.transport);
  }
}

/// Typed client for the optional email OTP server plugin.
final class AuthEmailOtpClient {
  const AuthEmailOtpClient({required this.transport});

  final AuthClientTransport transport;

  Future<void> sendVerificationOtp({
    required String email,
    required AuthEmailOtpType type,
  }) async {
    await transport.request(
      'POST',
      const AuthRoutePath('/email-otp/send-verification-otp'),
      body: {'email': email, 'type': _emailOtpTypeName(type)},
    );
  }

  Future<void> checkVerificationOtp({
    required String email,
    required AuthEmailOtpType type,
    required String otp,
  }) async {
    await transport.request(
      'POST',
      const AuthRoutePath('/email-otp/check-verification-otp'),
      body: {'email': email, 'type': _emailOtpTypeName(type), 'otp': otp},
    );
  }

  Future<AuthSession> signIn({
    required String email,
    required String otp,
    String? name,
    String? image,
  }) async {
    final response = await transport.request(
      'POST',
      const AuthRoutePath('/sign-in/email-otp'),
      body: {'email': email, 'otp': otp, 'name': ?name, 'image': ?image},
    );
    return _sessionFromBody(response.body);
  }

  Future<AuthUser> verifyEmail({required String otp}) async {
    final response = await transport.mutate(
      'POST',
      const AuthRoutePath('/email-otp/verify-email'),
      {'otp': otp},
    );
    final user = _mapBody(response.body)['user'];
    if (user is! Map) {
      throw const FormatException('Invalid email OTP response');
    }
    return AuthUser.fromJson(Map<String, dynamic>.from(user));
  }
}

String _emailOtpTypeName(AuthEmailOtpType type) => switch (type) {
  AuthEmailOtpType.signIn => 'sign-in',
  AuthEmailOtpType.emailVerification => 'email-verification',
  AuthEmailOtpType.forgetPassword => 'forget-password',
  AuthEmailOtpType.changeEmail => 'change-email',
};

AuthClientAuthResult _authResult(AuthClientResponse response) {
  final location = response.headers['location'];
  if (location != null && location.trim().isNotEmpty) {
    return AuthClientAuthResult(redirectUrl: Uri.parse(location));
  }
  final body = _mapBody(response.body);
  return AuthClientAuthResult(
    session: _sessionFromMapOrNull(body),
    status: body['status']?.toString(),
    email: body['email']?.toString(),
  );
}

AuthSession _sessionFromBody(String body) {
  final session = _sessionFromMapOrNull(_mapBody(body));
  if (session == null) {
    throw const FormatException('Auth response did not contain a session');
  }
  return session;
}

AuthSession? _sessionFromMapOrNull(Map<String, dynamic> body) {
  final rawUser = body['user'];
  if (rawUser is! Map) return null;
  final strategyName = body['strategy']?.toString();
  final strategy = AuthSessionStrategy.values
      .where((value) => value.name == strategyName)
      .firstOrNull;
  return AuthSession(
    user: AuthUser.fromJson(Map<String, dynamic>.from(rawUser)),
    expiresAt: body['expires'] == null
        ? null
        : DateTime.tryParse(body['expires'].toString()),
    strategy: strategy,
    token: body['token']?.toString(),
  );
}

Map<String, dynamic> _mapBody(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Auth response was not a JSON object');
  }
  return Map<String, dynamic>.from(decoded);
}

String _pathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'provider', 'must not be empty');
  }
  return trimmed;
}

void _validateProvider(String provider) {
  _pathSegment(provider);
}
