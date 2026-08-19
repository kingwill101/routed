import 'models.dart' show AuthUser, sanitizeAuthPublicAttributes;

/// Normalizes an email identifier used by built-in auth flows.
///
/// Email providers and local credential lookups use a case-insensitive,
/// trimmed identifier so equivalent inputs address the same account and
/// verification-token namespace.
String normalizeAuthEmail(String email) => email.trim().toLowerCase();

/// Returns whether [user] has an explicitly verified email address.
///
/// The canonical flag is `emailVerified`. The snake-case spelling is accepted
/// for provider profile data so OAuth mappings can retain their source claims
/// without a lossy conversion.
bool authUserEmailIsVerified(AuthUser user) {
  return user.attributes['emailVerified'] == true ||
      user.attributes['email_verified'] == true;
}

/// Returns whether [user] is unavailable for authentication.
///
/// `disabled` is the stable application-facing flag. `deletedAt` and
/// `accountDisabled` are recognized as defensive tombstone/legacy markers so
/// a stale session cannot continue after an account lifecycle mutation.
bool authUserIsDisabled(AuthUser user) {
  return user.attributes['disabled'] == true ||
      user.attributes['accountDisabled'] == true ||
      user.attributes['deletedAt'] != null;
}

/// Resolves a provider account id from profile/user fields.
String resolveAuthAccountId(
  Map<String, dynamic> profile,
  AuthUser user, {
  required String Function() fallbackId,
  bool emailVerified = false,
}) {
  final candidates = <Object?>[
    profile['sub'],
    profile['id'],
    profile['user_id'],
    user.id,
    if (emailVerified) user.email,
  ];

  for (final value in candidates) {
    final candidate = value?.toString().trim();
    if (candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
  }
  final fallback = fallbackId().trim();
  if (fallback.isEmpty) {
    throw StateError('OAuth provider returned no stable account identity');
  }
  return fallback;
}

/// Merges [incoming] user data into [existing] using auth manager semantics.
AuthUser mergeAuthUser(AuthUser existing, AuthUser incoming) {
  final roles = incoming.roles.isNotEmpty ? incoming.roles : existing.roles;
  final attributes = <String, dynamic>{
    ...existing.attributes,
    ...incoming.attributes,
  };

  return AuthUser(
    id: existing.id,
    email: incoming.email ?? existing.email,
    name: incoming.name ?? existing.name,
    image: incoming.image ?? existing.image,
    roles: roles,
    attributes: attributes,
  );
}

/// Returns true when [left] and [right] differ by auth-relevant fields.
bool authUsersDiffer(AuthUser left, AuthUser right) {
  if (left.email != right.email ||
      left.name != right.name ||
      left.image != right.image) {
    return true;
  }
  if (!_listEquals(left.roles, right.roles)) {
    return true;
  }
  return !_mapEquals(left.attributes, right.attributes);
}

/// Converts [user] into default JWT auth claims.
Map<String, dynamic> authJwtClaimsForUser(AuthUser user) {
  final safeUser = user.redacted();
  return {
    'sub': safeUser.id,
    'email': safeUser.email,
    'name': safeUser.name,
    'image': safeUser.image,
    'roles': safeUser.roles,
    'attributes': safeUser.attributes,
  };
}

/// Creates an [AuthUser] from default JWT auth [claims].
AuthUser authUserFromJwtClaims(Map<String, dynamic> claims) {
  return AuthUser(
    id: claims['sub']?.toString() ?? '',
    email: claims['email']?.toString(),
    name: claims['name']?.toString(),
    image: claims['image']?.toString(),
    roles: _jwtRoles(claims['roles']),
    attributes: _jwtAttributes(claims['attributes']),
  );
}

List<String> _jwtRoles(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().toList(growable: false);
}

Map<String, dynamic> _jwtAttributes(Object? value) {
  if (value is! Map) {
    return <String, dynamic>{};
  }
  final attributes = <String, dynamic>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  return sanitizeAuthPublicAttributes(attributes);
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

bool _mapEquals(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key)) {
      return false;
    }
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
