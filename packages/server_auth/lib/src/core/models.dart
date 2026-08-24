import 'dart:convert';

const Set<String> _sensitiveAttributeNames = <String>{
  'apikey',
  'authorization',
  'clientsecret',
  'credential',
  'credentials',
  'password',
  'passwordhash',
  'passphrase',
  'passwd',
  'privatekey',
  'refreshtoken',
  'secret',
  'token',
  'accesstoken',
  'idtoken',
  'sessiontoken',
};

const Set<String> _sensitiveAttributeFragments = <String>{
  'apikey',
  'authorization',
  'credential',
  'csrf',
  'idtoken',
  'jwt',
  'password',
  'passphrase',
  'passwd',
  'privatekey',
  'secret',
  'sessionid',
  'sessionkey',
  'token',
};

const _maxAuthPublicAttributeDepth = 32;

String _normalizeAttributeName(Object? name) =>
    name.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _isCredentialSecretAttribute(Object? name) {
  final normalized = _normalizeAttributeName(name);
  return normalized == 'password' ||
      normalized == 'passwordhash' ||
      normalized == 'passphrase' ||
      normalized == 'passwd';
}

bool _isSensitiveAttributeName(Object? name) {
  final normalized = _normalizeAttributeName(name);
  return _sensitiveAttributeNames.contains(normalized) ||
      _sensitiveAttributeFragments.any(normalized.contains);
}

dynamic _sanitizePublicValue(
  Object? value, {
  required Set<Object> ancestors,
  required int depth,
}) {
  if (value is Map) {
    if (depth >= _maxAuthPublicAttributeDepth || !ancestors.add(value)) {
      return null;
    }
    try {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!_isSensitiveAttributeName(entry.key))
            entry.key.toString(): _sanitizePublicValue(
              entry.value,
              ancestors: ancestors,
              depth: depth + 1,
            ),
      };
    } finally {
      ancestors.remove(value);
    }
  }
  if (value is Iterable) {
    if (depth >= _maxAuthPublicAttributeDepth || !ancestors.add(value)) {
      return null;
    }
    try {
      return value
          .map(
            (item) => _sanitizePublicValue(
              item,
              ancestors: ancestors,
              depth: depth + 1,
            ),
          )
          .toList(growable: false);
    } finally {
      ancestors.remove(value);
    }
  }
  return value;
}

/// Removes credential-like keys recursively from a public attribute map.
///
/// This is used for response projections and event payloads. Persistence and
/// provider callbacks should use the original private values instead.
Map<String, dynamic> sanitizeAuthPublicAttributes(Map<String, dynamic> value) {
  return Map<String, dynamic>.from(
    _sanitizePublicValue(value, ancestors: Set<Object>.identity(), depth: 0)
        as Map<String, dynamic>,
  );
}

/// Represents an authenticated user or entity.
class AuthPrincipal {
  /// Creates a principal with an identifier, roles, and public attributes.
  AuthPrincipal({
    required this.id,
    this.roles = const <String>[],
    Map<String, dynamic>? attributes,
  }) : attributes = attributes == null
           ? const <String, dynamic>{}
           : Map<String, dynamic>.from(attributes);

  /// Stable identifier for the authenticated principal.
  final String id;

  /// Role labels associated with the principal.
  final List<String> roles;

  /// Public attributes associated with the principal.
  final Map<String, dynamic> attributes;

  /// Returns whether [role] is assigned to this principal.
  bool hasRole(String role) => roles.contains(role);

  /// Serializes this principal after removing sensitive attributes.
  Map<String, dynamic> toJson() => {
    'id': id,
    'roles': roles,
    'attributes': sanitizeAuthPublicAttributes(attributes),
  };

