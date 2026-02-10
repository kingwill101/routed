import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

export 'package:jose/jose.dart';

/// Attribute key for JWT claims in the request context.
const String jwtClaimsAttribute = 'auth.jwt.claims';

/// Attribute key for JWT headers in the request context.
const String jwtHeadersAttribute = 'auth.jwt.headers';

/// Attribute key for the JWT subject in the request context.
const String jwtSubjectAttribute = 'auth.jwt.subject';

/// An exception thrown when JWT authentication fails.
///
/// Contains a [message] describing the specific authentication failure,
/// such as `'invalid_format'`, `'token_expired'`, or `'issuer_mismatch'`.
class JwtAuthException implements Exception {
  /// Creates a [JwtAuthException] with the given [message].
  JwtAuthException(this.message);

  /// The error message describing why authentication failed.
  final String message;

  @override
  String toString() => 'JwtAuthException: $message';
}

/// The payload of a verified JWT, including its claims and headers.
///
/// Instances of this class are produced by [JwtVerifier.verifyToken] after
/// successful token verification. The [claims] and [headers] maps provide
/// access to the decoded JWT content.
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

/// Callback invoked after a JWT has been successfully verified.
///
/// Receives the verified [payload] and the current request [context],
/// allowing additional processing such as loading user data or
/// enriching the request context.
typedef JwtOnVerified =
    FutureOr<void> Function(JwtPayload payload, EngineContext context);

/// Configuration options for JWT verification.
///
/// Controls how tokens are extracted, validated, and which keys are used
/// for signature verification. Supports both inline keys and remote JWKS
/// endpoints.
///
/// ```dart
/// final options = JwtOptions(
///   issuer: 'https://auth.example.com',
///   audience: ['my-api'],
///   jwksUri: Uri.parse('https://auth.example.com/.well-known/jwks.json'),
/// );
/// ```
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
    this.cookieName = 'routed_auth_token',
  });

  /// Whether JWT verification is enabled.
  ///
  /// When `false`, the [JwtVerifier] middleware passes requests through
  /// without performing any token validation.
  final bool enabled;

  /// The expected issuer (`iss`) claim of the JWT.
  ///
  /// If non-null, tokens with a different issuer are rejected with an
  /// `'issuer_mismatch'` error.
  final String? issuer;

  /// The expected audience (`aud`) values for the JWT.
  ///
  /// If non-empty, at least one of these values must appear in the token's
  /// audience claim. Otherwise, the token is rejected with an
  /// `'audience_mismatch'` error.
  final List<String> audience;

  /// The claim names that must be present in the JWT.
  ///
  /// If any of these claims are missing, the token is rejected with a
  /// `'missing_claim_<name>'` error.
  final List<String> requiredClaims;

  /// The URI for fetching JSON Web Key Sets (JWKS).
  ///
  /// When provided, keys are fetched from this endpoint and cached
  /// according to [jwksCacheTtl].
  final Uri? jwksUri;

  /// Inline JSON Web Keys for verifying tokens.
  ///
  /// Each entry should be a valid JWK JSON map. These keys are used in
  /// addition to any keys fetched from [jwksUri].
  final List<Map<String, dynamic>> inlineKeys;

  /// The allowed algorithms for JWT signature verification.
  ///
  /// Defaults to `['RS256']`. Tokens signed with other algorithms are
  /// rejected.
  final List<String> algorithms;

  /// The allowed clock skew for token expiry and not-before validation.
  ///
  /// Accounts for minor clock differences between the issuer and this
  /// server. Defaults to 60 seconds.
  final Duration clockSkew;

  /// The cache time-to-live for fetched JWKS keys.
  ///
  /// After this duration elapses, the key store is refreshed from the
  /// [jwksUri] on the next verification request. Defaults to 5 minutes.
  final Duration jwksCacheTtl;

  /// The HTTP header used to extract the JWT.
  ///
  /// Defaults to `'Authorization'`.
  final String header;

  /// The prefix expected before the token in the authorization header.
  ///
  /// Defaults to `'Bearer '`. The prefix is stripped to extract the raw
  /// token string.
  final String bearerPrefix;

  /// The cookie name used to read or write JWT tokens.
  ///
  /// Defaults to `'routed_auth_token'`.
  final String cookieName;

  /// Creates a copy of this [JwtOptions] with the specified overrides.
  ///
  /// Any parameter that is `null` retains its current value.
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

