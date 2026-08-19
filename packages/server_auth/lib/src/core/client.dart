import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'models.dart';

/// A cookie received from an auth response.
///
/// The client stores the name and value, plus the transport attribute needed
/// to enforce `Secure`. Other attributes such as `HttpOnly`, `Path`, and
/// `SameSite` are server instructions and are not sent back as request data.
class AuthClientCookie {
  const AuthClientCookie({
    required this.name,
    required this.value,
    this.expires,
    this.maxAge,
    this.secure = false,
  });

  final String name;
  final String value;
  final DateTime? expires;
  final int? maxAge;
  final bool secure;

  bool get isDeletion =>
      (maxAge != null && maxAge! <= 0) ||
      (expires != null && !expires!.isAfter(DateTime.now()));

  /// Parses the first cookie in a `Set-Cookie` header.
  factory AuthClientCookie.fromSetCookie(String header) {
    final attributes = header.split(';');
    final first = attributes.first.trim();
    final separator = first.indexOf('=');
    if (separator <= 0) {
      throw FormatException('Invalid Set-Cookie header');
    }

    final name = first.substring(0, separator).trim();
    final value = first.substring(separator + 1).trim();
    DateTime? expires;
    int? maxAge;
    var secure = false;

    for (final rawAttribute in attributes.skip(1)) {
      final attribute = rawAttribute.trim();
      final equals = attribute.indexOf('=');
      final key = (equals < 0 ? attribute : attribute.substring(0, equals))
          .trim()
          .toLowerCase();
      final rawValue = equals < 0 ? '' : attribute.substring(equals + 1).trim();
      if (key == 'max-age') {
        maxAge = int.tryParse(rawValue);
      } else if (key == 'expires') {
        try {
          expires = parseHttpDate(rawValue);
        } on FormatException {
          // Ignore an invalid expiry; the cookie value remains usable for the
          // current process, but no invalid date controls deletion.
        }
      } else if (key == 'secure') {
        secure = true;
      }
    }

    return AuthClientCookie(
      name: name,
      value: value,
      expires: expires,
      maxAge: maxAge,
      secure: secure,
    );
  }
}

/// Stores cookies for an [AuthClient] instance.
///
/// Applications can provide a persistent implementation for mobile or desktop
/// clients. The default [InMemoryAuthClientCookieStore] is useful for tests and
/// short-lived clients. It does not write cookies to disk.
abstract interface class AuthClientCookieStore {
  FutureOr<Iterable<AuthClientCookie>> load();

  FutureOr<void> save(AuthClientCookie cookie);
}

/// A process-local cookie store for tests and short-lived clients.
class InMemoryAuthClientCookieStore implements AuthClientCookieStore {
  final Map<String, AuthClientCookie> _cookies = <String, AuthClientCookie>{};

  @override
  Iterable<AuthClientCookie> load() =>
      List<AuthClientCookie>.unmodifiable(_cookies.values);

  @override
  void save(AuthClientCookie cookie) {
    if (cookie.isDeletion) {
      _cookies.remove(cookie.name);
    } else {
      _cookies[cookie.name] = cookie;
    }
  }
}

/// Public provider metadata returned by `/auth/providers`.
class AuthClientProvider {
  const AuthClientProvider({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;
  final String type;

  factory AuthClientProvider.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final type = json['type']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty || type.isEmpty) {
      throw const FormatException('Invalid auth provider response');
    }
    return AuthClientProvider(id: id, name: name, type: type);
  }
}

/// The result of an auth callback that may return a session or redirect.
class AuthClientAuthResult {
  const AuthClientAuthResult({
    this.session,
    this.redirectUrl,
    this.status,
    this.email,
  });

  final AuthSession? session;
  final Uri? redirectUrl;
  final String? status;
  final String? email;
}

/// A successful email sign-in request.
class AuthClientVerificationSent {
  const AuthClientVerificationSent({required this.email});

  final String email;
}

/// A server-side session returned by the session-management API.
class AuthClientSession {
  const AuthClientSession({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.authenticationMethod,
    required this.isCurrent,
    required this.active,
    this.revokedAt,
    this.ipAddress,
    this.userAgent,
  });