  /// Creates a principal from a JSON payload.
  factory AuthPrincipal.fromJson(Map<String, dynamic> json) {
    final rolesValue = json['roles'];
    final attributesValue = json['attributes'];
    return AuthPrincipal(
      id: json['id']?.toString() ?? '',
      roles: rolesValue is List
          ? rolesValue.whereType<String>().toList(growable: false)
          : const <String>[],
      attributes: attributesValue is Map
          ? sanitizeAuthPublicAttributes(<String, dynamic>{
              for (final entry in attributesValue.entries)
                if (entry.key is String) entry.key as String: entry.value,
            })
          : const <String, dynamic>{},
    );
  }
}

/// Authenticated user profile used by auth flows and sessions.
class AuthUser {
  /// Creates a user profile.
  AuthUser({
    required this.id,
    this.email,
    this.name,
    this.image,
    this.roles = const <String>[],
    this.isAnonymous = false,
    Map<String, dynamic>? attributes,
  }) : attributes = attributes == null
           ? <String, dynamic>{}
           : Map<String, dynamic>.from(attributes);

  /// Provider-stable user identifier.
  final String id;

  /// Primary email address.
  final String? email;

  /// Display name.
  final String? name;

  /// Avatar or profile image URL.
  final String? image;

  /// Role labels used by guards and gates.
  final List<String> roles;

  /// Whether this account has no verified authentication identity yet.
  final bool isAnonymous;

  /// Additional provider-specific attributes.
  final Map<String, dynamic> attributes;

  /// Converts this user to a session principal.
  AuthPrincipal toPrincipal() {
    return AuthPrincipal(
      id: id,
      roles: roles,
      attributes: {...attributes, ..._standardPrincipalAttributes()},
    );
  }

  /// Converts this user to the compact principal stored in a framework
  /// session.
  ///
  /// Provider profiles can contain large, provider-specific metadata. A
  /// framework session may be serialized into a browser cookie, so retaining
  /// those fields here can exceed browser cookie limits and make a successful
  /// sign-in unusable on the next request. Applications that need additional
  /// session claims can explicitly call `SessionAuth.updateSession` with an
  /// [AuthPrincipal] containing the claims they intend to retain.
  AuthPrincipal toSessionPrincipal() {
    return AuthPrincipal(
      id: id,
      roles: roles,
      attributes: _compactStandardPrincipalAttributes(),
    );
  }

  Map<String, dynamic> _standardPrincipalAttributes() {
    return {
      if (email != null) 'email': email,
      if (name != null) 'name': name,
      if (image != null) 'image': image,
      if (isAnonymous) 'isAnonymous': true,
    };
  }

  Map<String, dynamic> _compactStandardPrincipalAttributes() {
    final fallbackEmail = _compactAttribute('email', maxBytes: 320);
    final compactEmail = _compactValue(email, maxBytes: 320);
    final compactName = _compactValue(name, maxBytes: 256);
    final compactImage = _compactValue(image, maxBytes: 2048);
    return {
      if (compactEmail != null) 'email': compactEmail,
      if (compactEmail == null && email == null && fallbackEmail != null)
        'email': fallbackEmail,
      if (compactName != null) 'name': compactName,
      if (compactImage != null) 'image': compactImage,
      if (isAnonymous) 'isAnonymous': true,
    };
  }

