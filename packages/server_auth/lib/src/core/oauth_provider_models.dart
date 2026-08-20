import 'package:jose/jose.dart' show JsonWebKey;

import 'plugin.dart';

/// Represents an OAuth client registered with this application.
class OAuthClient {
  const OAuthClient({
    required this.clientId,
    required this.clientSecretHash,
    required this.name,
    this.description,
    required this.redirectUris,
    this.grantTypes = const ['authorization_code'],
    this.scopes = const ['openid', 'profile', 'email'],
    this.tokenEndpointAuthMethod = 'client_secret_basic',
    this.createdAt,
    this.updatedAt,
    this.enabled = true,
  });

  /// Unique client identifier.
  final String clientId;

  /// Hashed client secret (never plaintext).
  final String clientSecretHash;

  /// Human-readable client name.
  final String name;

  /// Optional client description.
  final String? description;

  /// Allowed redirect URIs for this client.
  final List<String> redirectUris;

  /// Supported grant types (e.g., 'authorization_code', 'client_credentials').
  final List<String> grantTypes;

  /// Allowed scopes.
  final List<String> scopes;

  /// Token endpoint authentication method.
  final String tokenEndpointAuthMethod;

  /// When the client was registered.
  final DateTime? createdAt;

  /// When the client was last updated.
  final DateTime? updatedAt;

  /// Whether the client is enabled.
  final bool enabled;

