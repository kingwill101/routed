import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';

import 'bearer.dart' show extractBearerToken;
import 'models.dart' show AuthSession, AuthSessionStrategy, AuthUser;
import 'users.dart' show authUserFromJwtClaims;

export 'package:jose/jose.dart';

/// Attribute key for JWT claims in framework request context stores.
const String jwtClaimsAttribute = 'auth.jwt.claims';

/// Attribute key for JWT headers in framework request context stores.
const String jwtHeadersAttribute = 'auth.jwt.headers';

/// Attribute key for the JWT subject in framework request context stores.
const String jwtSubjectAttribute = 'auth.jwt.subject';

/// Parses a JWT `iat` claim value into a UTC timestamp.
DateTime? jwtIssuedAtUtc(Object? value) {
  if (value is! num) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value.toInt() * 1000,
    isUtc: true,
  ).toUtc();
}

/// Returns true when a JWT should be refreshed based on its `iat` claim.
bool shouldRefreshJwtByIssuedAt(
  Object? issuedAtClaim,
  Duration updateAge, {
  DateTime? now,
}) {
  final issuedAt = jwtIssuedAtUtc(issuedAtClaim);
  if (issuedAt == null) {
    return false;
  }
  final current = (now ?? DateTime.now()).toUtc();
  return current.difference(issuedAt) >= updateAge;
}

/// Returns true when JWT claims indicate refresh should occur.
bool shouldRefreshJwtClaims(
  Map<String, dynamic> claims,
  Duration? updateAge, {
  DateTime? now,
}) {
  if (updateAge == null) {
    return false;
  }
  final issuedAtValue = claims['iat'];
  final issuedAt = jwtIssuedAtUtc(issuedAtValue);
  if (issuedAt == null) {
    return false;
  }
  return shouldRefreshJwtByIssuedAt(issuedAtValue, updateAge, now: now);
}

/// Builds an HTTP-only JWT cookie.
Cookie buildJwtTokenCookie(
  String cookieName,
  String token, {
  DateTime? expires,
  String path = '/',
  bool httpOnly = true,
}) {
  final cookie = Cookie(cookieName, token)
    ..httpOnly = httpOnly
    ..path = path;
  if (expires != null) {
    cookie.expires = expires;
  }
  return cookie;
}

/// Builds an expired JWT cookie for sign-out flows.
Cookie buildExpiredJwtTokenCookie(String cookieName, {String path = '/'}) {
  return buildJwtTokenCookie(cookieName, '', path: path)..maxAge = 0;
}

/// Result of issuing a JWT token and corresponding auth cookie.
class AuthIssuedJwtToken {
  const AuthIssuedJwtToken({
    required this.token,
    required this.expiresAt,
    required this.cookie,
  });

  final String token;
  final DateTime expiresAt;
  final Cookie cookie;
}

/// Issues a JWT token and builds the corresponding auth cookie.
AuthIssuedJwtToken issueAuthJwtToken({
  required JwtSessionOptions options,
  required Map<String, dynamic> claims,
}) {
  final issuer = JwtIssuer(options);
  final token = issuer.issue(claims);
  final expiresAt = issuer.expiry;
  final cookie = buildJwtTokenCookie(
    options.cookieName,
    token,
    expires: expiresAt,
  );
  return AuthIssuedJwtToken(token: token, expiresAt: expiresAt, cookie: cookie);
}

/// Reissues JWT token/cookie only when [claims] indicate refresh is required.
Future<AuthIssuedJwtToken?> refreshAuthJwtTokenIfNeeded({
  required JwtSessionOptions options,
  required Map<String, dynamic> claims,
  required Duration? updateAge,
  required FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> claims)
  resolveClaims,
  DateTime? now,
}) async {
  if (!shouldRefreshJwtClaims(claims, updateAge, now: now)) {
    return null;
  }

  final nextClaims = await Future<Map<String, dynamic>>.value(
    resolveClaims(Map<String, dynamic>.from(claims)),
  );
  return issueAuthJwtToken(options: options, claims: nextClaims);
}

