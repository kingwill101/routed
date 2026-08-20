import 'dart:async';

import '../core/scim_connection_models.dart';
import '../core/scim_connection_store.dart';
import '../core/scim_models.dart';

typedef AuthScimConnectionStoreConformanceFactory =
    FutureOr<AuthScimConnectionStoreConformanceFixture> Function();

final class AuthScimConnectionStoreConformanceFixture {
  const AuthScimConnectionStoreConformanceFixture({
    required this.store,
    this.dispose,
  });

  final AuthScimConnectionStore store;
  final FutureOr<void> Function()? dispose;
}

final class AuthScimConnectionStoreConformanceFailure implements Exception {
  const AuthScimConnectionStoreConformanceFailure(this.caseId, this.cause);

  final String caseId;
  final Object cause;

  @override
  String toString() =>
      'AuthScimConnectionStoreConformanceFailure($caseId): $cause';
}

final class AuthScimConnectionStoreConformanceCase {
  const AuthScimConnectionStoreConformanceCase({
    required this.id,
    required this.description,
    required Future<void> Function() run,
  }) : _run = run;

  final String id;
  final String description;
  final Future<void> Function() _run;

  Future<void> run() => _run();
}

/// Reusable contract for durable managed-SCIM connection adapters.
final class AuthScimConnectionStoreConformanceSuite {
  AuthScimConnectionStoreConformanceSuite(this.createFixture);

  final AuthScimConnectionStoreConformanceFactory createFixture;

  List<AuthScimConnectionStoreConformanceCase> get cases => [
    _case('create_replay', 'Create is atomic and replay-safe.', _createReplay),
    _case(
      'replay_mismatch',
      'An idempotency key cannot be rebound to another payload.',
      _replayMismatch,
    ),
    _case(
      'binding_isolation',
      'Connection catalogs and credentials enforce exact tenancy.',
      _bindingIsolation,
    ),
    _case(
      'disable_revokes',
      'Disabling a connection revokes every live credential atomically.',
      _disableRevokes,
    ),
    _case(
      'rotate_atomic',
      'Rotation revokes the old digest and activates one replacement.',
      _rotateAtomic,
    ),
    _case(
      'subject_delete',
      'Subject deletion removes connection and credential state.',
      _subjectDelete,
    ),
    _case(
      'tenant_delete',
      'Tenant deletion removes every tenant connection and credential.',
      _tenantDelete,
    ),
    _case(
      'contention',
      'Concurrent identical create requests commit once.',
      _contention,
    ),
  ];

  AuthScimConnectionStoreConformanceCase _case(
    String id,
    String description,
    Future<void> Function(AuthScimConnectionStore store) body,
  ) => AuthScimConnectionStoreConformanceCase(
    id: id,
    description: description,
    run: () => _withFixture(id, body),
  );