  /// Creates a copy with selected fields replaced.
  OAuthClient copyWith({
    String? clientSecretHash,
    String? name,
    String? description,
    List<String>? redirectUris,
    List<String>? grantTypes,
    List<String>? scopes,
    String? tokenEndpointAuthMethod,
    DateTime? updatedAt,
    bool? enabled,
  }) {
    return OAuthClient(
      clientId: clientId,
      clientSecretHash: clientSecretHash ?? this.clientSecretHash,
      name: name ?? this.name,
      description: description ?? this.description,
      redirectUris: redirectUris ?? this.redirectUris,
      grantTypes: grantTypes ?? this.grantTypes,
      scopes: scopes ?? this.scopes,
      tokenEndpointAuthMethod:
          tokenEndpointAuthMethod ?? this.tokenEndpointAuthMethod,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Serializes to JSON (without sensitive data).
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'name': name,
    'description': description,
    'redirectUris': redirectUris,
    'grantTypes': grantTypes,
    'scopes': scopes,
    'tokenEndpointAuthMethod': tokenEndpointAuthMethod,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'enabled': enabled,
  };

  /// Serializes for storage (includes secret hash).
  Map<String, dynamic> toStorageJson() => {
    ...toJson(),
    'clientSecretHash': clientSecretHash,
  };

  /// Creates from JSON.
  factory OAuthClient.fromJson(Map<String, dynamic> json) {
    return OAuthClient(
      clientId: json['clientId']?.toString() ?? '',
      clientSecretHash: json['clientSecretHash']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      redirectUris: _stringList(json['redirectUris']),
      grantTypes: _stringList(json['grantTypes']),
      scopes: _stringList(json['scopes']),
      tokenEndpointAuthMethod:
          json['tokenEndpointAuthMethod']?.toString() ?? 'client_secret_basic',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      enabled: json['enabled'] != false,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}

/// Represents an authorization code issued to a client.
///
/// Only [codeHash] is persisted. The raw code is returned to the client once
/// and hashed before it reaches the store.
class OAuthAuthorizationCode {
  const OAuthAuthorizationCode({
    required this.authorizationId,
    required this.codeHash,
    required this.clientId,
    required this.userId,
    required this.redirectUri,
    required this.scope,
    required this.expiresAt,
    this.codeChallenge,
    this.codeChallengeMethod,
    this.nonce,
    this.createdAt,
  });

  /// Stable persistence identifier for this authorization.
  ///
  /// This is not the authorization code and is safe to persist. It lets an
  /// exchange store distinguish a retry from a digest collision without
  /// retaining any delivery credential.
  final String authorizationId;

  /// Digest of the raw authorization code.
  final String codeHash;

  /// Client that requested the code.
  final String clientId;

  /// User who authorized the code.
  final String userId;

  /// Redirect URI for this authorization.
  final String redirectUri;

  /// Granted scopes.
  final String scope;

  /// When the code expires.
  final DateTime expiresAt;

  /// PKCE code challenge (optional).
  final String? codeChallenge;

  /// PKCE code challenge method (optional).
  final String? codeChallengeMethod;

  /// OIDC nonce (optional).
  final String? nonce;

  /// When the code was created.
  final DateTime? createdAt;

  /// Whether the code is still valid.
  bool isValid({DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    return current.isBefore(expiresAt.toUtc());
  }

  /// Serializes persistence-safe data without the raw authorization code.
  Map<String, dynamic> toStorageJson() => <String, dynamic>{
    'authorizationId': authorizationId,
    'codeHash': codeHash,
    'clientId': clientId,
    'userId': userId,
    'redirectUri': redirectUri,
    'scope': scope,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (codeChallenge != null) 'codeChallenge': codeChallenge,
    if (codeChallengeMethod != null) 'codeChallengeMethod': codeChallengeMethod,
    if (nonce != null) 'nonce': nonce,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
  };
}

/// Represents an issued access token.
class OAuthAccessToken {
  const OAuthAccessToken({
    required this.tokenHash,
    required this.clientId,
    required this.userId,
    required this.scope,
    required this.expiresAt,
    this.refreshTokenHash,
    this.refreshTokenExpiresAt,
    this.refreshTokenUses = 0,
    this.issuedAt,
    this.authorizationId,
  });

  /// Digest of the opaque access token held by the client.
  final String tokenHash;

  /// Client the token was issued to.
  final String clientId;

  /// User the token represents.
  final String userId;

  /// Granted scopes.
  final String scope;

  /// When the access token expires.
  final DateTime expiresAt;

  /// Digest of the opaque refresh token held by the client (optional).
  final String? refreshTokenHash;

  /// When the refresh token expires (optional). When present, refresh-token
  /// grants validate this timestamp instead of [expiresAt] so a refresh token
  /// remains usable after the access token has expired. When null, the refresh
  /// token is considered to never expire on its own and is only invalidated by
  /// revocation.
  final DateTime? refreshTokenExpiresAt;

  /// Number of times this refresh token has been consumed.
  final int refreshTokenUses;

  /// When the token was issued.
  final DateTime? issuedAt;

  /// Authorization that produced this record, for authorization-code grants.
  ///
  /// Other grants leave this null. The value is a persistence identifier, not
  /// an authorization code or token.
  final String? authorizationId;

  OAuthAccessToken copyWith({
    String? tokenHash,
    String? clientId,
    String? userId,
    String? scope,
    DateTime? expiresAt,
    String? refreshTokenHash,
    DateTime? refreshTokenExpiresAt,
    int? refreshTokenUses,
    DateTime? issuedAt,
    String? authorizationId,
  }) {
    return OAuthAccessToken(
      tokenHash: tokenHash ?? this.tokenHash,
      clientId: clientId ?? this.clientId,
      userId: userId ?? this.userId,
      scope: scope ?? this.scope,
      expiresAt: expiresAt ?? this.expiresAt,
      refreshTokenHash: refreshTokenHash ?? this.refreshTokenHash,
      refreshTokenExpiresAt:
          refreshTokenExpiresAt ?? this.refreshTokenExpiresAt,
      refreshTokenUses: refreshTokenUses ?? this.refreshTokenUses,
      issuedAt: issuedAt ?? this.issuedAt,
      authorizationId: authorizationId ?? this.authorizationId,
    );
  }

  /// Whether the access token is still valid.
  bool isValid({DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    return current.isBefore(expiresAt.toUtc());
  }

  /// Whether the refresh token is still valid. A null [refreshTokenHash] is never
  /// valid. When [refreshTokenExpiresAt] is null the refresh token does not
  /// expire on its own; callers must additionally check revocation via the
  /// access-token store.
  bool isRefreshTokenValid({DateTime? now}) {
    if (refreshTokenHash == null) return false;
    final current = now ?? DateTime.now().toUtc();
    if (refreshTokenExpiresAt == null) return true;
    return current.isBefore(refreshTokenExpiresAt!.toUtc());
  }
}

/// Options for the OAuth provider mode.
class OAuthProviderModeOptions {
  const OAuthProviderModeOptions({
    this.authorizationEndpoint = const AuthRoutePath('/oauth/authorize'),
    this.tokenEndpoint = const AuthRoutePath('/oauth/token'),
    this.userInfoEndpoint = const AuthRoutePath('/oauth/userinfo'),
    this.introspectionEndpoint = const AuthRoutePath('/oauth/introspect'),
    this.oidc,
    this.codeLifetime = const Duration(minutes: 10),
    this.accessTokenLifetime = const Duration(hours: 1),
    this.refreshTokenLifetime = const Duration(days: 30),
    this.supportedGrantTypes = const [
      'authorization_code',
      'client_credentials',
      'refresh_token',
    ],
    this.supportedResponseTypes = const ['code'],
    this.supportedScopes = const ['openid', 'profile', 'email'],
    this.userInfoClaimsByScope = const {},
    this.requirePkce = true,
    this.allowRefreshTokenRotation = true,
    this.maxRefreshTokenUses,
  });

  /// Authorization endpoint path.
  final AuthRoutePath authorizationEndpoint;

  /// Token endpoint path.
  final AuthRoutePath tokenEndpoint;

  /// UserInfo endpoint path.
  final AuthRoutePath userInfoEndpoint;

  /// Token introspection endpoint path.
  final AuthRoutePath introspectionEndpoint;

  /// Explicit OpenID Connect signing and discovery configuration.
  ///
  /// When null, the plugin operates as an OAuth authorization server and does
  /// not expose discovery or JWKS endpoints. Requests for the `openid` scope
  /// are rejected.
  final OAuthOidcConfiguration? oidc;

  /// Lifetime of authorization codes.
  final Duration codeLifetime;

  /// Lifetime of access tokens.
  final Duration accessTokenLifetime;

  /// Lifetime of refresh tokens.
  final Duration refreshTokenLifetime;

  /// Supported grant types.
  final List<String> supportedGrantTypes;

  /// Supported response types.
  final List<String> supportedResponseTypes;

  /// Supported scopes.
  final List<String> supportedScopes;

  /// Explicit user-attribute claims exposed by each granted scope.
  ///
  /// Protocol-reserved claims such as `sub`, `email`, `name`, and `picture`
  /// are always ignored here and are emitted only by their standard scopes.
  final Map<String, List<String>> userInfoClaimsByScope;

  /// Whether PKCE is required.
  final bool requirePkce;

  /// Whether refresh token rotation is allowed.
  final bool allowRefreshTokenRotation;

  /// Maximum number of refresh token uses (null = unlimited).
  final int? maxRefreshTokenUses;
}

/// OpenID Connect issuer and asymmetric signing configuration.
///
/// [signingKey] must contain private asymmetric key material and a non-empty
/// key ID. The plugin derives a public-only JWK for the JWKS endpoint and never
/// exposes private key parameters.
class OAuthOidcConfiguration {
  OAuthOidcConfiguration({
    required this.issuer,
    required this.signingKey,
    this.signingAlgorithm = 'RS256',
    this.discoveryEndpoint = const AuthRoutePath(
      '/.well-known/openid-configuration',
    ),
    this.jwksEndpoint = const AuthRoutePath('/oauth/jwks'),
    this.idTokenLifetime = const Duration(hours: 1),
  }) {
    if (!issuer.isAbsolute ||
        issuer.hasFragment ||
        issuer.hasQuery ||
        issuer.host.isEmpty) {
      throw ArgumentError.value(
        issuer,
        'issuer',
        'must be an absolute URI without a query or fragment',
      );
    }
    if (signingAlgorithm.trim().isEmpty) {
      throw ArgumentError.value(
        signingAlgorithm,
        'signingAlgorithm',
        'must not be empty',
      );
    }
    if (signingKey.keyId?.trim().isEmpty ?? true) {
      throw ArgumentError.value(
        signingKey.keyId,
        'signingKey',
        'must have a non-empty key ID',
      );
    }
    if (signingKey.keyType == 'oct') {
      throw ArgumentError.value(
        signingKey.keyType,
        'signingKey',
        'must be asymmetric so JWKS can expose only public material',
      );
    }
    if (!signingKey.usableForAlgorithm(signingAlgorithm) ||
        !signingKey.usableForOperation('sign')) {
      throw ArgumentError.value(
        signingKey,
        'signingKey',
        'cannot sign with $signingAlgorithm',
      );
    }
    discoveryEndpoint.validate();
    jwksEndpoint.validate();
    if (idTokenLifetime <= Duration.zero) {
      throw ArgumentError.value(
        idTokenLifetime,
        'idTokenLifetime',
        'must be positive',
      );
    }
  }

  /// Public issuer identifier embedded in ID tokens and discovery metadata.
  final Uri issuer;

  /// Private asymmetric JWK used to sign ID tokens.
  final JsonWebKey signingKey;

  /// JWS algorithm used to sign ID tokens.
  final String signingAlgorithm;

  /// Standard OpenID Provider configuration endpoint path.
  final AuthRoutePath discoveryEndpoint;

  /// Public JSON Web Key Set endpoint path.
  final AuthRoutePath jwksEndpoint;

  /// Lifetime of an issued ID token.
  final Duration idTokenLifetime;

  /// Public-only representation of [signingKey] for the JWKS endpoint.
  Map<String, dynamic> get publicJwk {
    final json = Map<String, dynamic>.from(signingKey.toJson())
      ..remove('d')
      ..remove('p')
      ..remove('q')
      ..remove('dp')
      ..remove('dq')
      ..remove('qi')
      ..remove('oth')
      ..remove('k');
    json['alg'] = signingAlgorithm;
    json['use'] = 'sig';
    json['key_ops'] = const <String>['verify'];
    return Map<String, dynamic>.unmodifiable(json);
  }
}