/// Callback invoked after a JWT has been successfully verified.
typedef AuthJwtVerifiedCallback<TContext> =
    FutureOr<void> Function(JwtPayload payload, TContext context);

/// An exception thrown when JWT authentication fails.
class JwtAuthException implements Exception {
  /// Creates a [JwtAuthException] with the given [message].
  JwtAuthException(this.message);

  /// The error message describing why authentication failed.
  final String message;

  @override
  String toString() => 'JwtAuthException: $message';
}

/// The payload of a verified JWT, including its claims and headers.
class JwtPayload {
  /// Creates a [JwtPayload] with the given [token], [claims], and [headers].
  const JwtPayload({
    required this.token,
    required this.claims,
    required this.headers,
  });

  /// The verified [JsonWebToken].
  final JsonWebToken token;

  /// The claims extracted from the JWT.
  final Map<String, dynamic> claims;

  /// The headers extracted from the JWT.
  final Map<String, dynamic> headers;

  /// The subject claim of the JWT, if present.
  String? get subject => token.claims.subject;
}

/// Result of resolving and verifying a JWT bearer token from a header.
class JwtBearerVerificationResult {
  const JwtBearerVerificationResult({
    required this.token,
    required this.payload,
  });

  final String token;
  final JwtPayload payload;
}

/// Verified JWT session payload for auth session resolution.
class AuthVerifiedJwtSession {
  const AuthVerifiedJwtSession({
    required this.token,
    required this.payload,
    required this.user,
  });

  final String token;
  final JwtPayload payload;
  final AuthUser user;

  DateTime? get expiresAt => payload.token.claims.expiry?.toUtc();

  AuthSession toSession({
    AuthSessionStrategy strategy = AuthSessionStrategy.jwt,
  }) {
    return AuthSession(
      user: user,
      expiresAt: expiresAt,
      strategy: strategy,
      token: token,
    );
  }
}

/// Writes verified JWT payload attributes into a context attribute store.
void writeJwtPayloadAttributes(
  JwtPayload payload, {
  required void Function(String key, Object? value) setAttribute,
}) {
  setAttribute(jwtClaimsAttribute, payload.claims);
  setAttribute(jwtHeadersAttribute, payload.headers);
  setAttribute(jwtSubjectAttribute, payload.subject);
}

/// Configuration options for JWT verification.
class JwtOptions {
  /// Creates a [JwtOptions] instance with the specified parameters.
  const JwtOptions({
    this.enabled = true,
    this.issuer,
    this.audience = const <String>[],
    this.requiredClaims = const <String>[],
    this.jwksUri,
    this.inlineKeys = const <Map<String, dynamic>>[],
    this.algorithms = const <String>['RS256'],
    this.clockSkew = const Duration(seconds: 60),
    this.jwksCacheTtl = const Duration(minutes: 5),
    this.header = 'Authorization',
    this.bearerPrefix = 'Bearer ',
    this.cookieName = 'auth_token',
  });

  /// Whether JWT verification is enabled.
  final bool enabled;

  /// The expected issuer (`iss`) claim of the JWT.
  final String? issuer;

  /// The expected audience (`aud`) values for the JWT.
  final List<String> audience;

  /// The claim names that must be present in the JWT.
  final List<String> requiredClaims;

  /// The URI for fetching JSON Web Key Sets (JWKS).
  final Uri? jwksUri;

  /// Inline JSON Web Keys for verifying tokens.
  final List<Map<String, dynamic>> inlineKeys;

  /// The allowed algorithms for JWT signature verification.
  final List<String> algorithms;

  /// The allowed clock skew for token expiry and not-before validation.
  final Duration clockSkew;

  /// The cache time-to-live for fetched JWKS keys.
  final Duration jwksCacheTtl;

  /// The HTTP header used to extract the JWT.
  final String header;

  /// The prefix expected before the token in the authorization header.
  final String bearerPrefix;

  /// The cookie name used to read or write JWT tokens.
  final String cookieName;