  final String id;
  final String userId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime lastUsedAt;
  final DateTime? revokedAt;
  final String? ipAddress;
  final String? userAgent;
  final String authenticationMethod;
  final bool isCurrent;
  final bool active;

  factory AuthClientSession.fromJson(Map<String, dynamic> json) {
    return AuthClientSession(
      id: _requiredString(json, 'id'),
      userId: _requiredString(json, 'userId'),
      createdAt: _requiredDate(json, 'createdAt'),
      expiresAt: _requiredDate(json, 'expiresAt'),
      lastUsedAt: _requiredDate(json, 'lastUsedAt'),
      revokedAt: _optionalDate(json, 'revokedAt'),
      ipAddress: json['ipAddress']?.toString(),
      userAgent: json['userAgent']?.toString(),
      authenticationMethod: _requiredString(json, 'authenticationMethod'),
      isCurrent: json['isCurrent'] == true,
      active: json['active'] == true,
    );
  }
}

/// TOTP enrollment data returned by a two-factor feature.
class AuthClientTwoFactorEnrollment {
  const AuthClientTwoFactorEnrollment({
    required this.secret,
    required this.otpauthUri,
    required this.expiresAt,
  });

  final String secret;
  final Uri otpauthUri;
  final DateTime expiresAt;

  factory AuthClientTwoFactorEnrollment.fromJson(Map<String, dynamic> json) {
    final secret = _requiredString(json, 'secret');
    final rawUri = _requiredString(json, 'otpauthUri');
    final uri = Uri.tryParse(rawUri);
    if (uri == null || uri.scheme != 'otpauth') {
      throw const FormatException('Invalid two-factor enrollment URI');
    }
    return AuthClientTwoFactorEnrollment(
      secret: secret,
      otpauthUri: uri,
      expiresAt: _requiredDate(json, 'expiresAt'),
    );
  }
}

/// Recovery codes returned after two-factor activation or regeneration.
class AuthClientTwoFactorRecoveryCodes {
  const AuthClientTwoFactorRecoveryCodes(this.codes);

  final List<String> codes;

  factory AuthClientTwoFactorRecoveryCodes.fromJson(Map<String, dynamic> json) {
    final values = json['recoveryCodes'];
    if (values is! List || values.any((value) => value is! String)) {
      throw const FormatException('Invalid two-factor recovery codes');
    }
    return AuthClientTwoFactorRecoveryCodes(
      List<String>.unmodifiable(values.cast<String>()),
    );
  }
}

/// Result of completing a recent step-up verification.
class AuthClientTwoFactorStepUp {
  const AuthClientTwoFactorStepUp({required this.expiresAt});

  factory AuthClientTwoFactorStepUp.fromJson(Map<String, dynamic> json) {
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (json['verified'] != true || expiresAt == null) {
      throw const FormatException('Invalid two-factor step-up response');
    }
    return AuthClientTwoFactorStepUp(expiresAt: expiresAt.toUtc());
  }

  final DateTime expiresAt;
}

/// Public two-factor status returned by the auth server.
class AuthClientTwoFactorStatus {
  const AuthClientTwoFactorStatus({
    required this.enabled,
    required this.recoveryCodesRemaining,
    this.enrollmentExpiresAt,
    this.lockedUntil,
  });

  final bool enabled;
  final int recoveryCodesRemaining;
  final DateTime? enrollmentExpiresAt;
  final DateTime? lockedUntil;

  factory AuthClientTwoFactorStatus.fromJson(Map<String, dynamic> json) {
    final remaining = json['recoveryCodesRemaining'];
    final count = remaining is int ? remaining : int.tryParse('$remaining');
    if (count == null || count < 0) {
      throw const FormatException('Invalid two-factor recovery code count');
    }
    return AuthClientTwoFactorStatus(
      enabled: json['enabled'] == true,
      recoveryCodesRemaining: count,
      enrollmentExpiresAt: _optionalDate(json, 'enrollmentExpiresAt'),
      lockedUntil: _optionalDate(json, 'lockedUntil'),
    );
  }
}

