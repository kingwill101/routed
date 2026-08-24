import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

import 'bearer.dart' show extractBearerToken;

/// Maximum response size accepted from OAuth token and user-info endpoints.
///
/// Provider adapters that perform additional OAuth requests should apply the
/// same bound before decoding a response body.
const int maxOAuthResponseCharacters = 1024 * 1024;

/// Attribute key used to store the OAuth2 access token.
const String oauthTokenAttribute = 'auth.oauth.access_token';

/// Attribute key used to store OAuth2 claims.
const String oauthClaimsAttribute = 'auth.oauth.claims';

/// Attribute key used to store OAuth2 scope values.
const String oauthScopeAttribute = 'auth.oauth.scope';

/// Callback invoked after token introspection has validated a request.
typedef AuthOAuthValidatedCallback<TContext> =
    FutureOr<void> Function(OAuthIntrospectionResult result, TContext context);

/// Represents an exception that occurs during OAuth2 operations.
class OAuth2Exception implements Exception {
  /// Creates an OAuth2 exception with an optional HTTP [statusCode].
  OAuth2Exception(this.message, [this.statusCode]);

  /// Human-readable description of the failure.
  final String message;

  /// HTTP status returned by the remote endpoint, when available.
  final int? statusCode;

  @override
  String toString() => 'OAuth2Exception($statusCode): $message';
}

/// Result of validating a bearer authorization header via introspection.
class OAuthBearerValidationResult {
  /// Creates a bearer-validation result.
  OAuthBearerValidationResult({required this.token, required this.result});

  /// Bearer token extracted from the authorization header.
  final String token;

  /// Introspection result associated with [token].
  final OAuthIntrospectionResult result;
}

/// Writes OAuth validation attributes into a context attribute store.
void writeOAuthValidationAttributes(
  OAuthBearerValidationResult validation, {
  required void Function(String key, Object? value) setAttribute,
}) {
  setAttribute(oauthTokenAttribute, validation.token);
  setAttribute(oauthClaimsAttribute, validation.result.raw);
  setAttribute(oauthScopeAttribute, validation.result.scope);
}

/// Represents the response from an OAuth2 token endpoint.
class OAuthTokenResponse {
  /// Creates a token-endpoint response.
  OAuthTokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.refreshToken,
    this.scope,
    required this.raw,
  });

  /// Creates a token response from an OAuth token-endpoint payload.
  factory OAuthTokenResponse.fromJson(Map<String, dynamic> json) {
    return OAuthTokenResponse(
      accessToken: json['access_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: (json['expires_in'] is num)
          ? (json['expires_in'] as num).toInt()
          : null,
      refreshToken: json['refresh_token'] as String?,
      scope: json['scope'] as String?,
      raw: json,
    );
  }

  /// Access token returned by the endpoint.
  final String accessToken;

  /// Token type returned by the endpoint, usually `Bearer`.
  final String tokenType;

  /// Access-token lifetime in seconds, when supplied.
  final int? expiresIn;

  /// Refresh token returned by the endpoint, when supplied.
  final String? refreshToken;

  /// Space-delimited scope returned by the endpoint, when supplied.
  final String? scope;

  /// Original decoded response payload.
  final Map<String, dynamic> raw;
}

/// Resolves token expiration from OAuth `expires_in` seconds.
DateTime? oauthTokenExpiryFromSeconds(int? expiresIn, {DateTime? now}) {
  if (expiresIn == null) {
    return null;
  }
  return (now ?? DateTime.now()).add(Duration(seconds: expiresIn));
}

/// Validates a bearer authorization header using [OAuth2TokenIntrospector].
Future<OAuthBearerValidationResult> validateOAuthBearerAuthorization({
  required String? authorizationHeader,
  required OAuth2TokenIntrospector introspector,
  String bearerPrefix = 'Bearer ',
}) async {
  final token = extractBearerToken(authorizationHeader, prefix: bearerPrefix);
  if (token == null) {
    throw OAuth2Exception('missing token');
  }

  final result = await introspector.validate(token);
  return OAuthBearerValidationResult(token: token, result: result);
}

