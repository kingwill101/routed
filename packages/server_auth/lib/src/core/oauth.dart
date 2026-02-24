import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'bearer.dart' show extractBearerToken;

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
  OAuth2Exception(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'OAuth2Exception($statusCode): $message';
}

/// Result of validating a bearer authorization header via introspection.
class OAuthBearerValidationResult {
  OAuthBearerValidationResult({required this.token, required this.result});

  final String token;
  final OAuthIntrospectionResult result;
}

/// Represents the response from an OAuth2 token endpoint.
class OAuthTokenResponse {
  OAuthTokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.refreshToken,
    this.scope,
    required this.raw,
  });

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

  final String accessToken;
  final String tokenType;
  final int? expiresIn;
  final String? refreshToken;
  final String? scope;
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

/// Parsed response from an RFC 7662 token introspection endpoint.
class OAuthIntrospectionResult {
  OAuthIntrospectionResult({required this.active, required this.raw});

  final bool active;
  final Map<String, dynamic> raw;

  String? get subject => raw['sub'] as String?;

  String? get scope => raw['scope'] as String?;

  DateTime? get expiresAt {
    final exp = raw['exp'];
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    }
    return null;
  }

  DateTime? get notBefore {
    final nbf = raw['nbf'];
    if (nbf is num) {
      return DateTime.fromMillisecondsSinceEpoch(nbf.toInt() * 1000);
    }
    return null;
  }
}

/// Options for RFC 7662 token introspection.
class OAuthIntrospectionOptions {
  const OAuthIntrospectionOptions({
    required this.endpoint,
    this.clientId,
    this.clientSecret,
    this.tokenTypeHint,
    this.cacheTtl = const Duration(seconds: 30),
    this.clockSkew = const Duration(seconds: 60),
    this.additionalParameters = const <String, String>{},
  });

  final Uri endpoint;
  final String? clientId;
  final String? clientSecret;
  final String? tokenTypeHint;
  final Duration cacheTtl;
  final Duration clockSkew;
  final Map<String, String> additionalParameters;
}

class _CachedIntrospection {
  _CachedIntrospection(this.result, this.expiresAt);

  final OAuthIntrospectionResult result;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Reusable RFC 7662 token introspection runtime with in-memory caching.
class OAuth2TokenIntrospector {
  OAuth2TokenIntrospector(this.options, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final OAuthIntrospectionOptions options;
  final http.Client _httpClient;
  final Map<String, _CachedIntrospection> _cache =
      <String, _CachedIntrospection>{};

  Future<OAuthIntrospectionResult> introspect(String token) async {
    final cached = _cache[token];
    if (cached != null && !cached.isExpired) {
      return cached.result;
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

    final response = await _httpClient.post(
      options.endpoint,
      headers: headers,
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuth2Exception(
        'Introspection endpoint responded with ${response.statusCode}',
        response.statusCode,
      );
    }

    final Map<String, dynamic> jsonResponse =
        json.decode(response.body) as Map<String, dynamic>;
    final result = OAuthIntrospectionResult(
      active: jsonResponse['active'] == true,
      raw: jsonResponse,
    );
    _cache[token] = _CachedIntrospection(
      result,
      DateTime.now().add(options.cacheTtl),
    );
    return result;
  }

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

    return result;
  }
}

/// Generic OAuth2 client for token exchange and userinfo requests.
class OAuth2Client {
  OAuth2Client({
    required this.tokenEndpoint,
    this.clientId,
    this.clientSecret,
    this.defaultHeaders = const <String, String>{},
    this.useBasicAuth = true,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final Uri tokenEndpoint;
  final String? clientId;
  final String? clientSecret;
  final Map<String, String> defaultHeaders;
  final bool useBasicAuth;
  final http.Client _httpClient;

  Future<OAuthTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
    String? codeVerifier,
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri.toString(),
      'scope': ?scope,
      'code_verifier': ?codeVerifier,
      'client_id': ?clientId,
      ...?additionalParameters,
    };
    return _sendTokenRequest(body);
  }

  Future<OAuthTokenResponse> clientCredentials({
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      'grant_type': 'client_credentials',
      'scope': ?scope,
      'client_id': ?clientId,
      ...?additionalParameters,
    };
    return _sendTokenRequest(body);
  }

  Future<OAuthTokenResponse> refreshToken({
    required String refreshToken,
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': ?scope,
      'client_id': ?clientId,
      ...?additionalParameters,
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

    final response = await _httpClient.post(
      tokenEndpoint,
      headers: headers,
      body: body,
    );

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

    final contentType =
        response.headers[HttpHeaders.contentTypeHeader]?.toLowerCase() ?? '';
    Map<String, dynamic> jsonResponse;
    if (contentType.contains('application/json') ||
        responseBody.startsWith('{')) {
      jsonResponse = json.decode(responseBody) as Map<String, dynamic>;
    } else {
      final parsed = Uri.splitQueryString(responseBody);
      jsonResponse = parsed.map((key, value) => MapEntry(key, value));
    }
    return OAuthTokenResponse.fromJson(jsonResponse);
  }

  Future<Map<String, dynamic>> fetchUserInfo(
    Uri endpoint,
    String accessToken,
  ) async {
    final response = await _httpClient.get(
      endpoint,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $accessToken',
        ...defaultHeaders,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuth2Exception(
        'Userinfo endpoint responded with ${response.statusCode}',
        response.statusCode,
      );
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }
}