  String? _compactValue(String? value, {required int maxBytes}) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    if (utf8.encode(value).length > maxBytes) {
      return null;
    }
    return value;
  }

  String? _compactAttribute(String key, {required int maxBytes}) {
    final value = attributes[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    if (utf8.encode(value).length > maxBytes) {
      return null;
    }
    return value;
  }

  /// Creates a user safe to retain in events and audit records.
  AuthUser redacted() {
    return AuthUser(
      id: id,
      email: email,
      name: name,
      image: image,
      roles: roles,
      isAnonymous: isAnonymous,
      attributes: sanitizeAuthPublicAttributes(attributes),
    );
  }

  /// Converts this user to JSON for API responses.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'image': image,
      'roles': roles,
      'isAnonymous': isAnonymous,
      'attributes': sanitizeAuthPublicAttributes(attributes),
    };
  }

  /// Creates a user from a session principal.
  factory AuthUser.fromPrincipal(AuthPrincipal principal) {
    final attributes = Map<String, dynamic>.from(principal.attributes);
    return AuthUser(
      id: principal.id,
      roles: principal.roles,
      email: attributes.remove('email')?.toString(),
      name: attributes.remove('name')?.toString(),
      image: attributes.remove('image')?.toString(),
      isAnonymous: attributes.remove('isAnonymous') == true,
      attributes: attributes,
    );
  }

  /// Creates a user from a JSON payload.
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rolesValue = json['roles'];
    final attributesValue = json['attributes'];
    return AuthUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString(),
      name: json['name']?.toString(),
      image: json['image']?.toString(),
      isAnonymous: json['isAnonymous'] == true,
      roles: rolesValue is List
          ? rolesValue.whereType<String>().toList(growable: false)
          : const <String>[],
      attributes: attributesValue is Map
          ? sanitizeAuthPublicAttributes(<String, dynamic>{
              for (final entry in attributesValue.entries)
                if (entry.key is String) entry.key as String: entry.value,
            })
          : const <String, dynamic>{},
    );
  }
}