/// Validates a bearer token, writes attributes, and runs validation callback.
Future<OAuthBearerValidationResult>
validateOAuthBearerAuthorizationAndWriteAttributes<TContext>({
  required String? authorizationHeader,
  required OAuth2TokenIntrospector introspector,
  required void Function(String key, Object? value) setAttribute,
  required TContext context,
  AuthOAuthValidatedCallback<TContext>? onValidated,
  String bearerPrefix = 'Bearer ',
}) async {
  final validation = await validateOAuthBearerAuthorization(
    authorizationHeader: authorizationHeader,
    introspector: introspector,
    bearerPrefix: bearerPrefix,
  );

  writeOAuthValidationAttributes(validation, setAttribute: setAttribute);

  if (onValidated != null) {
    await onValidated(validation.result, context);
  }

  return validation;
}

/// Parsed response from an RFC 7662 token introspection endpoint.
class OAuthIntrospectionResult {
  /// Creates an introspection result from its active flag and raw claims.
  OAuthIntrospectionResult({required this.active, required this.raw});

  /// Whether the introspection endpoint considers the token active.
  final bool active;

  /// Decoded claims returned by the introspection endpoint.
  final Map<String, dynamic> raw;

  /// Subject claim identifying the token owner, when present.
  String? get subject => raw['sub'] as String?;

  /// Space-delimited scope claim, when present.
  String? get scope => raw['scope'] as String?;

