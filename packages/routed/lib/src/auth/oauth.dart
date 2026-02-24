import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart'
    show OAuth2Exception;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

/// Attribute key for storing the OAuth2 access token in the request context.
const String oauthTokenAttribute = 'auth.oauth.access_token';

/// Attribute key for storing OAuth2 claims in the request context.
const String oauthClaimsAttribute = 'auth.oauth.claims';

/// Attribute key for storing OAuth2 scopes in the request context.
const String oauthScopeAttribute = 'auth.oauth.scope';

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

typedef OAuthOnValidated =
    FutureOr<void> Function(
      OAuthIntrospectionResult result,
      EngineContext context,
    );

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

/// Creates a middleware for OAuth2 token introspection.
///
/// This middleware validates incoming OAuth2 tokens using the provided
/// [options]. If the token is valid, its claims and attributes are added
/// to the request context.
///
/// - [options]: Configuration options for the introspection.
/// - [onValidated]: Optional callback invoked after successful validation.
/// - [httpClient]: Optional HTTP client for making introspection requests.
///
/// Returns a middleware function that can be used in the routing pipeline.
///
/// Example:
/// ```dart
/// final middleware = oauth2Introspection(
///   OAuthIntrospectionOptions(
///     endpoint: Uri.parse('https://example.com/introspect'),
///     clientId: 'my-client-id',
///     clientSecret: 'my-client-secret',
///   ),
/// );
/// ```
Middleware oauth2Introspection(
  OAuthIntrospectionOptions options, {
  OAuthOnValidated? onValidated,
  http.Client? httpClient,
}) {
  final client = httpClient ?? http.Client();
  final cache = <String, _CachedIntrospection>{};

  Future<OAuthIntrospectionResult> introspect(String token) async {
    final cached = cache[token];
    if (cached != null && !cached.isExpired) {
      return cached.result;
    }

    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (options.clientId != null && options.clientSecret != null) {
      final credentials = base64Encode(
        utf8.encode('${options.clientId}:${options.clientSecret}'),
      );
      headers['Authorization'] = 'Basic $credentials';
    }

    final body = <String, String>{
      'token': token,
      if (options.tokenTypeHint != null)
        'token_type_hint': options.tokenTypeHint!,
      ...options.additionalParameters,
    };

    final response = await client.post(
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
    cache[token] = _CachedIntrospection(
      result,
      DateTime.now().add(options.cacheTtl),
    );
    return result;
  }

  return (EngineContext ctx, Next next) async {
    final header = ctx.request.header('Authorization');
    if (header.isEmpty || !header.startsWith('Bearer ')) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('missing token');
      return ctx.response;
    }
    final token = header.substring('Bearer '.length).trim();
    if (token.isEmpty) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('missing token');
      return ctx.response;
    }

    OAuthIntrospectionResult result;
    try {
      result = await introspect(token);
    } on OAuth2Exception catch (error) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write(error.message);
      return ctx.response;
    }

    if (!result.active) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('token inactive');
      return ctx.response;
    }

    final now = DateTime.now().toUtc();
    final expiresAt = result.expiresAt?.toUtc();
    if (expiresAt != null && expiresAt.add(options.clockSkew).isBefore(now)) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('token expired');
      return ctx.response;
    }

    final notBefore = result.notBefore?.toUtc();
    if (notBefore != null &&
        notBefore.subtract(options.clockSkew).isAfter(now)) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('token not yet valid');
      return ctx.response;
    }

    ctx.request
      ..setAttribute(oauthTokenAttribute, token)
      ..setAttribute(oauthClaimsAttribute, result.raw)
      ..setAttribute(oauthScopeAttribute, result.scope);

    if (onValidated != null) {
      await onValidated(result, ctx);
    }

    return await next();
  };
}
