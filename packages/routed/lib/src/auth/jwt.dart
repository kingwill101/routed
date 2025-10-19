import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
export 'package:jose/jose.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

const String jwtClaimsAttribute = 'auth.jwt.claims';
const String jwtHeadersAttribute = 'auth.jwt.headers';
const String jwtSubjectAttribute = 'auth.jwt.subject';

class JwtAuthException implements Exception {
  JwtAuthException(this.message);

  final String message;

  @override
  String toString() => 'JwtAuthException: $message';
}

class JwtPayload {
  const JwtPayload({
    required this.token,
    required this.claims,
    required this.headers,
  });

  final JsonWebToken token;
  final Map<String, dynamic> claims;
  final Map<String, dynamic> headers;

  String? get subject => token.claims.subject;
}

typedef JwtOnVerified =
    FutureOr<void> Function(JwtPayload payload, EngineContext context);

class JwtOptions {
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
  });

  final bool enabled;
  final String? issuer;
  final List<String> audience;
  final List<String> requiredClaims;
  final Uri? jwksUri;
  final List<Map<String, dynamic>> inlineKeys;
  final List<String> algorithms;
  final Duration clockSkew;
  final Duration jwksCacheTtl;
  final String header;
  final String bearerPrefix;

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
    );
  }
}

class JwtVerifier {
  JwtVerifier({required JwtOptions options, http.Client? httpClient})
    : _options = options,
      _httpClient = httpClient ?? http.Client();

  final JwtOptions _options;
  final http.Client _httpClient;

  JsonWebKeyStore? _cachedStore;
  DateTime? _storeExpiry;

  JwtOptions get options => _options;

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
        final payload = await _verify(token);
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

  void _writeUnauthorized(EngineContext ctx, String reason) {
    ctx.response
      ..statusCode = HttpStatus.unauthorized
      ..headers.set(
        'WWW-Authenticate',
        'Bearer error="invalid_token", error_description="$reason"',
      );
    if (!ctx.response.isClosed) {
      ctx.response.write('Unauthorized');
    }
  }

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

  String _normalizeBase64(String input) {
    final padding = (4 - input.length % 4) % 4;
    return input.padRight(input.length + padding, '=');
  }

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