  /// Creates a copy of this [JwtOptions] with the specified overrides.
  JwtOptions copyWith({
    bool? enabled,
    String? issuer,
    List<String>? audience,
    List<String>? requiredClaims,
    Uri? jwksUri,
    List<Map<String, dynamic>>? inlineKeys,
    List<String>? algorithms,
    Duration? clockSkew,
    Duration? jwksCacheTtl,
    String? header,
    String? bearerPrefix,
    String? cookieName,
  }) {
    return JwtOptions(
      enabled: enabled ?? this.enabled,
      issuer: issuer ?? this.issuer,
      audience: audience ?? this.audience,
      requiredClaims: requiredClaims ?? this.requiredClaims,
      jwksUri: jwksUri ?? this.jwksUri,
      inlineKeys: inlineKeys ?? this.inlineKeys,
      algorithms: algorithms ?? this.algorithms,
      clockSkew: clockSkew ?? this.clockSkew,
      jwksCacheTtl: jwksCacheTtl ?? this.jwksCacheTtl,
      header: header ?? this.header,
      bearerPrefix: bearerPrefix ?? this.bearerPrefix,
      cookieName: cookieName ?? this.cookieName,
    );
  }
}

/// Extracts and verifies a bearer JWT token from an authorization header.
Future<JwtBearerVerificationResult> verifyJwtBearerAuthorization({
  required String? authorizationHeader,
  required JwtVerifier verifier,
  String? bearerPrefix,
}) async {
  final options = verifier.options;
  final token = extractBearerToken(
    authorizationHeader,
    prefix: bearerPrefix ?? options.bearerPrefix,
  );
  if (token == null) {
    throw JwtAuthException('missing_token');
  }

  final payload = await verifier.verifyToken(token);
  return JwtBearerVerificationResult(token: token, payload: payload);
}

/// Verifies a JWT session token and returns auth user/session material.
///
/// Returns `null` when the token is absent, the secret is missing, or
/// verification fails.
Future<AuthVerifiedJwtSession?> verifyAuthJwtSessionToken({
  required String? token,
  required JwtSessionOptions options,
  http.Client? httpClient,
}) async {
  if (token == null || token.isEmpty) {
    return null;
  }
  if (options.secret.isEmpty) {
    return null;
  }

  final verifier = JwtVerifier(
    options: options.toVerifierOptions(),
    httpClient: httpClient,
  );

  JwtPayload payload;
  try {
    payload = await verifier.verifyToken(token);
  } on JwtAuthException {
    return null;
  }

  return AuthVerifiedJwtSession(
    token: token,
    payload: payload,
    user: authUserFromJwtClaims(payload.claims),
  );
}

/// Resolved JWT session payload after optional refresh processing.
class AuthResolvedJwtSession {
  const AuthResolvedJwtSession({
    required this.token,
    required this.user,
    required this.expiresAt,
    required this.payload,
    this.refreshCookie,
  });

  final String token;
  final AuthUser user;
  final DateTime? expiresAt;
  final JwtPayload payload;
  final Cookie? refreshCookie;

  AuthSession toSession({
    AuthSessionStrategy strategy = AuthSessionStrategy.jwt,
  }) {
    return AuthSession(
      user: user,
      expiresAt: expiresAt,
      strategy: strategy,
      token: token,
    );
  }
}

