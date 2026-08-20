import 'dart:async';

import 'deletion_transaction.dart';
import 'scim_connection_models.dart';
import 'scim_models.dart';

/// Stable failure codes returned by managed SCIM persistence adapters.
enum AuthScimConnectionStoreFailure {
  conflict,
  notFound,
  disabled,
  scopeMismatch,
  replayMismatch,
  capacity,
}

/// Sanitized managed-SCIM persistence failure.
final class AuthScimConnectionStoreException implements Exception {
  const AuthScimConnectionStoreException(this.failure);

  final AuthScimConnectionStoreFailure failure;

  @override
  String toString() => 'AuthScimConnectionStoreException(${failure.name})';
}

/// Required replay binding for an issuance transaction.
final class AuthScimIdempotencyBinding {
  AuthScimIdempotencyBinding({required String key, required String fingerprint})
    : key = _bounded(key, 'key', 128),
      fingerprint = _bounded(fingerprint, 'fingerprint', 512);

  final String key;
  final String fingerprint;
}

/// Atomic connection + initial credential creation command.
final class AuthScimCreateConnectionTransaction {
  const AuthScimCreateConnectionTransaction({
    required this.connection,
    required this.credential,
    required this.idempotency,
  });

  final AuthScimManagedConnection connection;
  final AuthScimCredentialRecord credential;
  final AuthScimIdempotencyBinding idempotency;
}

/// Atomic connection update command.
final class AuthScimUpdateConnectionTransaction {
  const AuthScimUpdateConnectionTransaction({
    required this.binding,
    required this.connection,
    required this.expectedUpdatedAt,
  });

  final AuthScimConnectionBinding binding;
  final AuthScimManagedConnection connection;
  final DateTime expectedUpdatedAt;
}

/// Atomic credential issuance command.
final class AuthScimIssueCredentialTransaction {
  const AuthScimIssueCredentialTransaction({
    required this.binding,
    required this.credential,
    required this.idempotency,
  });

  final AuthScimConnectionBinding binding;
  final AuthScimCredentialRecord credential;
  final AuthScimIdempotencyBinding idempotency;
}

/// Atomic revoke-old/create-new rotation command.
final class AuthScimRotateCredentialTransaction {
  const AuthScimRotateCredentialTransaction({
    required this.binding,
    required this.connectionId,
    required this.credentialId,
    required this.replacement,
    required this.revokedAt,
    required this.idempotency,
  });

  final AuthScimConnectionBinding binding;
  final String connectionId;
  final String credentialId;
  final AuthScimCredentialRecord replacement;
  final DateTime revokedAt;
  final AuthScimIdempotencyBinding idempotency;
}

/// Stored result of a one-time credential transaction.
final class AuthScimStoredCredentialIssuance {
  const AuthScimStoredCredentialIssuance({
    required this.credential,
    required this.replayed,
  });

  final AuthScimCredentialRecord credential;
  final bool replayed;
}

/// Stored result of connection creation.
final class AuthScimStoredConnectionCreation {
  const AuthScimStoredConnectionCreation({
    required this.connection,
    required this.credential,
    required this.replayed,
  });

  final AuthScimManagedConnection connection;
  final AuthScimCredentialRecord credential;
  final bool replayed;
}

/// Bounded connection query. Adapters must enforce the exact binding.
final class AuthScimConnectionCatalogQuery {
  AuthScimConnectionCatalogQuery({
    required this.binding,
    this.limit = 100,
    this.offset = 0,
  }) {
    _page(limit, offset);
  }

  final AuthScimConnectionBinding binding;
  final int limit;
  final int offset;
}

/// Bounded credential query. Adapters must enforce connection ownership.
final class AuthScimCredentialCatalogQuery {
  AuthScimCredentialCatalogQuery({
    required this.binding,
    required String connectionId,
    this.limit = 100,
    this.offset = 0,
  }) : connectionId = _bounded(connectionId, 'connectionId', 256) {
    _page(limit, offset);
  }

  final AuthScimConnectionBinding binding;
  final String connectionId;
  final int limit;
  final int offset;
}

