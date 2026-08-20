import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'email_otp_store.dart';
import 'models.dart';
import 'plugin.dart';

/// A cookie received from an auth response.
///
/// The client stores the name/value plus expiry and transport metadata needed
/// to avoid sending stale credentials or `Secure` cookies over HTTP. Other
/// attributes such as `HttpOnly`, `Path`, and `SameSite` are server instructions
/// and are not sent back as request data.
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

  bool get isDeletion => (maxAge != null && maxAge! <= 0) || isExpired;

  bool get isExpired =>
      expires != null && !expires!.isAfter(DateTime.now().toUtc());

  /// Parses the first cookie in a `Set-Cookie` header.
  factory AuthClientCookie.fromSetCookie(String header, {DateTime? now}) {
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

    // Max-Age is relative to receipt time and takes precedence over Expires.
    // Store it as an absolute deadline so persistent and in-memory stores do
    // not keep sending a credential after its lifetime has elapsed.
    if (maxAge != null) {
      expires = (now ?? DateTime.now()).toUtc().add(Duration(seconds: maxAge));
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
  Iterable<AuthClientCookie> load() {
    _cookies.removeWhere((_, cookie) => cookie.isExpired);
    return List<AuthClientCookie>.unmodifiable(_cookies.values);
  }

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

/// Public API-key metadata returned by the auth API.
final class AuthClientApiKey {
  const AuthClientApiKey({
    required this.id,
    required this.userId,
    required this.name,
    required this.keyPrefix,
    required this.scopes,
    required this.createdAt,
    required this.updatedAt,
    required this.active,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String keyPrefix;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;
  final bool active;

  factory AuthClientApiKey.fromJson(Map<String, dynamic> json) {
    final scopes = json['scopes'];
    if (scopes is! List || scopes.any((value) => value is! String)) {
      throw const FormatException('Invalid API-key scopes');
    }
    return AuthClientApiKey(
      id: _requiredString(json, 'id'),
      userId: _requiredString(json, 'userId'),
      name: _requiredString(json, 'name'),
      keyPrefix: _requiredString(json, 'keyPrefix'),
      scopes: List<String>.unmodifiable(scopes.cast<String>()),
      createdAt: _requiredDate(json, 'createdAt'),
      updatedAt: _requiredDate(json, 'updatedAt'),
      expiresAt: _optionalDate(json, 'expiresAt'),
      lastUsedAt: _optionalDate(json, 'lastUsedAt'),
      revokedAt: _optionalDate(json, 'revokedAt'),
      active: json['active'] == true,
    );
  }
}

/// Device-code response returned by the RFC 8628 authorization endpoint.
final class AuthClientDeviceAuthorization {
  const AuthClientDeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
    this.verificationUriComplete,
    this.receivedAt,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration expiresIn;
  final Duration interval;
  final String? verificationUriComplete;

  /// When the client received this response, used to enforce [expiresIn]
  /// locally while polling.
  final DateTime? receivedAt;

  factory AuthClientDeviceAuthorization.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) {
    return AuthClientDeviceAuthorization(
      deviceCode: _requiredString(json, 'device_code'),
      userCode: _requiredString(json, 'user_code'),
      verificationUri: _requiredString(json, 'verification_uri'),
      expiresIn: _requiredSeconds(json, 'expires_in'),
      interval: _requiredSeconds(json, 'interval'),
      verificationUriComplete: json['verification_uri_complete']?.toString(),
      receivedAt: receivedAt?.toUtc(),
    );
  }
}

/// Supplies the current time to device-authorization polling.
typedef AuthDeviceAuthorizationClock = DateTime Function();

/// Waits before the next device-token request.
typedef AuthDeviceAuthorizationDelay = Future<void> Function(Duration delay);

/// Decides whether an automatic device-authorization poll should continue.
typedef AuthDeviceAuthorizationShouldContinue =
    FutureOr<bool> Function(AuthDeviceAuthorizationPollingContext context);

/// State supplied before each wait in an automatic device-token poll.
final class AuthDeviceAuthorizationPollingContext {
  const AuthDeviceAuthorizationPollingContext({
    required this.attempts,
    required this.interval,
    required this.deadline,
    this.lastError,
  });

  /// Number of token requests already completed.
  final int attempts;

  /// Minimum delay before the next token request.
  final Duration interval;

  /// Effective local deadline for the polling operation.
  final DateTime deadline;

  /// Most recent retryable RFC 8628 response, if any.
  final AuthClientException? lastError;
}

/// Allows a caller to interrupt an automatic device-authorization poll.
final class AuthDeviceAuthorizationPollingController {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Why automatic device-authorization polling stopped locally.
enum AuthDeviceAuthorizationPollingStopReason {
  cancelled,
  stoppedByCaller,
  authorizationExpired,
  deadlineReached,
}

/// Indicates that automatic polling stopped before receiving a token.
final class AuthDeviceAuthorizationPollingStoppedException
    implements Exception {
  const AuthDeviceAuthorizationPollingStoppedException({
    required this.reason,
    required this.attempts,
  });

  final AuthDeviceAuthorizationPollingStopReason reason;
  final int attempts;

  @override
  String toString() =>
      'AuthDeviceAuthorizationPollingStoppedException($reason, attempts: '
      '$attempts)';
}

/// Controls a high-level RFC 8628 device-token polling operation.
final class AuthDeviceAuthorizationPollingOptions {
  AuthDeviceAuthorizationPollingOptions({
    this.deadline,
    this.controller,
    this.shouldContinue,
    AuthDeviceAuthorizationClock? clock,
    AuthDeviceAuthorizationDelay? delay,
  }) : clock = clock ?? _deviceAuthorizationClock,
       delay = delay ?? _deviceAuthorizationDelay;

  /// Optional caller deadline. The authorization expiry still takes priority
  /// when it occurs sooner.
  final DateTime? deadline;

  /// Optional controller that can interrupt a pending wait.
  final AuthDeviceAuthorizationPollingController? controller;

  /// Optional callback evaluated before every wait.
  final AuthDeviceAuthorizationShouldContinue? shouldContinue;

  /// Clock hook. Applications normally use the system-clock default.
  final AuthDeviceAuthorizationClock clock;

  /// Delay hook. Applications normally use the timer-backed default.
  final AuthDeviceAuthorizationDelay delay;
}

DateTime _deviceAuthorizationClock() => DateTime.now().toUtc();

Future<void> _deviceAuthorizationDelay(Duration delay) =>
    Future<void>.delayed(delay);

/// Access-token response returned after a device has been approved.
final class AuthClientDeviceAccessToken {
  const AuthClientDeviceAccessToken({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.scopes,
    this.refreshToken,
  });

  final String accessToken;
  final String tokenType;
  final Duration expiresIn;
  final List<String> scopes;
  final String? refreshToken;

  factory AuthClientDeviceAccessToken.fromJson(Map<String, dynamic> json) {
    final rawScope = json['scope'];
    final scopes = rawScope is String && rawScope.trim().isNotEmpty
        ? rawScope.trim().split(RegExp(r'\s+'))
        : const <String>[];
    return AuthClientDeviceAccessToken(
      accessToken: _requiredString(json, 'access_token'),
      tokenType: _requiredString(json, 'token_type'),
      expiresIn: _requiredSeconds(json, 'expires_in'),
      scopes: List<String>.unmodifiable(scopes),
      refreshToken: json['refresh_token']?.toString(),
    );
  }
}

/// Registration options returned by the WebAuthn ceremony-start endpoint.
///
/// [publicKey] is shaped for the browser `navigator.credentials.create` API.
/// Base64url fields remain strings so a platform adapter can convert them to
/// the byte representation required by its WebAuthn binding.
final class AuthClientWebAuthnRegistrationOptions {
  const AuthClientWebAuthnRegistrationOptions({
    required this.challenge,
    required this.relyingPartyId,
    required this.userId,
    required this.publicKey,
  });

  final String challenge;
  final String relyingPartyId;
  final String userId;
  final Map<String, dynamic> publicKey;

  factory AuthClientWebAuthnRegistrationOptions.fromJson(
    Map<String, dynamic> json,
  ) {
    final challenge = _requiredString(json, 'challenge');
    final rp = json['rp'];
    final user = json['user'];
    if (rp is! Map || user is! Map) {
      throw const FormatException('Invalid WebAuthn registration options');
    }
    final relyingPartyId = _requiredString(Map<String, dynamic>.from(rp), 'id');
    final userId = _requiredString(Map<String, dynamic>.from(user), 'id');
    final timeout = json['timeout'];
    if (timeout is! int || timeout <= 0) {
      throw const FormatException('Invalid WebAuthn registration timeout');
    }
    return AuthClientWebAuthnRegistrationOptions(
      challenge: challenge,
      relyingPartyId: relyingPartyId,
      userId: userId,
      publicKey: Map<String, dynamic>.unmodifiable(json),
    );
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(publicKey);
}

/// Authentication options returned by the WebAuthn ceremony-start endpoint.
final class AuthClientWebAuthnAuthenticationOptions {
  const AuthClientWebAuthnAuthenticationOptions({
    required this.challenge,
    required this.relyingPartyId,
    required this.timeout,
    required this.userVerification,
    required this.allowCredentials,
    this.userId,
  });

  final String challenge;
  final String relyingPartyId;
  final Duration timeout;
  final String userVerification;
  final List<String> allowCredentials;
  final String? userId;

  factory AuthClientWebAuthnAuthenticationOptions.fromJson(
    Map<String, dynamic> json, {
    String? userId,
  }) {
    final timeout = json['timeout'];
    final rawCredentials = json['allowCredentials'];
    if (timeout is! int ||
        timeout <= 0 ||
        (rawCredentials != null && rawCredentials is! List)) {
      throw const FormatException('Invalid WebAuthn authentication options');
    }
    final credentials = rawCredentials == null
        ? const <String>[]
        : rawCredentials
              .map((value) {
                if (value is! Map) {
                  throw const FormatException(
                    'Invalid WebAuthn allowed credential',
                  );
                }
                return _requiredString(Map<String, dynamic>.from(value), 'id');
              })
              .toList(growable: false);
    return AuthClientWebAuthnAuthenticationOptions(
      challenge: _requiredString(json, 'challenge'),
      relyingPartyId: _requiredString(json, 'rpId'),
      timeout: Duration(milliseconds: timeout),
      userVerification: _requiredString(json, 'userVerification'),
      allowCredentials: List<String>.unmodifiable(credentials),
      userId: userId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'challenge': challenge,
    'rpId': relyingPartyId,
    'timeout': timeout.inMilliseconds,
    'userVerification': userVerification,
    if (allowCredentials.isNotEmpty)
      'allowCredentials': allowCredentials
          .map((id) => <String, dynamic>{'type': 'public-key', 'id': id})
          .toList(growable: false),
  };
}

/// Public metadata for a registered passkey.
final class AuthClientWebAuthnCredential {
  const AuthClientWebAuthnCredential({
    required this.credentialId,
    required this.userId,
    required this.counter,
    this.publicKey,
    this.transports,
    this.createdAt,
    this.lastUsedAt,
    this.name,
  });

  final String credentialId;
  final String userId;
  final int counter;
  final String? publicKey;
  final List<String>? transports;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final String? name;

  factory AuthClientWebAuthnCredential.fromJson(Map<String, dynamic> json) {
    final rawCounter = json['counter'];
    if (rawCounter is! int || rawCounter < 0) {
      throw const FormatException('Invalid WebAuthn credential counter');
    }
    final rawTransports = json['transports'];
    if (rawTransports != null &&
        (rawTransports is! List ||
            rawTransports.any((value) => value is! String))) {
      throw const FormatException('Invalid WebAuthn credential transports');
    }
    return AuthClientWebAuthnCredential(
      credentialId: _requiredString(json, 'credential_id'),
      userId: _requiredString(json, 'user_id'),
      counter: rawCounter,
      publicKey: json['public_key']?.toString(),
      transports: rawTransports == null
          ? null
          : List<String>.unmodifiable(rawTransports.cast<String>()),
      createdAt: _optionalDate(json, 'created_at'),
      lastUsedAt: _optionalDate(json, 'last_used_at'),
      name: json['name']?.toString(),
    );
  }
}

/// The one-time API-key response returned after create or rotate.
final class AuthClientIssuedApiKey {
  const AuthClientIssuedApiKey({required this.apiKey, required this.key});

  final AuthClientApiKey apiKey;
  final String key;

  factory AuthClientIssuedApiKey.fromJson(Map<String, dynamic> json) {
    final key = _requiredString(json, 'apiKey');
    return AuthClientIssuedApiKey(
      apiKey: AuthClientApiKey.fromJson(json),
      key: key,
    );
  }
}

/// Result returned after a passkey assertion is verified.
final class AuthClientWebAuthnAuthenticationResult {
  const AuthClientWebAuthnAuthenticationResult({
    required this.user,
    required this.credential,
    required this.session,
  });

  final AuthUser user;
  final AuthClientWebAuthnCredential credential;
  final AuthSession session;

  factory AuthClientWebAuthnAuthenticationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawUser = json['user'];
    final rawCredential = json['credential'];
    final session = _sessionFromMapOrNull(json);
    if (rawUser is! Map || rawCredential is! Map || session == null) {
      throw const FormatException('Invalid WebAuthn authentication response');
    }
    return AuthClientWebAuthnAuthenticationResult(
      user: AuthUser.fromJson(Map<String, dynamic>.from(rawUser)),
      credential: AuthClientWebAuthnCredential.fromJson(
        Map<String, dynamic>.from(rawCredential),
      ),
      session: session,
    );
  }
}

/// TOTP enrollment data returned by a two-factor plugin.
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

/// Raw successful response returned by [AuthClientTransport].
final class AuthClientResponse {
  const AuthClientResponse(this.statusCode, this.response);

  final int statusCode;
  final http.Response response;

  String get body => response.body;
  Map<String, String> get headers => response.headers;
}

/// Shared HTTP transport for core and plugin-specific auth clients.
///
/// It owns cookies, bearer authentication, CSRF reuse, timeouts, redirect
/// policy, bounded error parsing, and response-cookie processing.
class AuthClientTransport {
  AuthClientTransport({
    required Uri baseUrl,
    String basePath = '/auth',
    http.Client? httpClient,
    AuthClientCookieStore? cookieStore,
    this.timeout = const Duration(seconds: 15),
    Map<String, String>? headers,
    String? bearerToken,
    String? apiKey,
    this.maximumErrorBodyBytes = 65536,
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _basePath = _normalizePath(basePath),
       _httpClient = httpClient ?? http.Client(),
       cookieStore = cookieStore ?? InMemoryAuthClientCookieStore(),
       _headers = Map<String, String>.unmodifiable(headers ?? const {}),
       _bearerToken = bearerToken,
       _apiKey = apiKey;

  final Uri _baseUrl;
  final String _basePath;
  final http.Client _httpClient;
  final AuthClientCookieStore cookieStore;
  final Duration timeout;
  final int maximumErrorBodyBytes;
  final Map<String, String> _headers;
  String? _bearerToken;
  String? _apiKey;
  String? _csrfToken;

  void setBearerToken(String? token) {
    _bearerToken = token?.trim().isEmpty == true ? null : token?.trim();
  }

  /// Replaces the API key used for service-client requests.
  void setApiKey(String? key) {
    _apiKey = key?.trim().isEmpty == true ? null : key?.trim();
  }

  void clearCsrfToken() => _csrfToken = null;

  Future<String> getCsrfToken() async {
    final response = await request('GET', const AuthRoutePath('/csrf'));
    final token = _mapBody(response.body)['csrfToken']?.toString().trim() ?? '';
    if (token.isEmpty) {
      throw const FormatException('Invalid auth CSRF response');
    }
    _csrfToken = token;
    return token;
  }

  Future<AuthClientResponse> mutate(
    String method,
    AuthRoutePath route,
    Map<String, dynamic> body, {
    Map<AuthRouteParameterKey, String> pathParameters =
        const <AuthRouteParameterKey, String>{},
    AuthEndpointMount mount = AuthEndpointMount.auth,
  }) async {
    final csrf = _csrfToken ?? await getCsrfToken();
    try {
      return await request(
        method,
        route,
        pathParameters: pathParameters,
        mount: mount,
        body: <String, dynamic>{...body, '_csrf': csrf},
        headers: {'x-csrf-token': csrf},
      );
    } on AuthClientException catch (error) {
      if (error.code != 'invalid_csrf') rethrow;
      _csrfToken = null;
      final refreshed = await getCsrfToken();
      return request(
        method,
        route,
        pathParameters: pathParameters,
        mount: mount,
        body: <String, dynamic>{...body, '_csrf': refreshed},
        headers: {'x-csrf-token': refreshed},
      );
    }
  }

  Future<AuthClientResponse> request(
    String method,
    AuthRoutePath route, {
    Map<AuthRouteParameterKey, String> pathParameters =
        const <AuthRouteParameterKey, String>{},
    AuthEndpointMount mount = AuthEndpointMount.auth,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    final uri = endpoint(
      route,
      pathParameters: pathParameters,
      mount: mount,
      queryParameters: queryParameters,
    );
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
    if (_apiKey != null) {
      request.headers['x-api-key'] = _apiKey!;
    }
    final cookies = (await Future.sync(cookieStore.load))
        .where(
          (cookie) =>
              !cookie.isDeletion && (!cookie.secure || uri.scheme == 'https'),
        )
        .toList(growable: false);
    if (cookies.isNotEmpty) {
      request.headers['cookie'] = cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    }

    final streamed = await _httpClient.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    await _storeResponseCookies(response);
    final result = AuthClientResponse(response.statusCode, response);
    if (response.statusCode >= 400) throw _exceptionFor(result);
    return result;
  }

  Uri endpoint(
    AuthRoutePath route, {
    Map<AuthRouteParameterKey, String> pathParameters =
        const <AuthRouteParameterKey, String>{},
    AuthEndpointMount mount = AuthEndpointMount.auth,
    Map<String, String>? queryParameters,
  }) {
    final resolved = Uri.parse(route.resolve(pathParameters));
    final segments = <String>[
      ..._baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
      if (mount == AuthEndpointMount.auth)
        ...Uri.parse(
          _basePath,
        ).pathSegments.where((segment) => segment.isNotEmpty),
      ...resolved.pathSegments,
    ];
    return _baseUrl.replace(
      pathSegments: segments,
      queryParameters: queryParameters,
    );
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
        // Ignore malformed cookies from unrelated middleware.
      }
    }
  }

  AuthClientException _exceptionFor(AuthClientResponse response) {
    String? code;
    String? message;
    if (response.body.length <= maximumErrorBodyBytes) {
      try {
        final body = _mapBody(response.body);
        code = body['error']?.toString();
        message = body['message']?.toString();
      } on FormatException {
        // Preserve the HTTP failure when a proxy returns non-JSON content.
      }
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
}

/// Context supplied when an optional client plugin is installed.
///
/// Plugins share the host transport so cookies, bearer credentials, API keys,
/// CSRF state, timeouts, and response handling remain consistent across the
/// selected client APIs.
final class AuthClientPluginContext {
  const AuthClientPluginContext({required this.transport});

  final AuthClientTransport transport;
}

/// A typed, opt-in client API.
///
/// A plugin should expose only the operations owned by one server plugin or
/// provider. Applications install the client plugins they use instead of
/// receiving every optional auth operation on one client object.
abstract interface class AuthClientPlugin<TApi extends Object> {
  String get id;

  TApi install(AuthClientPluginContext context);
}

final class _InstalledAuthClientPlugin {
  const _InstalledAuthClientPlugin({required this.plugin, required this.api});

  final AuthClientPlugin<dynamic> plugin;
  final Object api;
}

/// Registry of the client plugins selected for one [AuthClient].
final class AuthClientPluginRegistry {
  AuthClientPluginRegistry({
    required AuthClientPluginContext context,
    Iterable<AuthClientPlugin<dynamic>> plugins =
        const <AuthClientPlugin<dynamic>>[],
  }) {
    for (final plugin in plugins) {
      final id = plugin.id.trim();
      if (id.isEmpty) {
        throw ArgumentError.value(plugin.id, 'plugin.id', 'must not be empty');
      }
      if (_installed.containsKey(id)) {
        throw StateError('Auth client plugin "$id" is already installed.');
      }
      _installed[id] = _InstalledAuthClientPlugin(
        plugin: plugin,
        api: plugin.install(context),
      );
    }
  }

  final Map<String, _InstalledAuthClientPlugin> _installed =
      <String, _InstalledAuthClientPlugin>{};

  /// Returns the typed API for an installed [plugin].
  ///
  /// Passing a plugin that was not included in the host client's constructor
  /// is an error, making accidental use of optional auth APIs explicit.
  TApi use<TApi extends Object>(AuthClientPlugin<TApi> plugin) {
    final installed = _installed[plugin.id.trim()];
    if (installed == null) {
      throw StateError(
        'Auth client plugin "${plugin.id}" is not installed. '
        'Add it to AuthClient.plugins.',
      );
    }
    if (installed.plugin.runtimeType != plugin.runtimeType) {
      throw StateError(
        'Auth client plugin ID "${plugin.id}" is registered by '
        '${installed.plugin.runtimeType}, not ${plugin.runtimeType}.',
      );
    }
    return installed.api as TApi;
  }

  bool contains(String id) => _installed.containsKey(id.trim());

  Iterable<String> get ids => List<String>.unmodifiable(_installed.keys);
}

/// Internal transport-backed implementation used while auth APIs are split
/// into typed client plugins.
///
/// New applications should use [AuthClient] with the client plugins they need.
class AuthClientCore {
  AuthClientCore.fromTransport(this.transport);

  AuthClientCore({
    required Uri baseUrl,
    String basePath = '/auth',
    http.Client? httpClient,
    AuthClientCookieStore? cookieStore,
    Duration timeout = const Duration(seconds: 15),
    Map<String, String>? headers,
    String? bearerToken,
    String? apiKey,
    AuthClientTransport? transport,
  }) : transport =
           transport ??
           AuthClientTransport(
             baseUrl: baseUrl,
             basePath: basePath,
             httpClient: httpClient,
             cookieStore: cookieStore,
             timeout: timeout,
             headers: headers,
             bearerToken: bearerToken,
             apiKey: apiKey,
           );

  final AuthClientTransport transport;

  AuthClientCookieStore get cookieStore => transport.cookieStore;
  Duration get timeout => transport.timeout;

  /// Replaces the bearer token used for JWT-based auth requests.
  void setBearerToken(String? token) {
    transport.setBearerToken(token);
  }

  /// Replaces the API key used for service-client requests.
  void setApiKey(String? key) {
    transport.setApiKey(key);
  }

  /// Clears the cached CSRF token so the next state-changing request refreshes
  /// it from the server.
  void clearCsrfToken() {
    transport.clearCsrfToken();
  }

  /// Lists the providers exposed by the auth server.
  Future<List<AuthClientProvider>> getProviders() async {
    final response = await _request('GET', const AuthRoutePath('/providers'));
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

  /// Starts an RFC 8628 device authorization transaction for [clientId].
  ///
  /// This endpoint is intentionally unauthenticated and does not use the
  /// browser CSRF flow because it is called by a constrained device.
  Future<AuthClientDeviceAuthorization> requestDeviceAuthorization({
    required String clientId,
    Iterable<String> scopes = const <String>[],
  }) async {
    final response = await _request(
      'POST',
      const AuthRoutePath('/oauth/device/authorize'),
      body: {'client_id': clientId, 'scope': scopes.join(' ')},
    );
    return AuthClientDeviceAuthorization.fromJson(
      _mapBody(response.body),
      receivedAt: DateTime.now().toUtc(),
    );
  }

  /// Polls the device token endpoint.
  ///
  /// RFC 8628 errors are surfaced as [AuthClientException] codes such as
  /// `authorization_pending`, `slow_down`, and `expired_token`.
  Future<AuthClientDeviceAccessToken> pollDeviceToken({
    required String clientId,
    required String deviceCode,
  }) async {
    final response = await _request(
      'POST',
      const AuthRoutePath('/oauth/token'),
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'client_id': clientId,
        'device_code': deviceCode,
      },
    );
    return AuthClientDeviceAccessToken.fromJson(_mapBody(response.body));
  }

  /// Approves a device code from an authenticated browser session.
  Future<void> approveDeviceAuthorization({required String userCode}) async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/oauth/device/approve'),
      {'user_code': userCode},
    );
  }

  /// Denies a device code from an authenticated browser session.
  Future<void> denyDeviceAuthorization({required String userCode}) async {
    await _mutatingRequest('POST', const AuthRoutePath('/oauth/device/deny'), {
      'user_code': userCode,
    });
  }

  /// Requests an email OTP for sign-in or email verification.
  Future<void> sendEmailOtp({
    required String email,
    required AuthEmailOtpType type,
  }) async {
    await _request(
      'POST',
      const AuthRoutePath('/email-otp/send-verification-otp'),
      body: {'email': email, 'type': _emailOtpTypeName(type)},
    );
  }

  /// Checks and consumes an email OTP without creating a session.
  Future<void> checkEmailOtp({
    required String email,
    required AuthEmailOtpType type,
    required String otp,
  }) async {
    await _request(
      'POST',
      const AuthRoutePath('/email-otp/check-verification-otp'),
      body: {'email': email, 'type': _emailOtpTypeName(type), 'otp': otp},
    );
  }

  /// Signs in with an email OTP and stores the returned session cookie.
  Future<AuthSession> signInWithEmailOtp({
    required String email,
    required String otp,
    String? name,
    String? image,
  }) async {
    final response = await _request(
      'POST',
      const AuthRoutePath('/sign-in/email-otp'),
      body: {'email': email, 'otp': otp, 'name': ?name, 'image': ?image},
    );
    return _sessionFromBody(response.body);
  }

  /// Verifies the current user's email with an OTP.
  Future<AuthUser> verifyEmailWithOtp({required String otp}) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/email-otp/verify-email'),
      {'otp': otp},
    );
    final value = _mapBody(response.body)['user'];
    if (value is! Map) {
      throw const FormatException('Invalid email OTP response');
    }
    return AuthUser.fromJson(Map<String, dynamic>.from(value));
  }

  /// Creates an anonymous authenticated session without collecting PII.
  Future<AuthSession> signInAnonymously() async {
    final response = await _request(
      'POST',
      const AuthRoutePath('/sign-in/anonymous'),
      body: const {},
    );
    return _sessionFromBody(response.body);
  }

  /// Deletes the current anonymous account and signs the client out.
  Future<void> deleteAnonymousUser() async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/delete-anonymous-user'),
      const {},
    );
    transport.clearCsrfToken();
  }

  /// Obtains and caches the CSRF token used by state-changing requests.
  Future<String> getCsrfToken() async {
    return transport.getCsrfToken();
  }

  /// Returns the current session, or `null` when the client is signed out.
  Future<AuthSession?> getSession() async {
    final response = await _request('GET', const AuthRoutePath('/session'));
    if (response.body.trim() == 'null') return null;
    return _sessionFromBody(response.body);
  }

  /// Lists active server-side sessions for the current user.
  Future<List<AuthClientSession>> getSessions() async {
    final response = await _request('GET', const AuthRoutePath('/sessions'));
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

  /// Lists API-key metadata for the current user.
  Future<List<AuthClientApiKey>> getApiKeys() async {
    final response = await _request(
      'GET',
      const AuthRoutePath('/api-keys/list'),
    );
    final values = _mapBody(response.body)['apiKeys'];
    if (values is! List) {
      throw const FormatException('Invalid API-key response');
    }
    return values
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid API-key metadata');
          }
          return AuthClientApiKey.fromJson(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);
  }

  /// Begins a passkey registration ceremony for the signed-in user.
  Future<AuthClientWebAuthnRegistrationOptions>
  beginWebAuthnRegistration() async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/webauthn/register/options'),
      const <String, dynamic>{},
    );
    return AuthClientWebAuthnRegistrationOptions.fromJson(
      _mapBody(response.body),
    );
  }

  /// Completes passkey registration and returns persisted credential metadata.
  Future<AuthClientWebAuthnCredential> completeWebAuthnRegistration({
    required Map<String, dynamic> credential,
    String? name,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/webauthn/register/verify'),
      <String, dynamic>{
        'credential': <String, dynamic>{...credential, 'name': ?name},
      },
    );
    final rawCredential = _mapBody(response.body)['credential'];
    if (rawCredential is! Map) {
      throw const FormatException('Invalid WebAuthn registration response');
    }
    return AuthClientWebAuthnCredential.fromJson(
      Map<String, dynamic>.from(rawCredential),
    );
  }

  /// Begins a discoverable or user-bound passkey authentication ceremony.
  Future<AuthClientWebAuthnAuthenticationOptions> beginWebAuthnAuthentication({
    String? userId,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/webauthn/authenticate/options'),
      <String, dynamic>{'userId': ?userId},
    );
    return AuthClientWebAuthnAuthenticationOptions.fromJson(
      _mapBody(response.body),
      userId: userId,
    );
  }

  /// Verifies a browser passkey assertion.
  Future<AuthClientWebAuthnAuthenticationResult>
  completeWebAuthnAuthentication({
    required Map<String, dynamic> credential,
    String? userId,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/webauthn/authenticate/verify'),
      <String, dynamic>{'credential': credential, 'userId': ?userId},
    );
    return AuthClientWebAuthnAuthenticationResult.fromJson(
      _mapBody(response.body),
    );
  }

  /// Lists passkeys registered for the current user.
  Future<List<AuthClientWebAuthnCredential>> getWebAuthnCredentials() async {
    final response = await _request(
      'GET',
      const AuthRoutePath('/webauthn/credentials'),
    );
    final values = _mapBody(response.body)['credentials'];
    if (values is! List) {
      throw const FormatException('Invalid WebAuthn credential response');
    }
    return values
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid WebAuthn credential');
          }
          return AuthClientWebAuthnCredential.fromJson(
            Map<String, dynamic>.from(value),
          );
        })
        .toList(growable: false);
  }

  /// Creates an API key. The raw key is returned only in this response.
  Future<AuthClientIssuedApiKey> createApiKey({
    required String name,
    Iterable<String> scopes = const <String>[],
    DateTime? expiresAt,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/api-keys/create'),
      {
        'name': name,
        'scopes': scopes.toList(growable: false),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
      },
    );
    return AuthClientIssuedApiKey.fromJson(_mapBody(response.body));
  }

  /// Revokes one API key belonging to the current user.
  Future<void> revokeApiKey({required String id}) async {
    await _mutatingRequest('POST', const AuthRoutePath('/api-keys/revoke'), {
      'id': id,
    });
  }

  /// Atomically rotates one API key. The replacement secret is returned once.
  Future<AuthClientIssuedApiKey> rotateApiKey({
    required String id,
    String? name,
    Iterable<String>? scopes,
    DateTime? expiresAt,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/api-keys/rotate'),
      {
        'id': id,
        'name': ?name,
        'scopes': scopes?.toList(growable: false),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
      },
    );
    return AuthClientIssuedApiKey.fromJson(_mapBody(response.body));
  }

  /// Exchanges the configured API key for a normal server-side session.
  ///
  /// The server must opt into this boundary with
  /// `sessionExchangeEnabled: true`. The transport stores the returned
  /// session cookie alongside its existing cookies.
  Future<AuthSession> exchangeApiKeyForSession() async {
    final response = await _request(
      'POST',
      const AuthRoutePath('/api-keys/exchange'),
    );
    return _sessionFromBody(response.body);
  }

  /// Deletes one passkey belonging to the current user.
  Future<void> deleteWebAuthnCredential({required String credentialId}) async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/webauthn/credentials/delete'),
      {'credentialId': credentialId},
    );
  }

  /// Renames one passkey belonging to the current user.
  Future<AuthClientWebAuthnCredential> renameWebAuthnCredential({
    required String credentialId,
    required String name,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/webauthn/credentials/rename'),
      <String, dynamic>{'credentialId': credentialId, 'name': name},
    );
    final rawCredential = _mapBody(response.body)['credential'];
    if (rawCredential is! Map) {
      throw const FormatException('Invalid WebAuthn rename response');
    }
    return AuthClientWebAuthnCredential.fromJson(
      Map<String, dynamic>.from(rawCredential),
    );
  }

  /// Returns the current two-factor status for the signed-in user.
  Future<AuthClientTwoFactorStatus> getTwoFactorStatus() async {
    final response = await _request('GET', const AuthRoutePath('/2fa/status'));
    return AuthClientTwoFactorStatus.fromJson(_mapBody(response.body));
  }

  /// Starts TOTP enrollment for the signed-in user.
  Future<AuthClientTwoFactorEnrollment> beginTwoFactorEnrollment({
    String? accountLabel,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/enroll'),
      {'accountLabel': ?accountLabel},
    );
    return AuthClientTwoFactorEnrollment.fromJson(_mapBody(response.body));
  }

  /// Verifies the first TOTP code and activates the factor.
  Future<AuthClientTwoFactorRecoveryCodes> verifyTwoFactorEnrollment({
    required String code,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/enroll/verify'),
      {'code': code},
    );
    return AuthClientTwoFactorRecoveryCodes.fromJson(_mapBody(response.body));
  }

  /// Verifies an enabled TOTP code.
  Future<void> verifyTwoFactor({required String code}) async {
    await _mutatingRequest('POST', const AuthRoutePath('/2fa/verify'), {
      'code': code,
    });
  }

  /// Completes a pending credential sign-in with a TOTP code.
  Future<AuthSession> verifyTwoFactorChallenge({
    required String challengeToken,
    required String code,
    bool trustDevice = false,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/challenge/verify'),
      {
        'challengeToken': challengeToken,
        'code': code,
        'trustDevice': trustDevice,
      },
    );
    return _sessionFromBody(response.body);
  }

  /// Completes a pending credential sign-in with a one-time recovery code.
  Future<AuthSession> verifyTwoFactorRecoveryChallenge({
    required String challengeToken,
    required String recoveryCode,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/challenge/recovery-code'),
      {'challengeToken': challengeToken, 'recoveryCode': recoveryCode},
    );
    return _sessionFromBody(response.body);
  }

  /// Revokes all trusted two-factor devices for the current session.
  Future<void> revokeTwoFactorTrustedDevices() async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/trusted-devices/revoke'),
      const {},
    );
  }

  /// Verifies TOTP for a sensitive action and stores the short-lived proof.
  Future<AuthClientTwoFactorStepUp> verifyTwoFactorStepUp({
    required String code,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/step-up'),
      {'code': code},
    );
    return AuthClientTwoFactorStepUp.fromJson(_mapBody(response.body));
  }

  /// Revokes the current session's step-up proof.
  Future<void> revokeTwoFactorStepUp() async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/step-up/revoke'),
      const {},
    );
  }

  /// Consumes one recovery code.
  Future<void> useTwoFactorRecoveryCode({required String code}) async {
    await _mutatingRequest('POST', const AuthRoutePath('/2fa/recovery-code'), {
      'recoveryCode': code,
    });
  }

  /// Replaces all recovery codes after verifying the current TOTP code.
  Future<AuthClientTwoFactorRecoveryCodes> regenerateTwoFactorRecoveryCodes({
    required String code,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/2fa/recovery-codes/regenerate'),
      {'code': code},
    );
    return AuthClientTwoFactorRecoveryCodes.fromJson(_mapBody(response.body));
  }

  /// Disables two-factor authentication after verifying the current TOTP code.
  Future<void> disableTwoFactor({required String code}) async {
    await _mutatingRequest('POST', const AuthRoutePath('/2fa/disable'), {
      'code': code,
    });
  }

  /// Signs in with a credentials provider.
  Future<AuthSession> signInWithCredentials({
    String provider = 'credentials',
    String? email,
    String? username,
    required String password,
    Map<String, dynamic>? attributes,
    String? captchaToken,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      authSignInProviderRoute,
      <String, dynamic>{
        ...?attributes,
        'email': ?email,
        'username': ?username,
        'password': password,
        'captchaToken': ?captchaToken,
      },
      pathParameters: <AuthRouteParameterKey, String>{
        authProviderRouteParameter: provider,
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
    String? captchaToken,
  }) async {
    final response = await _mutatingRequest(
      'POST',
      authRegisterProviderRoute,
      <String, dynamic>{
        ...?attributes,
        'email': ?email,
        'username': ?username,
        'password': password,
        'captchaToken': ?captchaToken,
      },
      pathParameters: <AuthRouteParameterKey, String>{
        authProviderRouteParameter: provider,
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
      authSignInProviderRoute,
      <String, dynamic>{'email': email, 'callbackUrl': ?callbackUrl},
      pathParameters: <AuthRouteParameterKey, String>{
        authProviderRouteParameter: provider,
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
      authSignInProviderRoute,
      pathParameters: <AuthRouteParameterKey, String>{
        authProviderRouteParameter: provider,
      },
      queryParameters: {'callbackUrl': ?callbackUrl},
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
      parameters: <String, String>{'code': code, 'state': ?state},
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
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/password/change'),
      <String, dynamic>{
        'identifier': identifier,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
    transport.clearCsrfToken();
  }

  /// Reauthenticates the current user and requests an email-change message.
  Future<void> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? identifier,
  }) async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/email/change/request'),
      <String, dynamic>{
        'newEmail': newEmail,
        'currentPassword': currentPassword,
        'identifier': ?identifier,
      },
    );
  }

  /// Lists linked external identities without provider tokens.
  Future<List<AuthAccount>> getLinkedAccounts() async {
    final response = await _request('GET', const AuthRoutePath('/accounts'));
    final values = _mapBody(response.body)['accounts'];
    if (values is! List) {
      throw const FormatException('Invalid linked-account response');
    }
    return values
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid linked-account metadata');
          }
          return AuthAccount.fromJson(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);
  }

  /// Unlinks one external identity using password or recent-auth/step-up proof.
  Future<void> unlinkAccount({
    required String providerId,
    required String providerAccountId,
    String? currentPassword,
  }) async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/accounts/unlink'),
      <String, dynamic>{
        'providerId': providerId,
        'providerAccountId': providerAccountId,
        'currentPassword': ?currentPassword,
      },
    );
  }

  /// Reauthenticates and permanently deletes the current account.
  Future<void> deleteAccount({required String currentPassword}) async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/account/delete'),
      <String, dynamic>{'currentPassword': currentPassword},
    );
    transport.clearCsrfToken();
  }

  /// Confirms an email change and returns the updated user projection.
  Future<AuthUser> confirmEmailChange({required String token}) async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/email/change/confirm'),
      <String, dynamic>{'token': token},
    );
    final value = _mapBody(response.body)['user'];
    if (value is! Map) {
      throw const FormatException('Invalid email-change response');
    }
    transport.clearCsrfToken();
    return AuthUser.fromJson(Map<String, dynamic>.from(value));
  }

  /// Revokes one server-side session by its public session ID.
  Future<void> revokeSession(String sessionId) async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/sessions/revoke'),
      <String, dynamic>{'sessionId': sessionId},
    );
  }

  /// Revokes every server-side session except the current session.
  Future<int> revokeOtherSessions() async {
    final response = await _mutatingRequest(
      'POST',
      const AuthRoutePath('/sessions/revoke-others'),
      const <String, dynamic>{},
    );
    final revoked = _mapBody(response.body)['revoked'];
    return revoked is int ? revoked : int.tryParse('$revoked') ?? 0;
  }

  /// Signs the current session out and processes expired auth cookies.
  Future<void> signOut() async {
    await _mutatingRequest(
      'POST',
      const AuthRoutePath('/signout'),
      const <String, dynamic>{},
    );
    transport.clearCsrfToken();
  }

  Future<AuthClientAuthResult> _completeCallback({
    required String provider,
    required Map<String, String> parameters,
  }) async {
    final response = await _request(
      'GET',
      authCallbackProviderRoute,
      pathParameters: <AuthRouteParameterKey, String>{
        authProviderRouteParameter: provider,
      },
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

  Future<AuthClientResponse> _mutatingRequest(
    String method,
    AuthRoutePath route,
    Map<String, dynamic> body, {
    Map<AuthRouteParameterKey, String> pathParameters =
        const <AuthRouteParameterKey, String>{},
  }) async {
    return transport.mutate(
      method,
      route,
      body,
      pathParameters: pathParameters,
    );
  }

  Future<AuthClientResponse> _request(
    String method,
    AuthRoutePath route, {
    Map<AuthRouteParameterKey, String> pathParameters =
        const <AuthRouteParameterKey, String>{},
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    return transport.request(
      method,
      route,
      pathParameters: pathParameters,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      followRedirects: followRedirects,
    );
  }
}

/// Typed host for the framework-independent auth client contract.
///
/// The host exposes transport controls and only the optional APIs selected in
/// [plugins]. Plugin and provider operations should be accessed through their
/// typed plugin APIs rather than through one global client surface.
final class AuthClient {
  AuthClient({
    required Uri baseUrl,
    String basePath = '/auth',
    http.Client? httpClient,
    AuthClientCookieStore? cookieStore,
    Duration timeout = const Duration(seconds: 15),
    Map<String, String>? headers,
    String? bearerToken,
    String? apiKey,
    AuthClientTransport? transport,
    Iterable<AuthClientPlugin<dynamic>> plugins =
        const <AuthClientPlugin<dynamic>>[],
  }) : transport =
           transport ??
           AuthClientTransport(
             baseUrl: baseUrl,
             basePath: basePath,
             httpClient: httpClient,
             cookieStore: cookieStore,
             timeout: timeout,
             headers: headers,
             bearerToken: bearerToken,
             apiKey: apiKey,
           ) {
    this.plugins = AuthClientPluginRegistry(
      context: AuthClientPluginContext(transport: this.transport),
      plugins: plugins,
    );
  }

  final AuthClientTransport transport;

  /// The explicitly selected optional client APIs.
  late final AuthClientPluginRegistry plugins;

  AuthClientCookieStore get cookieStore => transport.cookieStore;
  Duration get timeout => transport.timeout;

  void setBearerToken(String? token) => transport.setBearerToken(token);

  void setApiKey(String? key) => transport.setApiKey(key);

  void clearCsrfToken() => transport.clearCsrfToken();

  Future<String> getCsrfToken() => transport.getCsrfToken();
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

String _emailOtpTypeName(AuthEmailOtpType type) {
  switch (type) {
    case AuthEmailOtpType.signIn:
      return 'sign-in';
    case AuthEmailOtpType.emailVerification:
      return 'email-verification';
    case AuthEmailOtpType.forgetPassword:
      return 'forget-password';
    case AuthEmailOtpType.changeEmail:
      return 'change-email';
  }
}

Duration _requiredSeconds(Map<String, dynamic> json, String key) {
  final value = json[key];
  final seconds = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (seconds == null || seconds <= 0) {
    throw FormatException('Invalid auth duration field: $key');
  }
  return Duration(seconds: seconds);
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

Iterable<String> _splitSetCookieHeader(String header) {
  return header
      .split(RegExp(r',(?=\s*[^;,=\s]+\s*=)'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty);
}