/// Verifies a JWT session token and optionally refreshes it when `iat` exceeds
/// [updateAge].
Future<AuthResolvedJwtSession?> resolveAuthJwtSessionWithRefresh({
  required String? token,
  required JwtSessionOptions options,
  required Duration? updateAge,
  FutureOr<Map<String, dynamic>> Function(
    Map<String, dynamic> claims,
    AuthUser user,
  )?
  resolveClaims,
  http.Client? httpClient,
  DateTime? now,
}) async {
  final verified = await verifyAuthJwtSessionToken(
    token: token,
    options: options,
    httpClient: httpClient,
  );
  if (verified == null) {
    return null;
  }

  var resolvedToken = verified.token;
  var resolvedExpiry = verified.expiresAt;
  Cookie? refreshCookie;

  final refreshed = await refreshAuthJwtTokenIfNeeded(
    options: options,
    claims: verified.payload.claims,
    updateAge: updateAge,
    now: now,
    resolveClaims: (claims) {
      if (resolveClaims == null) {
        return claims;
      }
      return resolveClaims(claims, verified.user);
    },
  );

  if (refreshed != null) {
    resolvedToken = refreshed.token;
    resolvedExpiry = refreshed.expiresAt;
    refreshCookie = refreshed.cookie;
  }

  return AuthResolvedJwtSession(
    token: resolvedToken,
    user: verified.user,
    expiresAt: resolvedExpiry,
    payload: verified.payload,
    refreshCookie: refreshCookie,
  );
}

/// Builds a symmetric [JsonWebKey] from a plain-text [secret].
JsonWebKey jwtSecretKey(String secret) {
  return JsonWebKey.fromJson({
    'kty': 'oct',
    'k': base64UrlEncode(utf8.encode(secret)),
  });
}

/// Configuration for JWT-based auth session issuance.
class JwtSessionOptions {
  /// Creates a [JwtSessionOptions] instance with the specified parameters.
  const JwtSessionOptions({
    required this.secret,
    this.issuer,
    this.audience,
    this.maxAge = const Duration(hours: 1),
    this.algorithm = 'HS256',
    this.cookieName = 'auth_token',
    this.header = 'Authorization',
    this.bearerPrefix = 'Bearer ',
  });

  /// The shared secret used for signing tokens.
  final String secret;

  /// The issuer (`iss`) claim to embed in issued tokens.
  final String? issuer;

  /// The audience (`aud`) claim to embed in issued tokens.
  final List<String>? audience;

  /// The maximum age of an issued token before it expires.
  final Duration maxAge;

  /// The signing algorithm to use.
  final String algorithm;

  /// The cookie name used to read or write JWT tokens.
  final String cookieName;

  /// The HTTP header used to pass the JWT.
  final String header;

  /// The prefix for the token in the authorization header.
  final String bearerPrefix;

  /// Converts this session configuration to a [JwtOptions] suitable for
  /// token verification.
  JwtOptions toVerifierOptions() {
    return JwtOptions(
      issuer: issuer,
      audience: audience ?? const <String>[],
      algorithms: [algorithm],
      inlineKeys: [jwtSecretKey(secret).toJson()],
      header: header,
      bearerPrefix: bearerPrefix,
      cookieName: cookieName,
    );
  }
}

/// A JWT issuer that produces signed tokens for auth sessions.
class JwtIssuer {
  /// Creates a [JwtIssuer] with the given session [options].
  JwtIssuer(this.options);

  /// The session configuration used for signing tokens.
  final JwtSessionOptions options;

  /// The expiry time for a token issued right now.
  DateTime get expiry => DateTime.now().add(options.maxAge);

  /// Issues a signed JWT containing the given [claims].
  String issue(Map<String, dynamic> claims) {
    final now = DateTime.now();
    final exp = now.add(options.maxAge).millisecondsSinceEpoch ~/ 1000;

    final key = jwtSecretKey(options.secret);
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        ...claims,
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': exp,
        if (options.issuer != null) 'iss': options.issuer,
        if (options.audience != null) 'aud': options.audience,
      };
    builder.addRecipient(key, algorithm: options.algorithm);
    return builder.build().toCompactSerialization();
  }
}

/// A JWT verifier that validates tokens against configured keys and claims.
class JwtVerifier {
  /// Creates a [JwtVerifier] with the given [options] and optional
  /// [httpClient].
  JwtVerifier({required JwtOptions options, http.Client? httpClient})
    : _options = options,
      _httpClient = httpClient ?? http.Client();

  final JwtOptions _options;
  final http.Client _httpClient;

  JsonWebKeyStore? _cachedStore;
  DateTime? _storeExpiry;

  /// The verification options this verifier was configured with.
  JwtOptions get options => _options;