/// Provider account metadata linked to an `AuthUser`.
class AuthAccount {
  /// Creates linked provider-account metadata.
  AuthAccount({
    required this.providerId,
    required this.providerAccountId,
    this.userId,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata == null
           ? <String, dynamic>{}
           : Map<String, dynamic>.from(metadata);

  /// Provider identifier (e.g. `github`).
  final String providerId;

  /// Provider account identifier.
  final String providerAccountId;

  /// Linked user identifier.
  final String? userId;

  /// Access token for the account.
  final String? accessToken;

  /// Refresh token for the account.
  final String? refreshToken;

  /// Access token expiration timestamp.
  final DateTime? expiresAt;

  /// Provider-specific metadata payload.
  final Map<String, dynamic> metadata;

  /// Serializes the account payload.
  Map<String, dynamic> toJson({bool includeTokens = false}) {
    return {
      'provider_id': providerId,
      'provider_account_id': providerAccountId,
      'user_id': userId,
      if (includeTokens) 'access_token': accessToken,
      if (includeTokens) 'refresh_token': refreshToken,
      'expires_at': expiresAt?.toIso8601String(),
      'metadata': sanitizeAuthPublicAttributes(metadata),
    };
  }

  /// Creates an account safe to retain in events and audit records.
  ///
  /// Provider access and refresh tokens are private persistence data and are
  /// never copied into the redacted projection.
  AuthAccount redacted() {
    return AuthAccount(
      providerId: providerId,
      providerAccountId: providerAccountId,
      userId: userId,
      expiresAt: expiresAt,
      metadata: sanitizeAuthPublicAttributes(metadata),
    );
  }

  /// Serializes the account for private persistence, including OAuth tokens.
  Map<String, dynamic> toStorageJson() => {
    'provider_id': providerId,
    'provider_account_id': providerAccountId,
    'user_id': userId,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt?.toIso8601String(),
    'metadata': metadata,
  };

  /// Creates a public linked-account projection from JSON.
  factory AuthAccount.fromJson(Map<String, dynamic> json) => AuthAccount(
    providerId:
        json['provider_id']?.toString() ?? json['providerId']?.toString() ?? '',
    providerAccountId:
        json['provider_account_id']?.toString() ??
        json['providerAccountId']?.toString() ??
        '',
    userId: json['user_id']?.toString() ?? json['userId']?.toString(),
    expiresAt: DateTime.tryParse(
      json['expires_at']?.toString() ?? json['expiresAt']?.toString() ?? '',
    ),
    metadata: json['metadata'] is Map
        ? sanitizeAuthPublicAttributes(
            Map<String, dynamic>.from(json['metadata'] as Map),
          )
        : const <String, dynamic>{},
  );
}

/// Persisted password credential record.
///
/// This is a storage model, not request input. It contains only an encoded
/// password hash and may safely be passed between typed persistence layers.
class AuthPasswordCredential {
  /// Creates a persisted password credential record.
  AuthPasswordCredential({
    required this.id,
    required this.userId,
    required this.identifier,
    required this.passwordHash,
    required this.createdAt,
    required this.updatedAt,
    this.enabled = true,
  });

  /// Stable persistence identifier for this credential.
  final String id;

  /// User owning the credential.
  final String userId;

  /// Normalized login identifier, such as an email or username.
  final String identifier;

  /// Self-contained encoded password hash; never plaintext.
  final String passwordHash;

  /// Time at which this credential was created.
  final DateTime createdAt;

  /// Time at which this credential was last changed.
  final DateTime updatedAt;

  /// Whether this credential may authenticate.
  final bool enabled;

  /// Creates a changed copy of this credential.
  AuthPasswordCredential copyWith({
    String? passwordHash,
    DateTime? updatedAt,
    bool? enabled,
  }) {
    return AuthPasswordCredential(
      id: id,
      userId: userId,
      identifier: identifier,
      passwordHash: passwordHash ?? this.passwordHash,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Serializes persistence-safe credential data.
  Map<String, dynamic> toStorageJson() => {
    'id': id,
    'user_id': userId,
    'identifier': identifier,
    'password_hash': passwordHash,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'enabled': enabled,
  };
}

/// Credential input for username/password flows.
class AuthCredentials {
  /// Creates credential input for a sign-in or registration request.
  AuthCredentials({
    this.email,
    this.username,
    this.password,
    Map<String, dynamic>? attributes,
  }) : attributes = attributes == null
           ? <String, dynamic>{}
           : Map<String, dynamic>.from(attributes);

  /// Email address supplied by the client.
  final String? email;

  /// Username supplied by the client.
  final String? username;

  /// Password supplied by the client.
  final String? password;

  /// Additional credential fields.
  final Map<String, dynamic> attributes;

  /// Returns a copy safe to retain in events and audit records.
  AuthCredentials redacted() {
    return AuthCredentials(
      email: email,
      username: username,
      attributes: sanitizeAuthPublicAttributes(<String, dynamic>{
        for (final entry in attributes.entries)
          if (!_isCredentialSecretAttribute(entry.key)) entry.key: entry.value,
      }),
    );
  }

  /// Builds credentials from a request payload.
  factory AuthCredentials.fromMap(Map<String, dynamic> data) {
    return AuthCredentials(
      email: data['email']?.toString(),
      username: data['username']?.toString(),
      password: data['password']?.toString(),
      attributes: <String, dynamic>{
        for (final entry in data.entries)
          if (!_isCredentialSecretAttribute(entry.key)) entry.key: entry.value,
      },
    );
  }
}

/// Verification token for email sign-in.
class AuthVerificationToken {
  /// Creates an email verification token record.
  AuthVerificationToken({
    required this.identifier,
    required this.token,
    required this.expiresAt,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata == null
           ? const <String, dynamic>{}
           : Map<String, dynamic>.unmodifiable(metadata);

  /// Identifier for the verification target (email).
  final String identifier;

  /// Token value sent to the user.
  final String token;

  /// Expiration timestamp.
  final DateTime expiresAt;

  /// Server-side data associated with the token. Implementations must persist
  /// this data with the token and must never expose the raw token in it.
  final Map<String, dynamic> metadata;
}

/// One-time confirmation token for changing a user's email address.
///
/// The raw [token] is delivery-only. Typed stores must persist only its
/// digest and return this value only to the caller that atomically consumes it.
class AuthEmailChangeToken {
  /// Creates a one-time email-change token record.
  AuthEmailChangeToken({
    required this.userId,
    required this.newEmail,
    required this.token,
    required this.expiresAt,
  });

  /// User requesting the email change.
  final String userId;

  /// New email address awaiting confirmation.
  final String newEmail;

  /// Raw token delivered to the user for one-time confirmation.
  final String token;

  /// Time after which this token is invalid.
  final DateTime expiresAt;
}

/// Persisted server-side session metadata.
///
/// [tokenHash] is the digest of the opaque session token held by the client;
/// the raw token must never be persisted. This record is deliberately
/// separate from [AuthSession], which is the public response projection.
class AuthSessionRecord {
  /// Creates persisted metadata for a server-side session.
  AuthSessionRecord({
    required this.id,
    required this.tokenHash,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.authenticationMethod,
    this.revokedAt,
    this.ipAddress,
    this.userAgent,
    this.impersonatedBy,
  });

  /// Stable persistence identifier for this session record.
  final String id;

  /// Digest of the client-held session token.
  final String tokenHash;

  /// User owning the session.
  final String userId;

  /// Time at which the session was issued.
  final DateTime createdAt;

  /// Time after which the session cannot authenticate.
  final DateTime expiresAt;

  /// Most recent authenticated use of the session.
  final DateTime lastUsedAt;

  /// Time at which the session was revoked, if any.
  final DateTime? revokedAt;

  /// Direct connection address observed when the session was issued.
  final String? ipAddress;

  /// User-agent value observed when the session was issued.
  final String? userAgent;

  /// Authentication mechanism that issued the session.
  final String authenticationMethod;

  /// Original administrator for an impersonated server session.
  final String? impersonatedBy;

  /// Whether this record is valid at [now].
  bool isActive({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return revokedAt == null && current.isBefore(expiresAt.toUtc());
  }

  /// Creates a changed copy while preserving immutable session metadata.
  AuthSessionRecord copyWith({DateTime? lastUsedAt, DateTime? revokedAt}) {
    return AuthSessionRecord(
      id: id,
      tokenHash: tokenHash,
      userId: userId,
      createdAt: createdAt,
      expiresAt: expiresAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      authenticationMethod: authenticationMethod,
      revokedAt: revokedAt ?? this.revokedAt,
      ipAddress: ipAddress,
      userAgent: userAgent,
      impersonatedBy: impersonatedBy,
    );
  }

  /// Serializes persistence-safe session metadata.
  Map<String, dynamic> toStorageJson() => {
    'id': id,
    'token_hash': tokenHash,
    'user_id': userId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'last_used_at': lastUsedAt.toUtc().toIso8601String(),
    'revoked_at': revokedAt?.toUtc().toIso8601String(),
    'ip_address': ipAddress,
    'user_agent': userAgent,
    'authentication_method': authenticationMethod,
    'impersonated_by': impersonatedBy,
  };
}

/// Session data returned by auth endpoints.
class AuthSession {
  /// Creates a public session response.
  AuthSession({
    required this.user,
    required this.expiresAt,
    this.strategy,
    this.token,
  });

  /// Signed-in user.
  final AuthUser user;

  /// Optional expiry timestamp.
  final DateTime? expiresAt;

  /// Session strategy used for this session.
  final AuthSessionStrategy? strategy;

  /// JWT token when using JWT strategy.
  final String? token;

  /// Creates a session safe to retain in events and audit records.
  AuthSession redacted() {
    return AuthSession(
      user: user.redacted(),
      expiresAt: expiresAt,
      strategy: strategy,
    );
  }

  /// Serializes the session payload.
  Map<String, dynamic> toJson({bool includeToken = false}) {
    return {
      'user': user.toJson(),
      'expires': expiresAt?.toIso8601String(),
      'strategy': strategy?.name,
      if (includeToken && token != null) 'token': token,
    };
  }
}

/// Session storage strategy for auth.
enum AuthSessionStrategy {
  /// Stores a random opaque token in the server-side session store.
  session,

  /// Stores a signed JSON Web Token as the session credential.
  jwt,
}

/// Result returned by sign-in flows.
class AuthResult {
  /// Creates the result of a sign-in flow.
  const AuthResult({
    required this.user,
    required this.session,
    this.redirectUrl,
  });

  /// Authenticated user.
  final AuthUser user;

  /// Session data for the request.
  final AuthSession session;

  /// Optional redirect target used by auth routes.
  final String? redirectUrl;
}