/// Builds a symmetric [JsonWebKey] from a plain-text [secret].
///
/// The secret is UTF-8 encoded and then base64url-encoded to produce
/// a JWK with key type `'oct'`, suitable for HMAC-based algorithms
/// such as HS256.
///
/// ```dart
/// final key = jwtSecretKey('my-secret');
/// ```
JsonWebKey jwtSecretKey(String secret) {
  return JsonWebKey.fromJson({
    'kty': 'oct',
    'k': base64UrlEncode(utf8.encode(secret)),
  });
}

/// Configuration for JWT-based auth session issuance.
///
/// Provides the signing [secret], token lifetime, and related settings
/// used by [JwtIssuer] to produce signed tokens. Can be converted to
/// a [JwtOptions] for verification via [toVerifierOptions].
///
/// ```dart
/// final sessionOptions = JwtSessionOptions(
///   secret: 'my-signing-secret',
///   issuer: 'https://myapp.example.com',
///   maxAge: Duration(hours: 2),
/// );
/// ```
class JwtSessionOptions {
  /// Creates a [JwtSessionOptions] instance with the specified parameters.
  const JwtSessionOptions({
    required this.secret,
    this.issuer,
    this.audience,
    this.maxAge = const Duration(hours: 1),
    this.algorithm = 'HS256',
    this.cookieName = 'routed_auth_token',
    this.header = HttpHeaders.authorizationHeader,
    this.bearerPrefix = 'Bearer ',
  });

  /// The shared secret used for signing tokens.
  final String secret;

  /// The issuer (`iss`) claim to embed in issued tokens.
  final String? issuer;

  /// The audience (`aud`) claim to embed in issued tokens.
  final List<String>? audience;

  /// The maximum age of an issued token before it expires.
  ///
  /// Defaults to one hour.
  final Duration maxAge;

  /// The signing algorithm to use.
  ///
  /// Defaults to `'HS256'`.
  final String algorithm;

  /// The cookie name used to read or write JWT tokens.
  ///
  /// Defaults to `'routed_auth_token'`.
  final String cookieName;

  /// The HTTP header used to pass the JWT.
  ///
  /// Defaults to the standard `Authorization` header.
  final String header;

  /// The prefix for the token in the authorization header.
  ///
  /// Defaults to `'Bearer '`.
  final String bearerPrefix;

  /// Converts this session configuration to a [JwtOptions] suitable for
  /// token verification.
  ///
  /// Produces inline keys derived from [secret] so that tokens issued
  /// with this configuration can be verified without an external JWKS
  /// endpoint.
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
///
/// Uses the signing secret and configuration from [options] to build
/// and sign [JsonWebToken]s with the specified claims.
///
/// ```dart
/// final issuer = JwtIssuer(sessionOptions);
/// final token = issuer.issue({'sub': 'user-123', 'role': 'admin'});
/// ```
class JwtIssuer {
  /// Creates a [JwtIssuer] with the given session [options].
  JwtIssuer(this.options);

  /// The session configuration used for signing tokens.
  final JwtSessionOptions options;

  /// The expiry time for a token issued right now.
  DateTime get expiry => DateTime.now().add(options.maxAge);

  /// Issues a signed JWT containing the given [claims].
  ///
  /// Automatically adds `iat` (issued at) and `exp` (expiration) claims
  /// based on the current time and [JwtSessionOptions.maxAge]. If
  /// [JwtSessionOptions.issuer] or [JwtSessionOptions.audience] are set,
  /// the `iss` and `aud` claims are included as well.
  ///
  /// Returns the compact serialized JWT string.
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
///
/// Supports both inline keys and remote JWKS endpoints for signature
/// verification, with automatic key caching. Can be used directly via
/// [verifyToken] or as a [Middleware] via [middleware].
///
/// ```dart
/// final verifier = JwtVerifier(options: jwtOptions);
/// final payload = await verifier.verifyToken(tokenString);
/// print(payload.subject);
/// ```
class JwtVerifier {
  /// Creates a [JwtVerifier] with the given [options] and optional
  /// [httpClient].
  ///
  /// If [httpClient] is not provided, a default [http.Client] is used
  /// for fetching remote JWKS keys.
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
  ///
  /// Parses the token, verifies its signature against configured keys,
  /// and validates claims such as issuer, audience, expiry, and required
  /// claims.
  ///
  /// Throws a [JwtAuthException] if the token is malformed, the signature
  /// is invalid, or any claim validation fails.
  Future<JwtPayload> verifyToken(String token) => _verify(token);