/// Complete atomic persistence boundary for managed SCIM connections.
abstract interface class AuthScimConnectionStore {
  FutureOr<AuthScimStoredConnectionCreation> createConnection(
    AuthScimCreateConnectionTransaction transaction,
  );

  FutureOr<AuthScimConnectionPage> listConnections(
    AuthScimConnectionCatalogQuery query,
  );

  FutureOr<AuthScimManagedConnection?> findConnection(
    AuthScimConnectionBinding binding,
    String connectionId,
  );

  /// Updates metadata and atomically revokes credentials outside new scopes.
  FutureOr<AuthScimManagedConnection?> updateConnection(
    AuthScimUpdateConnectionTransaction transaction,
  );

  /// Disables a connection and revokes all credentials in one transaction.
  FutureOr<AuthScimManagedConnection?> disableConnection(
    AuthScimConnectionBinding binding,
    String connectionId, {
    required DateTime disabledAt,
  });

  FutureOr<AuthScimStoredCredentialIssuance> issueCredential(
    AuthScimIssueCredentialTransaction transaction,
  );

  FutureOr<AuthScimStoredCredentialIssuance?> rotateCredential(
    AuthScimRotateCredentialTransaction transaction,
  );

  FutureOr<AuthScimCredentialRecord?> revokeCredential(
    AuthScimConnectionBinding binding,
    String connectionId,
    String credentialId, {
    required DateTime revokedAt,
  });

  FutureOr<AuthScimCredentialPage> listCredentials(
    AuthScimCredentialCatalogQuery query, {
    required DateTime now,
  });

  /// Resolves and touches one credential in a single transaction.
  ///
  /// The adapter must validate digest, expiry, revocation, connection state,
  /// tenancy, and scopes before returning an immutable identity.
  FutureOr<AuthScimConnectionIdentity?> resolveCredentialDigest(
    String digest, {
    required DateTime now,
  });

  /// Atomically removes every connection and credential owned by [subjectId].
  FutureOr<void> deleteForSubject(String subjectId);

  /// Atomically removes every connection and credential in [tenantId].
  FutureOr<void> deleteForTenant(String tenantId);
}

/// Optional injected failure point used by adapter and rollback tests.
typedef AuthScimConnectionStoreFaultInjector =
    FutureOr<void> Function(String operation);

