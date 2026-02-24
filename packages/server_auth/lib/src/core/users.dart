import 'models.dart' show AuthUser;

/// Resolves a provider account id from profile/user fields.
String resolveAuthAccountId(
  Map<String, dynamic> profile,
  AuthUser user, {
  required String Function() fallbackId,
}) {
  final candidates = <Object?>[
    profile['sub'],
    profile['id'],
    profile['user_id'],
    user.id,
    user.email,
  ];

  for (final value in candidates) {
    if (value != null && value.toString().isNotEmpty) {
      return value.toString();
    }
  }
  return fallbackId();
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