/// An error returned by an auth endpoint.
class AuthClientException implements Exception {
  const AuthClientException({
    required this.statusCode,
    required this.code,
    this.retryAfter,
    this.message,
  });

  final int statusCode;
  final String code;
  final Duration? retryAfter;
  final String? message;

  @override
  String toString() {
    final suffix = message == null ? '' : ': $message';
    return 'AuthClientException($statusCode, $code$suffix)';
  }
}

/// Indicates that credentials were valid but a TOTP challenge is required.
class AuthClientTwoFactorRequiredException extends AuthClientException {
  AuthClientTwoFactorRequiredException({
    required this.challengeToken,
    required this.expiresAt,
  }) : super(statusCode: 202, code: 'two_factor_required');

  final String challengeToken;
  final DateTime expiresAt;
}

/// Typed Dart client for the framework-independent auth HTTP contract.
///
/// The client owns route names, JSON shapes, CSRF presentation, and response
/// parsing. It does not choose how cookies are persisted; provide an
/// [AuthClientCookieStore] when cookies must survive process restarts.
class AuthClient {
  AuthClient({
    required Uri baseUrl,
    String basePath = '/auth',
    http.Client? httpClient,
    AuthClientCookieStore? cookieStore,
    this.timeout = const Duration(seconds: 15),
    Map<String, String>? headers,
    String? bearerToken,
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _basePath = _normalizePath(basePath),
       _httpClient = httpClient ?? http.Client(),
       cookieStore = cookieStore ?? InMemoryAuthClientCookieStore(),
       _bearerToken = bearerToken {
    _headers = Map<String, String>.unmodifiable(headers ?? const {});
  }

  final Uri _baseUrl;
  final String _basePath;
  final http.Client _httpClient;
  final AuthClientCookieStore cookieStore;
  final Duration timeout;
  late final Map<String, String> _headers;
  String? _bearerToken;
  String? _csrfToken;

  /// Replaces the bearer token used for JWT-based auth requests.
  void setBearerToken(String? token) {
    _bearerToken = token?.trim().isEmpty == true ? null : token?.trim();
  }

  /// Clears the cached CSRF token so the next state-changing request refreshes
  /// it from the server.
  void clearCsrfToken() {
    _csrfToken = null;
  }

  /// Lists the providers exposed by the auth server.
  Future<List<AuthClientProvider>> getProviders() async {
    final response = await _request('GET', '/providers');
    final body = _mapBody(response.body);
    final providers = body['providers'];
    if (providers is! List) {
      throw const FormatException('Invalid auth providers response');
    }
    return providers
        .map((provider) {
          if (provider is! Map) {
            throw const FormatException('Invalid auth provider response');
          }
          return AuthClientProvider.fromJson(
            Map<String, dynamic>.from(provider),
          );
        })
        .toList(growable: false);
  }

  /// Obtains and caches the CSRF token used by state-changing requests.
  Future<String> getCsrfToken() async {
    final response = await _request('GET', '/csrf');
    final token = _mapBody(response.body)['csrfToken']?.toString().trim() ?? '';
    if (token.isEmpty) {
      throw const FormatException('Invalid auth CSRF response');
    }
    _csrfToken = token;
    return token;
  }

  /// Returns the current session, or `null` when the client is signed out.
  Future<AuthSession?> getSession() async {
    final response = await _request('GET', '/session');
    if (response.body.trim() == 'null') return null;
    return _sessionFromBody(response.body);
  }

  /// Lists active server-side sessions for the current user.
  Future<List<AuthClientSession>> getSessions() async {
    final response = await _request('GET', '/sessions');
    final sessions = _mapBody(response.body)['sessions'];
    if (sessions is! List) {
      throw const FormatException('Invalid auth sessions response');
    }
    return sessions
        .map((session) {
          if (session is! Map) {
            throw const FormatException('Invalid auth session response');
          }
          return AuthClientSession.fromJson(Map<String, dynamic>.from(session));
        })
        .toList(growable: false);
  }

  /// Returns the current two-factor status for the signed-in user.
  Future<AuthClientTwoFactorStatus> getTwoFactorStatus() async {
    final response = await _request('GET', '/2fa/status');
    return AuthClientTwoFactorStatus.fromJson(_mapBody(response.body));
  }

  /// Starts TOTP enrollment for the signed-in user.
  Future<AuthClientTwoFactorEnrollment> beginTwoFactorEnrollment({
    String? accountLabel,
  }) async {
    final response = await _mutatingRequest('POST', '/2fa/enroll', {
      if (accountLabel != null) 'accountLabel': accountLabel,
    });
    return AuthClientTwoFactorEnrollment.fromJson(_mapBody(response.body));
  }

  /// Verifies the first TOTP code and activates the factor.
  Future<AuthClientTwoFactorRecoveryCodes> verifyTwoFactorEnrollment({
    required String code,
  }) async {
    final response = await _mutatingRequest('POST', '/2fa/enroll/verify', {
      'code': code,
    });
    return AuthClientTwoFactorRecoveryCodes.fromJson(_mapBody(response.body));
  }

  /// Verifies an enabled TOTP code.
  Future<void> verifyTwoFactor({required String code}) async {
    await _mutatingRequest('POST', '/2fa/verify', {'code': code});
  }

  /// Completes a pending credential sign-in with a TOTP code.
  Future<AuthSession> verifyTwoFactorChallenge({
    required String challengeToken,
    required String code,
    bool trustDevice = false,
  }) async {
    final response = await _mutatingRequest('POST', '/2fa/challenge/verify', {
      'challengeToken': challengeToken,
      'code': code,
      'trustDevice': trustDevice,
    });
    return _sessionFromBody(response.body);
  }

  /// Completes a pending credential sign-in with a one-time recovery code.
  Future<AuthSession> verifyTwoFactorRecoveryChallenge({
    required String challengeToken,
    required String recoveryCode,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      '/2fa/challenge/recovery-code',
      {'challengeToken': challengeToken, 'recoveryCode': recoveryCode},
    );
    return _sessionFromBody(response.body);
  }

  /// Revokes all trusted two-factor devices for the current session.
  Future<void> revokeTwoFactorTrustedDevices() async {
    await _mutatingRequest('POST', '/2fa/trusted-devices/revoke', const {});
  }

  /// Verifies TOTP for a sensitive action and stores the short-lived proof.
  Future<AuthClientTwoFactorStepUp> verifyTwoFactorStepUp({
    required String code,
  }) async {
    final response = await _mutatingRequest('POST', '/2fa/step-up', {
      'code': code,
    });
    return AuthClientTwoFactorStepUp.fromJson(_mapBody(response.body));
  }

  /// Revokes the current session's step-up proof.
  Future<void> revokeTwoFactorStepUp() async {
    await _mutatingRequest('POST', '/2fa/step-up/revoke', const {});
  }

  /// Consumes one recovery code.
  Future<void> useTwoFactorRecoveryCode({required String code}) async {
    await _mutatingRequest('POST', '/2fa/recovery-code', {
      'recoveryCode': code,
    });
  }

  /// Replaces all recovery codes after verifying the current TOTP code.
  Future<AuthClientTwoFactorRecoveryCodes> regenerateTwoFactorRecoveryCodes({
    required String code,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      '/2fa/recovery-codes/regenerate',
      {'code': code},
    );
    return AuthClientTwoFactorRecoveryCodes.fromJson(_mapBody(response.body));
  }

  /// Disables two-factor authentication after verifying the current TOTP code.
  Future<void> disableTwoFactor({required String code}) async {
    await _mutatingRequest('POST', '/2fa/disable', {'code': code});
  }

  /// Signs in with a credentials provider.
  Future<AuthSession> signInWithCredentials({
    String provider = 'credentials',
    String? email,
    String? username,
    required String password,
    Map<String, dynamic>? attributes,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      '/signin/${_pathSegment(provider)}',
      <String, dynamic>{
        ...?attributes,
        if (email != null) 'email': email,
        if (username != null) 'username': username,
        'password': password,
      },
    );
    final body = _mapBody(response.body);
    if (body['status'] == 'two_factor_required') {
      throw AuthClientTwoFactorRequiredException(
        challengeToken: _requiredString(body, 'challengeToken'),
        expiresAt: _requiredDate(body, 'expiresAt'),
      );
    }
    final session = _sessionFromMapOrNull(body);
    if (session == null) {
      throw const FormatException('Auth response did not contain a session');
    }
    return session;
  }

  /// Registers a new credentials account and signs the user in.
  Future<AuthSession> registerWithCredentials({
    String provider = 'credentials',
    String? email,
    String? username,
    required String password,
    Map<String, dynamic>? attributes,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      '/register/${_pathSegment(provider)}',
      <String, dynamic>{
        ...?attributes,
        if (email != null) 'email': email,
        if (username != null) 'username': username,
        'password': password,
      },
    );
    return _sessionFromBody(response.body);
  }

  /// Sends a magic-link sign-in request.
  Future<AuthClientVerificationSent> signInWithEmail({
    String provider = 'email',
    required String email,
    String? callbackUrl,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      '/signin/${_pathSegment(provider)}',
      <String, dynamic>{
        'email': email,
        if (callbackUrl != null) 'callbackUrl': callbackUrl,
      },
    );
    final body = _mapBody(response.body);
    return AuthClientVerificationSent(
      email: body['email']?.toString() ?? email,
    );
  }

  /// Starts an OAuth flow and returns the provider authorization URL.
  Future<Uri> beginOAuth({
    required String provider,
    String? callbackUrl,
  }) async {
    final response = await _request(
      'GET',
      '/signin/${_pathSegment(provider)}',
      queryParameters: {if (callbackUrl != null) 'callbackUrl': callbackUrl},
      followRedirects: false,
    );
    final location = response.headers['location'];
    if (location == null || location.trim().isEmpty) {
      throw const FormatException('Auth OAuth response did not contain a URL');
    }
    return Uri.parse(location);
  }

  /// Completes an OAuth callback and returns its session or redirect result.
  Future<AuthClientAuthResult> completeOAuth({
    required String provider,
    required String code,
    String? state,
  }) {
    return _completeCallback(
      provider: provider,
      parameters: <String, String>{
        'code': code,
        if (state != null) 'state': state,
      },
    );
  }

  /// Completes an email verification callback.
  Future<AuthClientAuthResult> verifyEmail({
    String provider = 'email',
    required String email,
    required String token,
  }) {
    return _completeCallback(
      provider: provider,
      parameters: <String, String>{'email': email, 'token': token},
    );
  }

  /// Reauthenticates the current user and changes their password.
  ///
  /// The server revokes the current session and all other sessions after a
  /// successful change, so callers should sign in again afterward.
  Future<void> changePassword({
    required String identifier,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _mutatingRequest('POST', '/password/change', <String, dynamic>{
      'identifier': identifier,
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
    _csrfToken = null;
  }

  /// Revokes one server-side session by its public session ID.
  Future<void> revokeSession(String sessionId) async {
    await _mutatingRequest('POST', '/sessions/revoke', <String, dynamic>{
      'sessionId': sessionId,
    });
  }

  /// Revokes every server-side session except the current session.
  Future<int> revokeOtherSessions() async {
    final response = await _mutatingRequest(
      'POST',
      '/sessions/revoke-others',
      const <String, dynamic>{},
    );
    final revoked = _mapBody(response.body)['revoked'];
    return revoked is int ? revoked : int.tryParse('$revoked') ?? 0;
  }

  /// Signs the current session out and processes expired auth cookies.
  Future<void> signOut() async {
    await _mutatingRequest('POST', '/signout', const <String, dynamic>{});
    _csrfToken = null;
  }

  Future<AuthClientAuthResult> _completeCallback({
    required String provider,
    required Map<String, String> parameters,
  }) async {
    final response = await _request(
      'GET',
      '/callback/${_pathSegment(provider)}',
      queryParameters: parameters,
      followRedirects: false,
    );
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

  Future<_AuthClientResponse> _mutatingRequest(
    String method,
    String relativePath,
    Map<String, dynamic> body,
  ) async {
    final csrf = _csrfToken ?? await getCsrfToken();
    return _request(
      method,
      relativePath,
      body: <String, dynamic>{...body, '_csrf': csrf},
      headers: {'x-csrf-token': csrf},
    );
  }

  Future<_AuthClientResponse> _request(
    String method,
    String relativePath, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    final uri = _endpoint(relativePath, queryParameters: queryParameters);
    final request = http.Request(method, uri)
      ..followRedirects = followRedirects
      ..headers.addAll({
        'accept': 'application/json',
        ..._headers,
        ...?headers,
      });
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (_bearerToken != null) {
      request.headers['authorization'] = 'Bearer $_bearerToken';
    }
    final cookies = await Future.sync(cookieStore.load);
    final requestCookies = cookies
        .where((cookie) => !cookie.secure || uri.scheme == 'https')
        .toList(growable: false);
    if (requestCookies.isNotEmpty) {
      request.headers['cookie'] = requestCookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    }

    final streamed = await _httpClient.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    await _storeResponseCookies(response);
    final result = _AuthClientResponse(response.statusCode, response);
    if (response.statusCode >= 400) {
      throw _exceptionFor(result);
    }
    return result;
  }

  Future<void> _storeResponseCookies(http.Response response) async {
    final header = response.headers['set-cookie'];
    if (header == null || header.trim().isEmpty) return;
    for (final value in _splitSetCookieHeader(header)) {
      try {
        await Future.sync(
          () => cookieStore.save(AuthClientCookie.fromSetCookie(value)),
        );
      } on FormatException {
        // Ignore malformed cookies from unrelated middleware. Auth state is
        // never inferred from an invalid cookie header.
      }
    }
  }

  AuthClientException _exceptionFor(_AuthClientResponse response) {
    String? code;
    String? message;
    try {
      final body = _mapBody(response.body);
      code = body['error']?.toString();
      message = body['message']?.toString();
    } on FormatException {
      // Preserve the HTTP failure even when a proxy returns non-JSON content.
    }
    final retryAfter = response.headers['retry-after'];
    final retrySeconds = retryAfter == null ? null : int.tryParse(retryAfter);
    return AuthClientException(
      statusCode: response.statusCode,
      code: code == null || code.isEmpty ? 'auth_request_failed' : code,
      message: message,
      retryAfter: retrySeconds == null ? null : Duration(seconds: retrySeconds),
    );
  }

  Uri _endpoint(String relativePath, {Map<String, String>? queryParameters}) {
    final path =
        '${_baseUrl.path.replaceFirst(RegExp(r'/*$'), '')}'
        '$_basePath$relativePath';
    return _baseUrl.replace(path: path, queryParameters: queryParameters);
  }
}

class _AuthClientResponse {
  const _AuthClientResponse(this.statusCode, this.response);

  final int statusCode;
  final http.Response response;

  String get body => response.body;

  Map<String, String> get headers => response.headers;
}

Map<String, dynamic> _mapBody(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Auth response was not a JSON object');
  }
  return Map<String, dynamic>.from(decoded);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Invalid auth session field: $key');
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(json[key]?.toString() ?? '');
  if (value == null) throw FormatException('Invalid auth session field: $key');
  return value;
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final raw = json[key];
  return raw == null ? null : DateTime.tryParse(raw.toString());
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
  final rawExpires = body['expires'];
  final strategyName = body['strategy']?.toString();
  final strategy = AuthSessionStrategy.values
      .where((value) => value.name == strategyName)
      .firstOrNull;
  return AuthSession(
    user: AuthUser.fromJson(Map<String, dynamic>.from(rawUser)),
    expiresAt: rawExpires == null
        ? null
        : DateTime.tryParse(rawExpires.toString()),
    strategy: strategy,
    token: body['token']?.toString(),
  );
}

String _normalizePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') return '';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}';
}

Uri _normalizeBaseUrl(Uri value) {
  if (!value.hasScheme || value.host.isEmpty) {
    throw ArgumentError.value(value, 'baseUrl', 'must be an absolute URI');
  }
  return value;
}

String _pathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.contains('/')) {
    throw ArgumentError.value(value, 'provider', 'must be one path segment');
  }
  return Uri.encodeComponent(trimmed);
}

Iterable<String> _splitSetCookieHeader(String header) {
  return header
      .split(RegExp(r',(?=\s*[^;,=\s]+\s*=)'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty);
}
