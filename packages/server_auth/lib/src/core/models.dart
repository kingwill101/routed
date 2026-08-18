const Set<String> _sensitiveAttributeNames = <String>{
  'apikey',
  'authorization',
  'clientsecret',
  'credential',
  'credentials',
  'password',
  'passwordhash',
  'privatekey',
  'refreshtoken',
  'secret',
  'token',
  'accesstoken',
  'idtoken',
  'sessiontoken',
};

String _normalizeAttributeName(Object? name) =>
    name.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

dynamic _sanitizePublicValue(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        if (!_sensitiveAttributeNames.contains(
          _normalizeAttributeName(entry.key),
        ))
          entry.key.toString(): _sanitizePublicValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_sanitizePublicValue).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> _sanitizePublicAttributes(Map<String, dynamic> value) {
  return Map<String, dynamic>.from(
    _sanitizePublicValue(value) as Map<String, dynamic>,
  );
}

/// Represents an authenticated user or entity.
class AuthPrincipal {
  AuthPrincipal({
    required this.id,
    this.roles = const <String>[],
    Map<String, dynamic>? attributes,
  }) : attributes = attributes == null
           ? const <String, dynamic>{}
           : Map<String, dynamic>.from(attributes);

  final String id;
  final List<String> roles;
  final Map<String, dynamic> attributes;

  bool hasRole(String role) => roles.contains(role);

  Map<String, dynamic> toJson() => {
    'id': id,
    'roles': roles,
    'attributes': _sanitizePublicAttributes(attributes),
  };

  factory AuthPrincipal.fromJson(Map<String, dynamic> json) {
    return AuthPrincipal(
      id: json['id']?.toString() ?? '',
      roles: (json['roles'] as List?)?.cast<String>() ?? const <String>[],
      attributes: (json['attributes'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

/// Authenticated user profile used by auth flows and sessions.
class AuthUser {
  AuthUser({
    required this.id,
    this.email,
    this.name,
    this.image,
    this.roles = const <String>[],
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

  /// Additional provider-specific attributes.
  final Map<String, dynamic> attributes;

  /// Converts this user to a session principal.
  AuthPrincipal toPrincipal() {
    return AuthPrincipal(
      id: id,
      roles: roles,
      attributes: {
        ...attributes,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (image != null) 'image': image,
      },
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
      'attributes': _sanitizePublicAttributes(attributes),
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
      attributes: attributes,
    );
  }

  /// Creates a user from a JSON payload.
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString(),
      name: json['name']?.toString(),
      image: json['image']?.toString(),
      roles: (json['roles'] as List?)?.cast<String>() ?? const <String>[],
      attributes: (json['attributes'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

/// Provider account metadata linked to an `AuthUser`.
class AuthAccount {
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
      'metadata': _sanitizePublicAttributes(metadata),
    };
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
}

/// Credential input for username/password flows.
class AuthCredentials {
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

  /// Builds credentials from a request payload.
  factory AuthCredentials.fromMap(Map<String, dynamic> data) {
    return AuthCredentials(
      email: data['email']?.toString(),
      username: data['username']?.toString(),
      password: data['password']?.toString(),
      attributes: Map<String, dynamic>.from(data)..remove('password'),
    );
  }
}

/// Verification token for email sign-in.
class AuthVerificationToken {
  AuthVerificationToken({
    required this.identifier,
    required this.token,
    required this.expiresAt,
  });

  /// Identifier for the verification target (email).
  final String identifier;

  /// Token value sent to the user.
  final String token;

  /// Expiration timestamp.
  final DateTime expiresAt;
}

/// Session data returned by auth endpoints.
class AuthSession {
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
enum AuthSessionStrategy { session, jwt }

/// Result returned by sign-in flows.
class AuthResult {
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