  /// Audience values normalized from the `aud` claim.
  List<String> get audience {
    final value = raw['aud'];
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    if (value is List) {
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  /// Expiration time decoded from the numeric `exp` claim.
  DateTime? get expiresAt {
    final exp = raw['exp'];
    if (exp is num) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// Not-before time decoded from the numeric `nbf` claim.
  DateTime? get notBefore {
    final nbf = raw['nbf'];
    if (nbf is num) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(nbf.toInt() * 1000);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }
}

/// Options for RFC 7662 token introspection.
class OAuthIntrospectionOptions {
  /// Creates introspection options for [endpoint].
  const OAuthIntrospectionOptions({
    required this.endpoint,
    this.clientId,
    this.clientSecret,
    this.tokenTypeHint,
    this.cacheTtl = Duration.zero,
    this.maxCacheEntries = 1024,
    this.clockSkew = const Duration(seconds: 60),
    this.requestTimeout = const Duration(seconds: 10),
    this.requiredAudience,
    this.additionalParameters = const <String, String>{},
  });

  /// Introspection endpoint that receives token checks.
  final Uri endpoint;

  /// Client identifier used for endpoint authentication, when supplied.
  final String? clientId;

  /// Client secret used for endpoint authentication, when supplied.
  final String? clientSecret;

  /// Optional `token_type_hint` sent with each request.
  final String? tokenTypeHint;

  /// Duration for which successful results remain cached.
  final Duration cacheTtl;

  /// Maximum number of distinct token digests retained by the local cache.
  ///
  /// Introspection caching is optional, but when enabled the cache must remain
  /// bounded because callers can present an unlimited number of distinct
  /// bearer tokens. The oldest entry is evicted when this limit is reached.
  final int maxCacheEntries;

  /// Clock tolerance applied to `exp` and `nbf` claims.
  final Duration clockSkew;

  /// Maximum time allowed for an introspection request.
  final Duration requestTimeout;

  /// Audience that every active token must contain, when configured.
  final String? requiredAudience;

  /// Additional form parameters sent to the endpoint.
  final Map<String, String> additionalParameters;
}

/// Materializes OAuth introspection options from typed provider fields.
///
/// Returns `null` when introspection is disabled or [endpoint] is missing.
OAuthIntrospectionOptions? materializeOAuthIntrospectionOptions({
  required bool enabled,
  required Uri? endpoint,
  String? clientId,
  String? clientSecret,
  String? tokenTypeHint,
  Duration cacheTtl = Duration.zero,
  int maxCacheEntries = 1024,
  Duration clockSkew = const Duration(seconds: 60),
  Duration requestTimeout = const Duration(seconds: 10),
  String? requiredAudience,
  Map<String, String> additionalParameters = const <String, String>{},
}) {
  if (!enabled || endpoint == null) {
    return null;
  }

  return OAuthIntrospectionOptions(
    endpoint: endpoint,
    clientId: _optionalTrimmed(clientId),
    clientSecret: _optionalTrimmed(clientSecret),
    tokenTypeHint: _optionalTrimmed(tokenTypeHint),
    cacheTtl: cacheTtl,
    maxCacheEntries: maxCacheEntries,
    clockSkew: clockSkew,
    requestTimeout: requestTimeout,
    requiredAudience: requiredAudience?.trim().isEmpty == true
        ? null
        : requiredAudience?.trim(),
    additionalParameters: additionalParameters,
  );
}

String? _optionalTrimmed(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _CachedIntrospection {
  _CachedIntrospection(this.result, this.expiresAt);

  final OAuthIntrospectionResult result;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Reusable RFC 7662 token introspection runtime with in-memory caching.
class OAuth2TokenIntrospector {
  /// Creates an introspector with [options] and an optional HTTP client.
  OAuth2TokenIntrospector(this.options, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// Options controlling endpoint authentication, validation, and caching.
  final OAuthIntrospectionOptions options;
  final http.Client _httpClient;
  final Map<String, _CachedIntrospection> _cache =
      <String, _CachedIntrospection>{};

  /// Sends [token] to the introspection endpoint and returns its claims.
  ///
  /// Successful results may be served from the configured in-memory cache.
  /// Throws [OAuth2Exception] for non-success responses or malformed payloads.
  Future<OAuthIntrospectionResult> introspect(String token) async {
    final cacheKey = sha256.convert(utf8.encode(token)).toString();
    if (options.cacheTtl > Duration.zero) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired) {
        return cached.result;
      }
      _cache.removeWhere((_, entry) => entry.isExpired);
    }

    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
    };
    if (options.clientId != null && options.clientSecret != null) {
      final credentials = base64Encode(
        utf8.encode('${options.clientId}:${options.clientSecret}'),
      );
      headers[HttpHeaders.authorizationHeader] = 'Basic $credentials';
    }

    final body = <String, String>{
      'token': token,
      if (options.tokenTypeHint != null)
        'token_type_hint': options.tokenTypeHint!,
      ...options.additionalParameters,
    };

    final response = await _httpClient
        .post(options.endpoint, headers: headers, body: body)
        .timeout(options.requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuth2Exception(
        'Introspection endpoint responded with ${response.statusCode}',
        response.statusCode,
      );
    }

    final jsonResponse = _decodeJsonObject(
      response.body,
      errorCode: 'invalid_introspection_response',
    );
    final result = OAuthIntrospectionResult(
      active: jsonResponse['active'] == true,
      raw: jsonResponse,
    );
    if (options.cacheTtl > Duration.zero) {
      _cache.remove(cacheKey);
      while (_cache.length >= options.maxCacheEntries && _cache.isNotEmpty) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cacheKey] = _CachedIntrospection(
        result,
        DateTime.now().add(options.cacheTtl),
      );
    }
    return result;
  }

  /// Introspects [token] and enforces its active, time, and audience claims.
  ///
  /// Throws [OAuth2Exception] when the token is inactive, outside its allowed
  /// time window, or missing the configured audience.
  Future<OAuthIntrospectionResult> validate(String token) async {
    final result = await introspect(token);
    if (!result.active) {
      throw OAuth2Exception('token inactive');
    }

    final now = DateTime.now().toUtc();
    final expiresAt = result.expiresAt?.toUtc();
    if (expiresAt != null && expiresAt.add(options.clockSkew).isBefore(now)) {
      throw OAuth2Exception('token expired');
    }

    final notBefore = result.notBefore?.toUtc();
    if (notBefore != null &&
        notBefore.subtract(options.clockSkew).isAfter(now)) {
      throw OAuth2Exception('token not yet valid');
    }

    final requiredAudience = options.requiredAudience;
    if (requiredAudience != null &&
        !result.audience.contains(requiredAudience)) {
      throw OAuth2Exception('token audience mismatch');
    }

    return result;
  }
}

/// Generic OAuth2 client for token exchange and userinfo requests.
class OAuth2Client {
  /// Creates an OAuth2 client for [tokenEndpoint].
  OAuth2Client({
    required this.tokenEndpoint,
    this.clientId,
    this.clientSecret,
    this.defaultHeaders = const <String, String>{},
    this.useBasicAuth = true,
    this.requestTimeout = const Duration(seconds: 10),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Token endpoint used by grant and refresh operations.
  final Uri tokenEndpoint;

  /// OAuth client identifier, when supplied.
  final String? clientId;

  /// OAuth client secret, when supplied.
  final String? clientSecret;

  /// Headers merged into requests sent by this client.
  final Map<String, String> defaultHeaders;

  /// Whether client credentials are sent using HTTP Basic authentication.
  final bool useBasicAuth;

  /// Maximum time allowed for each HTTP request.
  final Duration requestTimeout;
  final http.Client _httpClient;

  /// Exchanges an authorization [code] for an access token.
  ///
  /// Includes [redirectUri] and the optional PKCE [codeVerifier], [scope], and
  /// [additionalParameters] in the token request.
  Future<OAuthTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
    String? codeVerifier,
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      ...?additionalParameters,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri.toString(),
      'scope': ?scope,
      'code_verifier': ?codeVerifier,
      'client_id': ?clientId,
    };
    return _sendTokenRequest(body);
  }

  /// Requests an access token using the client-credentials grant.
  Future<OAuthTokenResponse> clientCredentials({
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      ...?additionalParameters,
      'grant_type': 'client_credentials',
      'scope': ?scope,
      'client_id': ?clientId,
    };
    return _sendTokenRequest(body);
  }

  /// Exchanges [refreshToken] for a new access token.
  Future<OAuthTokenResponse> refreshToken({
    required String refreshToken,
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      ...?additionalParameters,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': ?scope,
      'client_id': ?clientId,
    };
    return _sendTokenRequest(body);
  }

  Future<OAuthTokenResponse> _sendTokenRequest(Map<String, String> body) async {
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      ...defaultHeaders,
    };
    if (clientId != null && clientSecret != null && useBasicAuth) {
      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));
      headers['Authorization'] = 'Basic $credentials';
    }
    if (!useBasicAuth) {
      body.addAll({'client_id': ?clientId, 'client_secret': ?clientSecret});
    }