  /// Verifies a JWT [token] string and returns its payload.
  Future<JwtPayload> verifyToken(String token) => _verify(token);

  /// Parses, verifies, and validates the [serialized] JWT string.
  Future<JwtPayload> _verify(String serialized) async {
    late JsonWebToken jwt;
    try {
      jwt = JsonWebToken.unverified(serialized);
    } catch (_) {
      throw JwtAuthException('invalid_format');
    }

    final keyStore = await _ensureKeyStore();
    final verified = await jwt.verify(
      keyStore,
      allowedArguments: _options.algorithms,
    );
    if (!verified) {
      throw JwtAuthException('signature_verification_failed');
    }

    final claims = jwt.claims;
    _validateClaims(claims);

    final segments = serialized.split('.');
    final headerSegment = segments.isNotEmpty ? segments.first : '';

    final payload = JwtPayload(
      token: jwt,
      claims: Map<String, dynamic>.from(claims.toJson()),
      headers: Map<String, dynamic>.from(
        _decodeHeader(headerSegment) ?? <String, dynamic>{},
      ),
    );
    return payload;
  }

  /// Returns a [JsonWebKeyStore] populated with configured keys.
  Future<JsonWebKeyStore> _ensureKeyStore() async {
    final now = DateTime.now();
    if (_cachedStore != null &&
        _storeExpiry != null &&
        now.isBefore(_storeExpiry!)) {
      return _cachedStore!;
    }

    final store = JsonWebKeyStore();
    var keyCount = 0;
    for (final key in _options.inlineKeys) {
      store.addKey(JsonWebKey.fromJson(key));
      keyCount += 1;
    }

    if (_options.jwksUri != null) {
      final response = await _httpClient.get(_options.jwksUri!);
      if (response.statusCode != 200) {
        throw JwtAuthException('jwks_fetch_failed');
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final keys = body['keys'];
      if (keys is! List) {
        throw JwtAuthException('jwks_missing_keys');
      }
      for (final entry in keys) {
        if (entry is Map<String, dynamic>) {
          store.addKey(JsonWebKey.fromJson(entry));
          keyCount += 1;
        }
      }
    }

    if (keyCount == 0) {
      throw JwtAuthException('no_keys_configured');
    }

    _cachedStore = store;
    _storeExpiry = DateTime.now().add(_options.jwksCacheTtl);
    return store;
  }

  /// Validates the token [claims] against the configured options.
  void _validateClaims(JsonWebTokenClaims claims) {
    final now = DateTime.now().toUtc();

    final issuer = _options.issuer;
    if (issuer != null) {
      final actual = claims.issuer?.toString();
      if (actual != issuer) {
        throw JwtAuthException('issuer_mismatch');
      }
    }

    if (_options.audience.isNotEmpty) {
      final aud = claims.audience ?? const <String>[];
      if (!_options.audience.any(aud.contains)) {
        throw JwtAuthException('audience_mismatch');
      }
    }

    final expiry = claims.expiry?.toUtc();
    if (expiry != null && expiry.add(_options.clockSkew).isBefore(now)) {
      throw JwtAuthException('token_expired');
    }

    final notBefore = claims.notBefore?.toUtc();
    if (notBefore != null &&
        notBefore.subtract(_options.clockSkew).isAfter(now)) {
      throw JwtAuthException('token_not_yet_valid');
    }

    for (final claim in _options.requiredClaims) {
      if (!claims.toJson().containsKey(claim)) {
        throw JwtAuthException('missing_claim_$claim');
      }
    }
  }

  /// Decodes a base64url-encoded JWT header [segment] into a JSON map.
  Map<String, dynamic>? _decodeHeader(String segment) {
    if (segment.isEmpty) return null;
    try {
      final normalized = _normalizeBase64(segment);
      final bytes = base64Url.decode(normalized);
      return json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Pads a base64url [input] string with `=` characters.
  String _normalizeBase64(String input) {
    final padding = (4 - input.length % 4) % 4;
    return input.padRight(input.length + padding, '=');
  }
}