  /// Creates a [Middleware] that authenticates requests using JWT.
  ///
  /// Extracts the token from the configured HTTP header, verifies it,
  /// and sets the [jwtClaimsAttribute], [jwtHeadersAttribute], and
  /// [jwtSubjectAttribute] on the request context.
  ///
  /// If [onVerified] is provided, it is called after successful
  /// verification and before the next handler in the chain.
  ///
  /// Returns an HTTP 401 response with a `WWW-Authenticate` header if
  /// the token is missing or invalid.
  Middleware middleware({JwtOnVerified? onVerified}) {
    return (EngineContext ctx, Next next) async {
      if (!_options.enabled) {
        return next();
      }

      final headerValue = ctx.request.header(_options.header);
      final token = _extractToken(headerValue, _options.bearerPrefix);
      if (token == null) {
        _writeUnauthorized(ctx, 'missing_token');
        return ctx.response;
      }

      try {
        final payload = await verifyToken(token);
        ctx.request
          ..setAttribute(jwtClaimsAttribute, payload.claims)
          ..setAttribute(jwtHeadersAttribute, payload.headers)
          ..setAttribute(jwtSubjectAttribute, payload.subject);

        if (onVerified != null) {
          await onVerified(payload, ctx);
        }

        return await next();
      } on JwtAuthException catch (error) {
        _writeUnauthorized(ctx, error.message);
        return ctx.response;
      }
    };
  }

  /// Writes an HTTP 401 Unauthorized response with the given [reason].
  void _writeUnauthorized(EngineContext ctx, String reason) {
    ctx.response.headers.set(
      'WWW-Authenticate',
      'Bearer error="invalid_token", error_description="$reason"',
    );
    if (!ctx.response.isClosed) {
      ctx.errorResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Unauthorized',
      );
    }
  }

  /// Parses, verifies, and validates the [serialized] JWT string.
  ///
  /// Throws a [JwtAuthException] on any verification or validation failure.
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
  ///
  /// Uses a cached store if it has not yet expired. Otherwise, rebuilds
  /// the store from inline keys and, if configured, fetches keys from
  /// the remote JWKS endpoint.
  ///
  /// Throws a [JwtAuthException] if no keys are available or if the
  /// JWKS fetch fails.
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
  ///
  /// Checks issuer, audience, expiry, not-before, and required claims.
  /// Throws a [JwtAuthException] if any validation check fails.
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
  ///
  /// Returns `null` if the segment is empty or cannot be decoded.
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

  /// Pads a base64url [input] string with `=` characters to make its
  /// length a multiple of 4.
  String _normalizeBase64(String input) {
    final padding = (4 - input.length % 4) % 4;
    return input.padRight(input.length + padding, '=');
  }

  /// Extracts the raw token from a [headerValue] by stripping the [prefix].
  ///
  /// Returns `null` if the header is missing, empty, does not start with
  /// the expected prefix, or contains only whitespace after the prefix.
  String? _extractToken(String? headerValue, String prefix) {
    if (headerValue == null || headerValue.isEmpty) {
      return null;
    }
    if (!headerValue.startsWith(prefix)) {
      return null;
    }
    final token = headerValue.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }
}

/// Creates a JWT authentication [Middleware] with the given [options].
///
/// This is a convenience function that constructs a [JwtVerifier] and
/// returns its middleware. Optionally accepts an [onVerified] callback
/// invoked after successful token verification, and a custom [httpClient]
/// for fetching remote JWKS keys.
///
/// ```dart
/// final auth = jwtAuthentication(
///   JwtOptions(issuer: 'https://auth.example.com'),
///   onVerified: (payload, ctx) {
///     print('Authenticated user: ${payload.subject}');
///   },
/// );
/// ```
Middleware jwtAuthentication(
  JwtOptions options, {
  JwtOnVerified? onVerified,
  http.Client? httpClient,
}) {
  return JwtVerifier(
    options: options,
    httpClient: httpClient,
  ).middleware(onVerified: onVerified);
}