/// Bounded transactional in-memory implementation for tests and development.
final class InMemoryAuthScimConnectionStore
    implements AuthScimConnectionStore, AuthInMemoryUserDeletionStore {
  InMemoryAuthScimConnectionStore({
    this.maxConnections = 1000,
    this.maxCredentials = 10000,
    this.maxCredentialsPerConnection = 32,
    this.maxReplayRecords = 10000,
    this.replayTtl = const Duration(days: 1),
    this.injectFault,
  }) {
    if (maxConnections < 1 ||
        maxCredentials < 1 ||
        maxCredentialsPerConnection < 1 ||
        maxReplayRecords < 1 ||
        replayTtl <= Duration.zero) {
      throw ArgumentError('Managed SCIM store bounds must be positive.');
    }
  }

  final int maxConnections;
  final int maxCredentials;
  final int maxCredentialsPerConnection;
  final int maxReplayRecords;
  final Duration replayTtl;
  final AuthScimConnectionStoreFaultInjector? injectFault;

  final Map<String, AuthScimManagedConnection> _connections =
      <String, AuthScimManagedConnection>{};
  final Map<String, AuthScimCredentialRecord> _credentials =
      <String, AuthScimCredentialRecord>{};
  final Map<String, _ReplayRecord> _replays = <String, _ReplayRecord>{};
  Future<void> _tail = Future<void>.value();

  @override
  Object captureDeletionState() => _Snapshot(
    connections: Map<String, AuthScimManagedConnection>.of(_connections),
    credentials: Map<String, AuthScimCredentialRecord>.of(_credentials),
    replays: Map<String, _ReplayRecord>.of(_replays),
  );

  @override
  void restoreDeletionState(Object checkpoint) {
    final snapshot = checkpoint as _Snapshot;
    _restore(snapshot);
  }

  @override
  Future<AuthScimStoredConnectionCreation> createConnection(
    AuthScimCreateConnectionTransaction transaction,
  ) => _atomic('createConnection', () {
    final connection = transaction.connection;
    final credential = transaction.credential;
    _validateCredentialForConnection(connection, credential);
    final replayKey = _replayKey(
      connection.binding,
      'create',
      transaction.idempotency.key,
    );
    final replay = _readReplay(
      replayKey,
      transaction.idempotency.fingerprint,
      connection.createdAt,
    );
    if (replay != null) {
      final storedConnection = _connections[replay.connectionId];
      final storedCredential = _credentials[replay.credentialId];
      if (storedConnection == null || storedCredential == null) {
        throw const AuthScimConnectionStoreException(
          AuthScimConnectionStoreFailure.replayMismatch,
        );
      }
      return AuthScimStoredConnectionCreation(
        connection: storedConnection,
        credential: storedCredential,
        replayed: true,
      );
    }
    _pruneInactiveCredentials(connection.createdAt);
    _requireCapacity(connection.id);
    if (_connections.containsKey(connection.id) ||
        _credentials.containsKey(credential.id) ||
        _credentials.values.any(
          (value) => value.secretDigest == credential.secretDigest,
        )) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.conflict,
      );
    }
    _connections[connection.id] = connection;
    _credentials[credential.id] = credential;
    _writeReplay(
      replayKey,
      transaction.idempotency,
      connection.id,
      credential.id,
      connection.createdAt,
    );
    return AuthScimStoredConnectionCreation(
      connection: connection,
      credential: credential,
      replayed: false,
    );
  });

  @override
  Future<AuthScimConnectionPage> listConnections(
    AuthScimConnectionCatalogQuery query,
  ) => _atomic('listConnections', () {
    final values =
        _connections.values
            .where((value) => _matches(value, query.binding))
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return AuthScimConnectionPage(
      items: _slice(values, query.offset, query.limit),
      total: values.length,
      limit: query.limit,
      offset: query.offset,
    );
  }, write: false);

  @override
  Future<AuthScimManagedConnection?> findConnection(
    AuthScimConnectionBinding binding,
    String connectionId,
  ) => _atomic('findConnection', () {
    final value = _connections[connectionId.trim()];
    return value != null && _matches(value, binding) ? value : null;
  }, write: false);

  @override
  Future<AuthScimManagedConnection?> updateConnection(
    AuthScimUpdateConnectionTransaction transaction,
  ) => _atomic('updateConnection', () {
    final next = transaction.connection;
    final current = _connections[next.id];
    if (current == null || !_matches(current, transaction.binding)) return null;
    if (current.updatedAt != transaction.expectedUpdatedAt.toUtc() ||
        !_sameImmutableConnection(current, next) ||
        !next.isActive) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.conflict,
      );
    }
    _connections[next.id] = next;
    for (final entry in _credentials.entries.toList(growable: false)) {
      final credential = entry.value;
      if (credential.connectionId == next.id &&
          !authScimScopesAllow(next.scopes, credential.scopes) &&
          credential.revokedAt == null) {
        _credentials[entry.key] = credential.copyWith(
          updatedAt: next.updatedAt,
          revokedAt: next.updatedAt,
        );
      }
    }
    return next;
  });

  @override
  Future<AuthScimManagedConnection?> disableConnection(
    AuthScimConnectionBinding binding,
    String connectionId, {
    required DateTime disabledAt,
  }) => _atomic('disableConnection', () {
    final current = _connections[connectionId.trim()];
    if (current == null || !_matches(current, binding)) return null;
    final now = disabledAt.toUtc();
    final disabled = current.disabledAt == null
        ? current.copyWith(updatedAt: now, disabledAt: now)
        : current;
    _connections[current.id] = disabled;
    for (final entry in _credentials.entries.toList(growable: false)) {
      final credential = entry.value;
      if (credential.connectionId == current.id &&
          credential.revokedAt == null) {
        _credentials[entry.key] = credential.copyWith(
          updatedAt: now,
          revokedAt: now,
        );
      }
    }
    return disabled;
  });

  @override
  Future<AuthScimStoredCredentialIssuance> issueCredential(
    AuthScimIssueCredentialTransaction transaction,
  ) => _atomic('issueCredential', () {
    final credential = transaction.credential;
    final connection = _connections[credential.connectionId];
    if (connection == null || !_matches(connection, transaction.binding)) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.notFound,
      );
    }
    _validateCredentialForConnection(connection, credential);
    if (!connection.isActive) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.disabled,
      );
    }
    final replayKey = _replayKey(
      transaction.binding,
      'issue:${connection.id}',
      transaction.idempotency.key,
    );
    final replay = _readReplay(
      replayKey,
      transaction.idempotency.fingerprint,
      credential.createdAt,
    );
    if (replay != null) {
      final stored = _credentials[replay.credentialId];
      if (stored == null || stored.connectionId != connection.id) {
        throw const AuthScimConnectionStoreException(
          AuthScimConnectionStoreFailure.replayMismatch,
        );
      }
      return AuthScimStoredCredentialIssuance(
        credential: stored,
        replayed: true,
      );
    }
    _prepareCredentialInsert(connection.id, credential, credential.createdAt);
    _credentials[credential.id] = credential;
    _writeReplay(
      replayKey,
      transaction.idempotency,
      connection.id,
      credential.id,
      credential.createdAt,
    );
    return AuthScimStoredCredentialIssuance(
      credential: credential,
      replayed: false,
    );
  });

  @override
  Future<AuthScimStoredCredentialIssuance?> rotateCredential(
    AuthScimRotateCredentialTransaction transaction,
  ) => _atomic('rotateCredential', () {
    final connection = _connections[transaction.connectionId.trim()];
    if (connection == null || !_matches(connection, transaction.binding)) {
      return null;
    }
    if (!connection.isActive) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.disabled,
      );
    }
    _validateCredentialForConnection(connection, transaction.replacement);
    final replayKey = _replayKey(
      transaction.binding,
      'rotate:${connection.id}:${transaction.credentialId.trim()}',
      transaction.idempotency.key,
    );
    final replay = _readReplay(
      replayKey,
      transaction.idempotency.fingerprint,
      transaction.revokedAt,
    );
    if (replay != null) {
      final stored = _credentials[replay.credentialId];
      if (stored == null || stored.connectionId != connection.id) {
        throw const AuthScimConnectionStoreException(
          AuthScimConnectionStoreFailure.replayMismatch,
        );
      }
      return AuthScimStoredCredentialIssuance(
        credential: stored,
        replayed: true,
      );
    }
    final current = _credentials[transaction.credentialId.trim()];
    final now = transaction.revokedAt.toUtc();
    if (current == null ||
        current.connectionId != connection.id ||
        !current.isActiveAt(now)) {
      return null;
    }
    _credentials[current.id] = current.copyWith(updatedAt: now, revokedAt: now);
    _prepareCredentialInsert(connection.id, transaction.replacement, now);
    _credentials[transaction.replacement.id] = transaction.replacement;
    _writeReplay(
      replayKey,
      transaction.idempotency,
      connection.id,
      transaction.replacement.id,
      now,
    );
    return AuthScimStoredCredentialIssuance(
      credential: transaction.replacement,
      replayed: false,
    );
  });

  @override
  Future<AuthScimCredentialRecord?> revokeCredential(
    AuthScimConnectionBinding binding,
    String connectionId,
    String credentialId, {
    required DateTime revokedAt,
  }) => _atomic('revokeCredential', () {
    final connection = _connections[connectionId.trim()];
    final current = _credentials[credentialId.trim()];
    if (connection == null ||
        !_matches(connection, binding) ||
        current == null ||
        current.connectionId != connection.id) {
      return null;
    }
    if (current.revokedAt != null) return current;
    final now = revokedAt.toUtc();
    final revoked = current.copyWith(updatedAt: now, revokedAt: now);
    _credentials[current.id] = revoked;
    return revoked;
  });

  @override
  Future<AuthScimCredentialPage> listCredentials(
    AuthScimCredentialCatalogQuery query, {
    required DateTime now,
  }) => _atomic('listCredentials', () {
    final connection = _connections[query.connectionId];
    if (connection == null || !_matches(connection, query.binding)) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.notFound,
      );
    }
    final values =
        _credentials.values
            .where((value) => value.connectionId == connection.id)
            .toList(growable: false)
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final page = _slice(
      values,
      query.offset,
      query.limit,
    ).map((value) => value.toPublic(now: now)).toList(growable: false);
    return AuthScimCredentialPage(
      items: page,
      total: values.length,
      limit: query.limit,
      offset: query.offset,
    );
  }, write: false);

  @override
  Future<AuthScimConnectionIdentity?> resolveCredentialDigest(
    String digest, {
    required DateTime now,
  }) => _atomic('resolveCredentialDigest', () {
    final normalized = digest.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(normalized)) return null;
    AuthScimCredentialRecord? credential;
    for (final candidate in _credentials.values) {
      if (candidate.secretDigest == normalized) {
        credential = candidate;
        break;
      }
    }
    final current = now.toUtc();
    if (credential == null || !credential.isActiveAt(current)) return null;
    final connection = _connections[credential.connectionId];
    if (connection == null ||
        !connection.isActive ||
        connection.tenantId != credential.tenantId ||
        connection.organizationId != credential.organizationId ||
        !authScimScopesAllow(connection.scopes, credential.scopes)) {
      return null;
    }
    final touched = credential.copyWith(
      updatedAt: current,
      lastUsedAt: current,
    );
    _credentials[credential.id] = touched;
    return AuthScimConnectionIdentity(
      connectionId: connection.id,
      credentialId: credential.id,
      tenantId: connection.tenantId,
      organizationId: connection.organizationId,
      provisioningDomainId: connection.provisioningDomainId,
      subjectId: connection.subjectId,
      scopes: credential.scopes,
      expiresAt: credential.expiresAt,
    );
  });

  @override
  Future<void> deleteForSubject(String subjectId) =>
      _atomic('deleteForSubject', () {
        final normalized = subjectId.trim();
        final ids = _connections.values
            .where((value) => value.subjectId == normalized)
            .map((value) => value.id)
            .toSet();
        _deleteConnections(ids);
      });

  @override
  Future<void> deleteForTenant(String tenantId) =>
      _atomic('deleteForTenant', () {
        final normalized = tenantId.trim();
        final ids = _connections.values
            .where((value) => value.tenantId == normalized)
            .map((value) => value.id)
            .toSet();
        _deleteConnections(ids);
      });

  @override
  Future<void> deleteUserDataForDeletion(String userId) =>
      deleteForSubject(userId);

  Future<T> _atomic<T>(
    String operation,
    FutureOr<T> Function() body, {
    bool write = true,
  }) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return (() async {
      await previous;
      final snapshot = write ? captureDeletionState() as _Snapshot : null;
      try {
        final result = await Future<T>.sync(body);
        if (write) await Future.sync(() => injectFault?.call(operation));
        done.complete();
        return result;
      } catch (error, stackTrace) {
        if (snapshot != null) _restore(snapshot);
        done.complete();
        Error.throwWithStackTrace(error, stackTrace);
      }
    })();
  }

  void _prepareCredentialInsert(
    String connectionId,
    AuthScimCredentialRecord credential,
    DateTime now,
  ) {
    _pruneInactiveCredentials(now);
    if (_credentials.containsKey(credential.id) ||
        _credentials.values.any(
          (value) => value.secretDigest == credential.secretDigest,
        )) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.conflict,
      );
    }
    final owned = _credentials.values
        .where((value) => value.connectionId == connectionId)
        .length;
    if (_credentials.length >= maxCredentials ||
        owned >= maxCredentialsPerConnection) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.capacity,
      );
    }
  }

  void _pruneInactiveCredentials(DateTime now) {
    final current = now.toUtc();
    final inactive =
        _credentials.values
            .where((value) => !value.isActiveAt(current))
            .toList()
          ..sort((left, right) => left.updatedAt.compareTo(right.updatedAt));
    while ((_credentials.length >= maxCredentials ||
            _connectionOverCapacity()) &&
        inactive.isNotEmpty) {
      _credentials.remove(inactive.removeAt(0).id);
    }
  }

  bool _connectionOverCapacity() {
    final counts = <String, int>{};
    for (final value in _credentials.values) {
      counts.update(
        value.connectionId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return counts.values.any((count) => count >= maxCredentialsPerConnection);
  }

  void _requireCapacity(String connectionId) {
    _pruneExpiredReplays(DateTime.now().toUtc());
    if (_connections.length >= maxConnections ||
        _credentials.length >= maxCredentials ||
        _replays.length >= maxReplayRecords) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.capacity,
      );
    }
    if (_credentials.values
            .where((value) => value.connectionId == connectionId)
            .length >=
        maxCredentialsPerConnection) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.capacity,
      );
    }
  }

  void _validateCredentialForConnection(
    AuthScimManagedConnection connection,
    AuthScimCredentialRecord credential,
  ) {
    if (credential.connectionId != connection.id ||
        credential.tenantId != connection.tenantId ||
        credential.organizationId != connection.organizationId ||
        !authScimScopesAllow(connection.scopes, credential.scopes)) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.scopeMismatch,
      );
    }
  }

  _ReplayRecord? _readReplay(String key, String fingerprint, DateTime now) {
    _pruneExpiredReplays(now.toUtc());
    final replay = _replays[key];
    if (replay == null) return null;
    if (replay.fingerprint != fingerprint) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.replayMismatch,
      );
    }
    return replay;
  }

  void _writeReplay(
    String key,
    AuthScimIdempotencyBinding binding,
    String connectionId,
    String credentialId,
    DateTime now,
  ) {
    _pruneExpiredReplays(now.toUtc());
    if (_replays.length >= maxReplayRecords) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.capacity,
      );
    }
    _replays[key] = _ReplayRecord(
      fingerprint: binding.fingerprint,
      connectionId: connectionId,
      credentialId: credentialId,
      expiresAt: now.toUtc().add(replayTtl),
    );
  }

  void _pruneExpiredReplays(DateTime now) {
    _replays.removeWhere((_, value) => !value.expiresAt.isAfter(now));
  }

  void _deleteConnections(Set<String> ids) {
    _connections.removeWhere((id, _) => ids.contains(id));
    _credentials.removeWhere((_, value) => ids.contains(value.connectionId));
    _replays.removeWhere((_, value) => ids.contains(value.connectionId));
  }

  void _restore(_Snapshot snapshot) {
    _connections
      ..clear()
      ..addAll(snapshot.connections);
    _credentials
      ..clear()
      ..addAll(snapshot.credentials);
    _replays
      ..clear()
      ..addAll(snapshot.replays);
  }
}