    final response = await _httpClient
        .post(tokenEndpoint, headers: headers, body: body)
        .timeout(requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuth2Exception(
        'Token endpoint responded with ${response.statusCode}',
        response.statusCode,
      );
    }

    final responseBody = response.body.trim();
    if (responseBody.isEmpty) {
      throw OAuth2Exception('Token endpoint returned empty response');
    }
    if (responseBody.length > maxOAuthResponseCharacters) {
      throw OAuth2Exception('invalid_token_endpoint_response');
    }

    final contentType =
        response.headers[HttpHeaders.contentTypeHeader]?.toLowerCase() ?? '';
    final Map<String, dynamic> jsonResponse;
    try {
      if (contentType.contains('application/json') ||
          responseBody.startsWith('{')) {
        jsonResponse = _decodeJsonObject(
          responseBody,
          errorCode: 'invalid_token_endpoint_response',
        );
      } else {
        final parsed = Uri.splitQueryString(responseBody);
        jsonResponse = parsed.map((key, value) => MapEntry(key, value));
      }
    } catch (error) {
      if (error is OAuth2Exception) rethrow;
      throw OAuth2Exception('invalid_token_endpoint_response');
    }

    try {
      final token = OAuthTokenResponse.fromJson(jsonResponse);
      if (token.accessToken.trim().isEmpty) {
        throw OAuth2Exception('invalid_token_endpoint_response');
      }
      return token;
    } catch (error) {
      if (error is OAuth2Exception) rethrow;
      throw OAuth2Exception('invalid_token_endpoint_response');
    }
  }

  /// Fetches and decodes a JSON user-info response using [accessToken].
  Future<Map<String, dynamic>> fetchUserInfo(
    Uri endpoint,
    String accessToken,
  ) async {
    final response = await _httpClient
        .get(
          endpoint,
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $accessToken',
            ...defaultHeaders,
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuth2Exception(
        'Userinfo endpoint responded with ${response.statusCode}',
        response.statusCode,
      );
    }
    return _decodeJsonObject(
      response.body,
      errorCode: 'invalid_userinfo_response',
    );
  }
}

Map<String, dynamic> _decodeJsonObject(
  String body, {
  required String errorCode,
}) {
  if (body.length > maxOAuthResponseCharacters) {
    throw OAuth2Exception(errorCode);
  }
  try {
    final decoded = json.decode(body);
    if (decoded is! Map) {
      throw const FormatException('expected JSON object');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } catch (_) {
    throw OAuth2Exception(errorCode);
  }
}
