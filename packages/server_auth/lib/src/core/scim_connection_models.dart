import 'dart:async';

import 'package:server_auth/src/core/plugin.dart';
import 'package:server_auth/src/core/scim_models.dart';

/// Lifecycle of one managed SCIM directory connection.
enum AuthScimConnectionState {
  /// The connection accepts provisioning requests.
  active,

  /// The connection no longer accepts provisioning requests.
  disabled,
}

/// Exact tenancy boundary used by managed SCIM connection operations.
final class AuthScimConnectionBinding {
  /// Creates a normalized tenant and organization binding.
  AuthScimConnectionBinding({
    required String tenantId,
    required String organizationId,
  }) : tenantId = _identifier(tenantId, 'tenantId'),
       organizationId = _identifier(organizationId, 'organizationId');

  /// Tenant containing the organization.
  final String tenantId;

  /// Organization containing the connection.
  final String organizationId;

  /// Serializes this tenancy boundary.
  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'organizationId': organizationId,
  };
}

/// Safe, public metadata for one managed directory connection.
final class AuthScimManagedConnection {
  /// Creates a validated public connection record.
  AuthScimManagedConnection({
    required String id,
    required String tenantId,
    required String organizationId,
    required String provisioningDomainId,
    required String subjectId,
    required String name,
    required Iterable<AuthScimScope> scopes,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? disabledAt,
  }) : id = _identifier(id, 'id'),
       tenantId = _identifier(tenantId, 'tenantId'),
       organizationId = _identifier(organizationId, 'organizationId'),
       provisioningDomainId = _identifier(
         provisioningDomainId,
         'provisioningDomainId',
       ),
       subjectId = _identifier(subjectId, 'subjectId'),
       name = _displayName(name),
       scopes = _scopes(scopes),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       disabledAt = disabledAt?.toUtc() {
    if (this.scopes.isEmpty) {
      throw ArgumentError('SCIM scopes must not be empty.');
    }
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError('updatedAt must not precede createdAt');
    }
    if (this.disabledAt?.isBefore(this.createdAt) ?? false) {
      throw ArgumentError('disabledAt must not precede createdAt');
    }
  }

  /// Decodes and validates a public connection representation.
  factory AuthScimManagedConnection.fromJson(Map<String, dynamic> json) {
    final state = _requiredString(json, 'state');
    final disabledAt = _optionalDate(json, 'disabledAt');
    if ((state == AuthScimConnectionState.disabled.name) !=
        (disabledAt != null)) {
      throw const FormatException('Invalid SCIM connection state.');
    }
    return AuthScimManagedConnection(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenantId'),
      organizationId: _requiredString(json, 'organizationId'),
      provisioningDomainId: _requiredString(json, 'provisioningDomainId'),
      subjectId: _requiredString(json, 'subjectId'),
      name: _requiredString(json, 'name'),
      scopes: _scopeValues(json['scopes']),
      createdAt: _requiredDate(json, 'createdAt'),
      updatedAt: _requiredDate(json, 'updatedAt'),
      disabledAt: disabledAt,
    );
  }

  /// Stable connection identifier.
  final String id;

  /// Tenant containing the connection.
  final String tenantId;

  /// Organization containing the connection.
  final String organizationId;

  /// Provisioning domain used by the SCIM endpoint.
  final String provisioningDomainId;

  /// Stable application subject that owns management of this connection.
  final String subjectId;

  /// Human-readable connection name.
  final String name;

  /// Scopes granted to credentials issued for this connection.
  final Set<AuthScimScope> scopes;

  /// Creation timestamp in UTC.
  final DateTime createdAt;

  /// Last update timestamp in UTC.
  final DateTime updatedAt;

  /// Disable timestamp, or `null` while active.
  final DateTime? disabledAt;

  /// Current lifecycle state derived from [disabledAt].
  AuthScimConnectionState get state => disabledAt == null
      ? AuthScimConnectionState.active
      : AuthScimConnectionState.disabled;

  /// Whether this connection is currently active.
  bool get isActive => disabledAt == null;

  /// The tenant and organization boundary for this connection.
  AuthScimConnectionBinding get binding => AuthScimConnectionBinding(
    tenantId: tenantId,
    organizationId: organizationId,
  );

  /// Creates a copy with the supplied mutable fields replaced.
  AuthScimManagedConnection copyWith({
    String? name,
    String? provisioningDomainId,
    Iterable<AuthScimScope>? scopes,
    DateTime? updatedAt,
    DateTime? disabledAt,
  }) => AuthScimManagedConnection(
    id: id,
    tenantId: tenantId,
    organizationId: organizationId,
    provisioningDomainId: provisioningDomainId ?? this.provisioningDomainId,
    subjectId: subjectId,
    name: name ?? this.name,
    scopes: scopes ?? this.scopes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    disabledAt: disabledAt ?? this.disabledAt,
  );

  /// Serializes the public connection representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'tenantId': tenantId,
    'organizationId': organizationId,
    'provisioningDomainId': provisioningDomainId,
    'subjectId': subjectId,
    'name': name,
    'scopes': scopes.map((value) => value.name).toList(growable: false),
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (disabledAt != null) 'disabledAt': disabledAt!.toIso8601String(),
  };
}