final class _ReplayRecord {
  const _ReplayRecord({
    required this.fingerprint,
    required this.connectionId,
    required this.credentialId,
    required this.expiresAt,
  });

  final String fingerprint;
  final String connectionId;
  final String credentialId;
  final DateTime expiresAt;
}

final class _Snapshot {
  const _Snapshot({
    required this.connections,
    required this.credentials,
    required this.replays,
  });

  final Map<String, AuthScimManagedConnection> connections;
  final Map<String, AuthScimCredentialRecord> credentials;
  final Map<String, _ReplayRecord> replays;
}

bool _matches(
  AuthScimManagedConnection connection,
  AuthScimConnectionBinding binding,
) =>
    connection.tenantId == binding.tenantId &&
    connection.organizationId == binding.organizationId;

bool _sameImmutableConnection(
  AuthScimManagedConnection current,
  AuthScimManagedConnection next,
) =>
    current.id == next.id &&
    current.tenantId == next.tenantId &&
    current.organizationId == next.organizationId &&
    current.subjectId == next.subjectId &&
    current.createdAt == next.createdAt;

String _replayKey(
  AuthScimConnectionBinding binding,
  String operation,
  String idempotencyKey,
) =>
    '${binding.tenantId}\u0000${binding.organizationId}\u0000'
    '$operation\u0000$idempotencyKey';

List<T> _slice<T>(List<T> values, int offset, int limit) {
  if (offset >= values.length) return <T>[];
  final end = (offset + limit).clamp(offset, values.length);
  return List<T>.unmodifiable(values.sublist(offset, end));
}

String _bounded(String value, String name, int maximum) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maximum ||
      normalized.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
    throw ArgumentError('Invalid bounded $name.');
  }
  return normalized;
}

void _page(int limit, int offset) {
  if (limit < 1 || limit > 200 || offset < 0 || offset > 1000000) {
    throw ArgumentError('Invalid bounded catalog page.');
  }
}