  Future<void> _withFixture(
    String id,
    Future<void> Function(AuthScimConnectionStore store) body,
  ) async {
    final fixture = await Future.sync(createFixture);
    try {
      await body(fixture.store);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AuthScimConnectionStoreConformanceFailure(id, error),
        stackTrace,
      );
    } finally {
      await Future.sync(() => fixture.dispose?.call());
    }
  }

  Future<void> _createReplay(AuthScimConnectionStore store) async {
    final transaction = _createTransaction();
    final first = await store.createConnection(transaction);
    final second = await store.createConnection(transaction);
    _require(!first.replayed, 'first create was reported as a replay');
    _require(second.replayed, 'second create was not reported as a replay');
    _require(first.connection.id == second.connection.id, 'connection changed');
    _require(first.credential.id == second.credential.id, 'credential changed');
  }

  Future<void> _replayMismatch(AuthScimConnectionStore store) async {
    final transaction = _createTransaction();
    await store.createConnection(transaction);
    try {
      await store.createConnection(
        AuthScimCreateConnectionTransaction(
          connection: transaction.connection,
          credential: transaction.credential,
          idempotency: AuthScimIdempotencyBinding(
            key: transaction.idempotency.key,
            fingerprint: 'different-payload',
          ),
        ),
      );
      throw StateError('replay mismatch was accepted');
    } on AuthScimConnectionStoreException catch (error) {
      _require(
        error.failure == AuthScimConnectionStoreFailure.replayMismatch,
        'wrong replay mismatch failure',
      );
    }
  }

  Future<void> _bindingIsolation(AuthScimConnectionStore store) async {
    final created = await store.createConnection(_createTransaction());
    final page = await store.listConnections(
      AuthScimConnectionCatalogQuery(binding: _otherBinding()),
    );
    _require(page.total == 0, 'connection crossed tenancy boundary');
    final credentialPage = await store.listCredentials(
      AuthScimCredentialCatalogQuery(
        binding: _binding(),
        connectionId: created.connection.id,
      ),
      now: _now,
    );
    _require(credentialPage.total == 1, 'credential was not cataloged');
  }

  Future<void> _disableRevokes(AuthScimConnectionStore store) async {
    final created = await store.createConnection(_createTransaction());
    final disabled = await store.disableConnection(
      _binding(),
      created.connection.id,
      disabledAt: _now.add(const Duration(minutes: 1)),
    );
    _require(disabled?.isActive == false, 'connection stayed active');
    final identity = await store.resolveCredentialDigest(
      created.credential.secretDigest,
      now: _now.add(const Duration(minutes: 2)),
    );
    _require(identity == null, 'disabled credential still authenticated');
  }

  Future<void> _rotateAtomic(AuthScimConnectionStore store) async {
    final created = await store.createConnection(_createTransaction());
    final replacement = _credential(
      id: 'credential-b',
      digest: _digest('b'),
      createdAt: _now.add(const Duration(minutes: 1)),
    );
    final rotated = await store.rotateCredential(
      AuthScimRotateCredentialTransaction(
        binding: _binding(),
        connectionId: created.connection.id,
        credentialId: created.credential.id,
        replacement: replacement,
        revokedAt: replacement.createdAt,
        idempotency: AuthScimIdempotencyBinding(
          key: 'rotate-1',
          fingerprint: 'rotate-fingerprint',
        ),
      ),
    );
    _require(rotated != null && !rotated.replayed, 'rotation did not commit');
    _require(
      await store.resolveCredentialDigest(
            created.credential.secretDigest,
            now: replacement.createdAt,
          ) ==
          null,
      'old credential remained live',
    );
    _require(
      await store.resolveCredentialDigest(
            replacement.secretDigest,
            now: replacement.createdAt,
          ) !=
          null,
      'replacement did not become live',
    );
  }

  Future<void> _subjectDelete(AuthScimConnectionStore store) async {
    final created = await store.createConnection(_createTransaction());
    await store.deleteForSubject(created.connection.subjectId);
    _require(
      await store.findConnection(_binding(), created.connection.id) == null,
      'subject connection survived deletion',
    );
    _require(
      await store.resolveCredentialDigest(
            created.credential.secretDigest,
            now: _now,
          ) ==
          null,
      'subject credential survived deletion',
    );
  }

  Future<void> _tenantDelete(AuthScimConnectionStore store) async {
    final created = await store.createConnection(_createTransaction());
    await store.deleteForTenant(created.connection.tenantId);
    _require(
      await store.findConnection(_binding(), created.connection.id) == null,
      'tenant connection survived deletion',
    );
  }

  Future<void> _contention(AuthScimConnectionStore store) async {
    final transaction = _createTransaction();
    final results = await Future.wait(
      List<Future<AuthScimStoredConnectionCreation>>.generate(
        12,
        (_) async => store.createConnection(transaction),
      ),
    );
    _require(
      results.where((value) => !value.replayed).length == 1,
      'contention committed more than one create',
    );
    _require(
      results.map((value) => value.connection.id).toSet().length == 1,
      'contention returned inconsistent connections',
    );
  }
}

final DateTime _now = DateTime.utc(2030, 1, 1, 12);

AuthScimConnectionBinding _binding() => AuthScimConnectionBinding(
  tenantId: 'tenant-a',
  organizationId: 'organization-a',
);

AuthScimConnectionBinding _otherBinding() => AuthScimConnectionBinding(
  tenantId: 'tenant-b',
  organizationId: 'organization-a',
);

AuthScimCreateConnectionTransaction _createTransaction() {
  final connection = AuthScimManagedConnection(
    id: 'connection-a',
    tenantId: _binding().tenantId,
    organizationId: _binding().organizationId,
    provisioningDomainId: 'directory-a',
    subjectId: 'user-a',
    name: 'Directory A',
    scopes: const <AuthScimScope>{
      AuthScimScope.usersRead,
      AuthScimScope.usersWrite,
    },
    createdAt: _now,
    updatedAt: _now,
  );
  return AuthScimCreateConnectionTransaction(
    connection: connection,
    credential: _credential(
      id: 'credential-a',
      digest: _digest('a'),
      createdAt: _now,
    ),
    idempotency: AuthScimIdempotencyBinding(
      key: 'create-1',
      fingerprint: 'create-fingerprint',
    ),
  );
}

AuthScimCredentialRecord _credential({
  required String id,
  required String digest,
  required DateTime createdAt,
}) => AuthScimCredentialRecord(
  id: id,
  connectionId: 'connection-a',
  tenantId: 'tenant-a',
  organizationId: 'organization-a',
  name: 'Provisioner',
  keyPrefix: 'rscim.cred',
  secretDigest: digest,
  scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
  createdAt: createdAt,
  updatedAt: createdAt,
  expiresAt: createdAt.add(const Duration(days: 30)),
);

String _digest(String value) => value.padRight(64, value);

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