/// Persisted credential record. The raw bearer secret is never represented.
final class AuthScimCredentialRecord {
  /// Creates a storage record without retaining the raw bearer secret.
  AuthScimCredentialRecord({
    required String id,
    required String connectionId,
    required String tenantId,
    required String organizationId,
    required String name,
    required String keyPrefix,
    required String secretDigest,
    required Iterable<AuthScimScope> scopes,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? expiresAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) : id = _identifier(id, 'id'),
       connectionId = _identifier(connectionId, 'connectionId'),
       tenantId = _identifier(tenantId, 'tenantId'),
       organizationId = _identifier(organizationId, 'organizationId'),
       name = _displayName(name),
       keyPrefix = _prefix(keyPrefix),
       secretDigest = _digest(secretDigest),
       scopes = _scopes(scopes),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       expiresAt = expiresAt?.toUtc(),
       lastUsedAt = lastUsedAt?.toUtc(),
       revokedAt = revokedAt?.toUtc() {
    if (this.scopes.isEmpty) {
      throw ArgumentError('SCIM scopes must not be empty.');
    }
    if (this.updatedAt.isBefore(this.createdAt) ||
        this.expiresAt?.isAfter(this.createdAt) == false ||
        (this.revokedAt?.isBefore(this.createdAt) ?? false)) {
      throw ArgumentError('Invalid SCIM credential timestamps.');
    }
  }

  /// Stable credential identifier.
  final String id;

  /// Connection that owns this credential.
  final String connectionId;

  /// Tenant containing the credential.
  final String tenantId;

  /// Organization containing the credential.
  final String organizationId;

  /// Human-readable credential name.
  final String name;

  /// Non-secret prefix used to identify the credential to operators.
  final String keyPrefix;

  /// Strong digest used for lookup. Never expose this from public projections.
  final String secretDigest;

  /// Scopes granted by this credential.
  final Set<AuthScimScope> scopes;

  /// Creation timestamp in UTC.
  final DateTime createdAt;

  /// Last update timestamp in UTC.
  final DateTime updatedAt;

  /// Expiry timestamp, or `null` when it does not expire.
  final DateTime? expiresAt;

  /// Last successful-use timestamp, when known.
  final DateTime? lastUsedAt;

  /// Revocation timestamp, or `null` while not revoked.
  final DateTime? revokedAt;

  /// Whether this credential is usable at [now].
  bool isActiveAt(DateTime now) =>
      revokedAt == null &&
      (expiresAt == null || expiresAt!.isAfter(now.toUtc()));

  /// Creates a copy with lifecycle timestamps replaced.
  AuthScimCredentialRecord copyWith({
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) => AuthScimCredentialRecord(
    id: id,
    connectionId: connectionId,
    tenantId: tenantId,
    organizationId: organizationId,
    name: name,
    keyPrefix: keyPrefix,
    secretDigest: secretDigest,
    scopes: scopes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    expiresAt: expiresAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    revokedAt: revokedAt ?? this.revokedAt,
  );

  /// Projects this storage record without its secret digest or tenancy data.
  AuthScimCredential toPublic({required DateTime now}) => AuthScimCredential(
    id: id,
    connectionId: connectionId,
    name: name,
    keyPrefix: keyPrefix,
    scopes: scopes,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
    lastUsedAt: lastUsedAt,
    revokedAt: revokedAt,
    active: isActiveAt(now),
  );

  /// Storage-only serialization including the non-reversible digest.
  Map<String, Object?> toStorageJson() => <String, Object?>{
    'id': id,
    'connectionId': connectionId,
    'tenantId': tenantId,
    'organizationId': organizationId,
    'name': name,
    'keyPrefix': keyPrefix,
    'secretDigest': secretDigest,
    'scopes': scopes.map((value) => value.name).toList(growable: false),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
    if (revokedAt != null) 'revokedAt': revokedAt!.toIso8601String(),
  };
}

/// Safe credential metadata returned by management APIs.
final class AuthScimCredential {
  /// Creates public credential metadata.
  const AuthScimCredential({
    required this.id,
    required this.connectionId,
    required this.name,
    required this.keyPrefix,
    required this.scopes,
    required this.createdAt,
    required this.updatedAt,
    required this.active,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  /// Decodes and validates public credential metadata.
  factory AuthScimCredential.fromJson(Map<String, dynamic> json) =>
      AuthScimCredential(
        id: _requiredString(json, 'id'),
        connectionId: _requiredString(json, 'connectionId'),
        name: _requiredString(json, 'name'),
        keyPrefix: _requiredString(json, 'keyPrefix'),
        scopes: _scopes(_scopeValues(json['scopes'])),
        active: json['active'] == true,
        createdAt: _requiredDate(json, 'createdAt'),
        updatedAt: _requiredDate(json, 'updatedAt'),
        expiresAt: _optionalDate(json, 'expiresAt'),
        lastUsedAt: _optionalDate(json, 'lastUsedAt'),
        revokedAt: _optionalDate(json, 'revokedAt'),
      );

  /// Stable credential identifier.
  final String id;

  /// Connection that owns this credential.
  final String connectionId;

  /// Human-readable credential name.
  final String name;

  /// Non-secret prefix used to identify the credential.
  final String keyPrefix;

  /// Scopes granted by this credential.
  final Set<AuthScimScope> scopes;

  /// Creation timestamp in UTC.
  final DateTime createdAt;

  /// Last update timestamp in UTC.
  final DateTime updatedAt;

  /// Whether the credential is usable at projection time.
  final bool active;

  /// Expiry timestamp, when configured.
  final DateTime? expiresAt;

  /// Last successful-use timestamp, when known.
  final DateTime? lastUsedAt;

  /// Revocation timestamp, when revoked.
  final DateTime? revokedAt;

  /// Serializes the public credential representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'connectionId': connectionId,
    'name': name,
    'keyPrefix': keyPrefix,
    'scopes': scopes.map((value) => value.name).toList(growable: false),
    'active': active,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toUtc().toIso8601String(),
    if (revokedAt != null) 'revokedAt': revokedAt!.toUtc().toIso8601String(),
  };
}

/// Result of one digest-only credential issuance transaction.
final class AuthScimCredentialIssuance {
  /// Creates an issuance result.
  const AuthScimCredentialIssuance({
    required this.credential,
    required this.replayed,
    this.secret,
  }) : assert(
         (secret == null) == replayed,
         'secret must be present exactly when the credential is replayed',
       );

  /// Decodes and validates an issuance response.
  factory AuthScimCredentialIssuance.fromJson(Map<String, dynamic> json) {
    final credential = json['credential'];
    if (credential is! Map) {
      throw const FormatException('Invalid SCIM credential response.');
    }
    final replayed = json['replayed'] == true;
    final secret = json['secret'];
    if ((!replayed && secret is! String) || (replayed && secret != null)) {
      throw const FormatException('Invalid SCIM credential delivery state.');
    }
    return AuthScimCredentialIssuance(
      credential: AuthScimCredential.fromJson(
        Map<String, dynamic>.from(credential),
      ),
      replayed: replayed,
      secret: secret as String?,
    );
  }

  /// Public metadata for the issued credential.
  final AuthScimCredential credential;

  /// Raw opaque bearer token. Present only for the first committed response.
  final String? secret;

  /// Whether this response replays an earlier idempotent issuance.
  final bool replayed;

  /// Serializes the issuance result.
  Map<String, Object?> toJson() => <String, Object?>{
    'credential': credential.toJson(),
    'replayed': replayed,
    if (secret != null) 'secret': secret,
  };
}

/// Result of creating a connection and its initial credential atomically.
final class AuthScimConnectionCreation {
  /// Creates an atomic connection-and-credential result.
  const AuthScimConnectionCreation({
    required this.connection,
    required this.issuance,
  });

  /// Decodes and validates a creation result.
  factory AuthScimConnectionCreation.fromJson(Map<String, dynamic> json) {
    final connection = json['connection'];
    final issuance = json['issuance'];
    if (connection is! Map || issuance is! Map) {
      throw const FormatException('Invalid SCIM connection response.');
    }
    return AuthScimConnectionCreation(
      connection: AuthScimManagedConnection.fromJson(
        Map<String, dynamic>.from(connection),
      ),
      issuance: AuthScimCredentialIssuance.fromJson(
        Map<String, dynamic>.from(issuance),
      ),
    );
  }

  /// The newly created connection.
  final AuthScimManagedConnection connection;

  /// The initial credential issuance, including its one-time secret.
  final AuthScimCredentialIssuance issuance;

  /// Serializes the creation result.
  Map<String, Object?> toJson() => <String, Object?>{
    'connection': connection.toJson(),
    'issuance': issuance.toJson(),
  };
}

/// Bounded connection catalog page.
final class AuthScimConnectionPage {
  /// Creates a bounded page of connection metadata.
  const AuthScimConnectionPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// Connections in this page.
  final List<AuthScimManagedConnection> items;

  /// Total matching connections across all pages.
  final int total;

  /// Maximum number of items requested for this page.
  final int limit;

  /// Zero-based offset used to produce this page.
  final int offset;

  /// Serializes the page.
  Map<String, Object?> toJson() => <String, Object?>{
    'items': items.map((value) => value.toJson()).toList(growable: false),
    'total': total,
    'limit': limit,
    'offset': offset,
  };
}

/// Bounded credential catalog page.
final class AuthScimCredentialPage {
  /// Creates a bounded page of credential metadata.
  const AuthScimCredentialPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// Credentials in this page.
  final List<AuthScimCredential> items;

  /// Total matching credentials across all pages.
  final int total;

  /// Maximum number of items requested for this page.
  final int limit;

  /// Zero-based offset used to produce this page.
  final int offset;

  /// Serializes the page.
  Map<String, Object?> toJson() => <String, Object?>{
    'items': items.map((value) => value.toJson()).toList(growable: false),
    'total': total,
    'limit': limit,
    'offset': offset,
  };
}

/// Management permission checked by the application-owned authorizer.
enum AuthScimConnectionManagementOperation {
  /// Creates a connection.
  create,

  /// Lists connections.
  list,

  /// Updates a connection.
  update,

  /// Disables a connection.
  disable,

  /// Lists connection credentials.
  credentialsList,

  /// Issues a connection credential.
  credentialsIssue,

  /// Rotates a connection credential.
  credentialsRotate,

  /// Revokes a connection credential.
  credentialsRevoke,
}

/// Authorization input for a managed SCIM operation.
final class AuthScimConnectionAuthorizationRequest<TContext> {
  /// Creates an authorization request for one management operation.
  const AuthScimConnectionAuthorizationRequest({
    required this.invocation,
    required this.operation,
    required this.organizationId,
  });

  /// Invocation containing the authenticated request context.
  final AuthOperationInvocation<TContext> invocation;

  /// Management operation being authorized.
  final AuthScimConnectionManagementOperation operation;

  /// Organization whose connection is being accessed.
  final String organizationId;
}

/// Exact principal and tenancy binding selected by application policy.
///
/// For session-authenticated management endpoints, [subjectId] must equal the
/// authenticated user's canonical ID. The plugin rejects a mismatched subject
/// so credential ownership and coordinated user deletion cannot be assigned to
/// another account by a faulty authorizer.
final class AuthScimConnectionManagementPrincipal {
  /// Creates the exact principal and tenancy returned by an authorizer.
  AuthScimConnectionManagementPrincipal({
    required String tenantId,
    required String organizationId,
    required String subjectId,
  }) : tenantId = _identifier(tenantId, 'tenantId'),
       organizationId = _identifier(organizationId, 'organizationId'),
       subjectId = _identifier(subjectId, 'subjectId');

  /// Tenant containing the organization.
  final String tenantId;

  /// Organization whose connection is being managed.
  final String organizationId;

  /// Canonical subject authorized to manage the connection.
  final String subjectId;

  /// The tenant and organization boundary represented by this principal.
  AuthScimConnectionBinding get binding => AuthScimConnectionBinding(
    tenantId: tenantId,
    organizationId: organizationId,
  );
}

/// Application-owned authorization boundary for connection administration.
typedef AuthScimConnectionAuthorizer<TContext> =
    FutureOr<AuthScimConnectionManagementPrincipal?> Function(
      AuthScimConnectionAuthorizationRequest<TContext> request,
    );

/// Parses and validates a SCIM scope collection.
Set<AuthScimScope> authScimParseScopes(Object? value) =>
    _scopes(_scopeValues(value));

/// Returns a stable sorted fingerprint for [scopes].
String authScimScopeFingerprint(Iterable<AuthScimScope> scopes) =>
    (_scopes(scopes).map((value) => value.name).toList()..sort()).join(',');

/// Whether [granted] permits every exact scope in [requested].
bool authScimScopesAllow(
  Iterable<AuthScimScope> granted,
  Iterable<AuthScimScope> requested,
) {
  final values = granted.toSet();
  return requested.every(
    (scope) =>
        values.contains(scope) ||
        scope == AuthScimScope.usersRead &&
            values.contains(AuthScimScope.usersWrite) ||
        scope == AuthScimScope.groupsRead &&
            values.contains(AuthScimScope.groupsWrite),
  );
}

String _identifier(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 256 ||
      _hasControl(normalized)) {
    throw ArgumentError('Invalid bounded $name.');
  }
  return normalized;
}

String _displayName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 128 || _hasControl(value)) {
    throw ArgumentError('Invalid bounded name.');
  }
  return normalized;
}

String _prefix(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 32 || _hasControl(normalized)) {
    throw ArgumentError('Invalid bounded keyPrefix.');
  }
  return normalized;
}

String _digest(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(normalized)) {
    throw ArgumentError('Invalid strong secretDigest.');
  }
  return normalized;
}

Set<AuthScimScope> _scopes(Iterable<AuthScimScope> values) =>
    Set<AuthScimScope>.unmodifiable(values.toSet());

Iterable<AuthScimScope> _scopeValues(Object? value) {
  if (value is! List || value.isEmpty || value.length > 4) {
    throw const FormatException('Invalid SCIM scopes.');
  }
  return value.map((entry) {
    if (entry is! String) throw const FormatException('Invalid SCIM scope.');
    return AuthScimScope.values.firstWhere(
      (scope) => scope.name == entry,
      orElse: () => throw const FormatException('Invalid SCIM scope.'),
    );
  });
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed.toUtc();
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed.toUtc();
}

bool _hasControl(String value) =>
    value.codeUnits.any((code) => code < 0x20 || code == 0x7f);
