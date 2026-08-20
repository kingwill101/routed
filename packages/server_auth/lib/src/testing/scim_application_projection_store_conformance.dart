import 'dart:async';

import '../core/scim_application_projection.dart';

typedef AuthScimApplicationProjectionStoreConformanceFactory =
    FutureOr<AuthScimApplicationProjectionStoreConformanceFixture> Function();

enum AuthScimApplicationProjectionStoreConformanceFaultPoint {
  apply,
  reconcile,
  deleteScope,
}

abstract interface class AuthScimApplicationProjectionStoreConformanceFaultController {
  void failNext(AuthScimApplicationProjectionStoreConformanceFaultPoint point);
}

final class AuthScimApplicationProjectionStoreConformanceFixture {
  const AuthScimApplicationProjectionStoreConformanceFixture({
    required this.store,
    required this.faults,
    this.dispose,
  });

  final AuthScimApplicationProjectionStore store;
  final AuthScimApplicationProjectionStoreConformanceFaultController faults;
  final FutureOr<void> Function()? dispose;
}

final class AuthScimApplicationProjectionStoreConformanceFailure
    implements Exception {
  const AuthScimApplicationProjectionStoreConformanceFailure(
    this.caseId,
    this.cause,
  );

  final String caseId;
  final Object cause;

  @override
  String toString() =>
      'AuthScimApplicationProjectionStoreConformanceFailure($caseId): $cause';
}

final class AuthScimApplicationProjectionStoreConformanceCase {
  const AuthScimApplicationProjectionStoreConformanceCase({
    required this.id,
    required this.description,
    required Future<void> Function() run,
  }) : _run = run;

  final String id;
  final String description;
  final Future<void> Function() _run;

  Future<void> run() => _run();
}

/// Reusable contract for durable application-owned SCIM projection adapters.
///
/// The suite verifies stable connection/resource identity, optimistic and
/// idempotent mutation, rollback, reconciliation, isolation, and final scope
/// deletion. It intentionally has no auth-user or session fixture: projection
/// records must remain unable to create a sign-in method or grant access.
final class AuthScimApplicationProjectionStoreConformanceSuite {
  AuthScimApplicationProjectionStoreConformanceSuite(this.createFixture);

  final AuthScimApplicationProjectionStoreConformanceFactory createFixture;

  List<AuthScimApplicationProjectionStoreConformanceCase> get cases => [
    _case(
      'apply_replay_binding',
      'Apply is idempotent and an operation cannot be rebound.',
      _applyReplayBinding,
    ),
    _case(
      'scope_resource_isolation',
      'Equal resource IDs remain isolated by the exact connection scope.',
      _scopeResourceIsolation,
    ),
    _case(
      'optimistic_version',
      'Updates require the current projection version.',
      _optimisticVersion,
    ),
    _case(
      'resource_tombstone_final',
      'A tombstoned resource cannot be reactivated.',
      _resourceTombstoneFinal,
    ),
    _case(
      'membership_integrity',
      'Groups cannot reference missing or tombstoned subjects.',
      _membershipIntegrity,
    ),
    _case(
      'apply_rollback',
      'A failed apply leaves no record or replay receipt.',
      _applyRollback,
    ),
    _case(
      'apply_contention',
      'Concurrent identical apply commands commit exactly once.',
      _applyContention,
    ),
    _case(
      'drift_classification',
      'Drift distinguishes missing, divergent, and unexpected subjects.',
      _driftClassification,
    ),
    _case(
      'reconcile_atomic',
      'Reconciliation creates, updates, and tombstones atomically.',
      _reconcileAtomic,
    ),
    _case(
      'reconcile_replay_stale',
      'Reconciliation binds replay payloads and rejects stale snapshots.',
      _reconcileReplayStale,
    ),
    _case(
      'reconcile_rollback',
      'Failed reconciliation restores every prior projection.',
      _reconcileRollback,
    ),
    _case(
      'scope_delete_fence',
      'Scope deletion is atomic, replay-safe, and permanently fenced.',
      _scopeDeleteFence,
    ),
    _case(
      'scope_delete_rollback',
      'Failed scope deletion restores records and removes its fence.',
      _scopeDeleteRollback,
    ),
    _case(
      'bounded_catalog',
      'Projection catalogs are deterministic, bounded, and scope-local.',
      _boundedCatalog,
    ),
  ];

  AuthScimApplicationProjectionStoreConformanceCase _case(
    String id,
    String description,
    Future<void> Function(AuthScimApplicationProjectionStoreConformanceFixture)
    body,
  ) => AuthScimApplicationProjectionStoreConformanceCase(
    id: id,
    description: description,
    run: () => _withFixture(id, body),
  );

  Future<void> _withFixture(
    String id,
    Future<void> Function(AuthScimApplicationProjectionStoreConformanceFixture)
    body,
  ) async {
    final fixture = await Future.sync(createFixture);
    try {
      await body(fixture);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AuthScimApplicationProjectionStoreConformanceFailure(id, error),
        stackTrace,
      );
    } finally {
      await Future.sync(() => fixture.dispose?.call());
    }
  }

  Future<void> _applyReplayBinding(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final command = _createCommand('apply-replay', _user('user-a'));
    final first = await fixture.store.apply(command);
    final replay = await fixture.store.apply(command);
    _require(first.status == AuthScimApplicationProjectionStatus.applied);
    _require(replay.status == AuthScimApplicationProjectionStatus.replayed);
    _require(first.record?.version == replay.record?.version);
    final mismatch = await fixture.store.apply(
      _createCommand('apply-replay', _user('user-b')),
    );
    _require(
      mismatch.status == AuthScimApplicationProjectionStatus.replayMismatch,
    );
    _require(await fixture.store.find(_user('user-b')) == null);
  }

  Future<void> _scopeResourceIsolation(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final first = _user('shared');
    final second = _user('shared', scope: _scope('connection-b'));
    await fixture.store.apply(_createCommand('isolation-a', first));
    await fixture.store.apply(_createCommand('isolation-b', second));
    _require((await fixture.store.find(first))?.subject == first);
    _require((await fixture.store.find(second))?.subject == second);
    _require(
      (await fixture.store.list(
            AuthScimApplicationProjectionQuery(scope: first.scope),
          )).total ==
          1,
    );
    _require(
      (await fixture.store.list(
            AuthScimApplicationProjectionQuery(scope: second.scope),
          )).total ==
          1,
    );
  }

  Future<void> _optimisticVersion(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final subject = _user('versioned');
    final created = await fixture.store.apply(
      _createCommand('version-create', subject),
    );
    final desired = _snapshot(subject, version: 'v2', digestSeed: 'b');
    final stale = await fixture.store.apply(
      AuthScimApplicationProjectionCommand(
        operationId: 'version-stale',
        mutation: AuthScimApplicationProjectionMutation.update,
        desired: desired,
        expectedVersion: 2,
      ),
    );
    _require(
      stale.status == AuthScimApplicationProjectionStatus.versionConflict,
    );
    final updated = await fixture.store.apply(
      AuthScimApplicationProjectionCommand(
        operationId: 'version-update',
        mutation: AuthScimApplicationProjectionMutation.update,
        desired: desired,
        expectedVersion: created.record!.version,
      ),
    );
    _require(updated.record?.version == 2);
  }

  Future<void> _resourceTombstoneFinal(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final subject = _user('tombstone-final');
    await fixture.store.apply(
      _createCommand('tombstone-final-create', subject),
    );
    final tombstoned = await fixture.store.apply(
      AuthScimApplicationProjectionCommand(
        operationId: 'tombstone-final-delete',
        mutation: AuthScimApplicationProjectionMutation.tombstone,
        desired: _snapshot(
          subject,
          version: 'v2',
          digestSeed: 'b',
          state: AuthScimApplicationProjectionState.tombstoned,
        ),
        expectedVersion: 1,
      ),
    );
    _require(tombstoned.record?.version == 2);
    final reactivated = await fixture.store.apply(
      AuthScimApplicationProjectionCommand(
        operationId: 'tombstone-final-reactivate',
        mutation: AuthScimApplicationProjectionMutation.update,
        desired: _snapshot(subject, version: 'v3', digestSeed: 'c'),
        expectedVersion: 2,
      ),
    );
    _require(
      reactivated.status ==
          AuthScimApplicationProjectionStatus.resourceTombstoned,
    );
    final page = await fixture.store.list(
      AuthScimApplicationProjectionQuery(scope: subject.scope),
    );
    final reconciled = await fixture.store.reconcile(
      AuthScimApplicationReconciliationCommand(
        operationId: 'tombstone-final-reconcile',
        scope: subject.scope,
        expectedProjectionSnapshotId: page.projectionSnapshotId,
        authoritative: <AuthScimApplicationProjectionSnapshot>[
          _snapshot(subject, version: 'v3', digestSeed: 'c'),
        ],
      ),
    );
    _require(
      reconciled.status ==
          AuthScimApplicationReconciliationStatus.tombstoneConflict,
    );
  }

  Future<void> _membershipIntegrity(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final member = _user('member-a');
    final group = AuthScimApplicationProjectionSubject(
      scope: member.scope,
      resourceId: 'group-a',
      kind: AuthScimApplicationSubjectKind.group,
    );
    final groupSnapshot = _snapshot(
      group,
      members: <AuthScimApplicationProjectionSubject>[member],
    );
    final missing = await fixture.store.apply(
      AuthScimApplicationProjectionCommand(
        operationId: 'membership-missing',
        mutation: AuthScimApplicationProjectionMutation.create,
        desired: groupSnapshot,
      ),
    );
    _require(
      missing.status == AuthScimApplicationProjectionStatus.memberConflict,
    );
    await fixture.store.apply(_createCommand('membership-member', member));
    final created = await fixture.store.apply(
      AuthScimApplicationProjectionCommand(
        operationId: 'membership-group',
        mutation: AuthScimApplicationProjectionMutation.create,
        desired: groupSnapshot,
      ),
    );
    _require(created.committed);
    final tombstone = await fixture.store.apply(
      AuthScimApplicationProjectionCommand(
        operationId: 'membership-tombstone',
        mutation: AuthScimApplicationProjectionMutation.tombstone,
        desired: _snapshot(
          member,
          state: AuthScimApplicationProjectionState.tombstoned,
        ),
        expectedVersion: 1,
      ),
    );
    _require(
      tombstone.status == AuthScimApplicationProjectionStatus.memberConflict,
    );
  }

  Future<void> _applyRollback(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final command = _createCommand('apply-rollback', _user('rollback'));
    fixture.faults.failNext(
      AuthScimApplicationProjectionStoreConformanceFaultPoint.apply,
    );
    await _throws(() => fixture.store.apply(command));
    _require(await fixture.store.find(command.desired.subject) == null);
    final retry = await fixture.store.apply(command);
    _require(retry.status == AuthScimApplicationProjectionStatus.applied);
  }

  Future<void> _applyContention(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final command = _createCommand('apply-contention', _user('contended'));
    final results = await Future.wait(
      List<Future<AuthScimApplicationProjectionResult>>.generate(
        16,
        (_) => Future.sync(() => fixture.store.apply(command)),
      ),
    );
    _require(
      results
              .where(
                (result) =>
                    result.status ==
                    AuthScimApplicationProjectionStatus.applied,
              )
              .length ==
          1,
    );
    _require(results.every((result) => result.committed));
  }

  Future<void> _driftClassification(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final divergent = _user('divergent');
    final unexpected = _user('unexpected');
    final missing = _user('missing');
    await fixture.store.apply(_createCommand('drift-a', divergent));
    await fixture.store.apply(_createCommand('drift-b', unexpected));
    final authoritative = <AuthScimApplicationProjectionSnapshot>[
      _snapshot(divergent, version: 'v2', digestSeed: 'b'),
      _snapshot(missing),
    ];
    final drift = await fixture.store.detectDrift(
      AuthScimApplicationProjectionDriftQuery(
        scope: divergent.scope,
        sourceSnapshotId: authScimApplicationSourceSnapshotId(
          divergent.scope,
          authoritative,
        ),
        authoritative: authoritative,
      ),
    );
    _require(drift.total == 3);
    _require(drift.findings.map((finding) => finding.kind).toSet().length == 3);
  }

  Future<void> _reconcileAtomic(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final updated = _user('updated');
    final removed = _user('removed');
    final created = _user('created');
    await fixture.store.apply(_createCommand('reconcile-a', updated));
    await fixture.store.apply(_createCommand('reconcile-b', removed));
    final before = await fixture.store.list(
      AuthScimApplicationProjectionQuery(scope: updated.scope),
    );
    final command = AuthScimApplicationReconciliationCommand(
      operationId: 'reconcile-atomic',
      scope: updated.scope,
      expectedProjectionSnapshotId: before.projectionSnapshotId,
      authoritative: <AuthScimApplicationProjectionSnapshot>[
        _snapshot(updated, version: 'v2', digestSeed: 'b'),
        _snapshot(created),
      ],
    );
    final result = await fixture.store.reconcile(command);
    _require(result.status == AuthScimApplicationReconciliationStatus.applied);
    _require(
      result.created == 1 && result.updated == 1 && result.tombstoned == 1,
    );
    _require((await fixture.store.find(updated))?.version == 2);
    _require((await fixture.store.find(created))?.version == 1);
    _require(
      (await fixture.store.find(removed))?.snapshot.state ==
          AuthScimApplicationProjectionState.tombstoned,
    );
  }

  Future<void> _reconcileReplayStale(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final subject = _user('replay');
    final command = AuthScimApplicationReconciliationCommand(
      operationId: 'reconcile-replay',
      scope: subject.scope,
      expectedProjectionSnapshotId:
          authScimEmptyApplicationProjectionSnapshotId,
      authoritative: <AuthScimApplicationProjectionSnapshot>[
        _snapshot(subject),
      ],
    );
    final first = await fixture.store.reconcile(command);
    final replay = await fixture.store.reconcile(command);
    _require(first.status == AuthScimApplicationReconciliationStatus.applied);
    _require(replay.status == AuthScimApplicationReconciliationStatus.replayed);

    final mismatch = await fixture.store.reconcile(
      AuthScimApplicationReconciliationCommand(
        operationId: command.operationId,
        scope: subject.scope,
        expectedProjectionSnapshotId: first.projectionSnapshotId,
        authoritative: const <AuthScimApplicationProjectionSnapshot>[],
      ),
    );
    _require(
      mismatch.status == AuthScimApplicationReconciliationStatus.replayMismatch,
    );
    final stale = await fixture.store.reconcile(
      AuthScimApplicationReconciliationCommand(
        operationId: 'reconcile-stale',
        scope: subject.scope,
        expectedProjectionSnapshotId:
            authScimEmptyApplicationProjectionSnapshotId,
        authoritative: const <AuthScimApplicationProjectionSnapshot>[],
      ),
    );
    _require(
      stale.status ==
          AuthScimApplicationReconciliationStatus.staleProjectionSnapshot,
    );
  }

  Future<void> _reconcileRollback(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final subject = _user('reconcile-rollback');
    await fixture.store.apply(
      _createCommand('reconcile-rollback-seed', subject),
    );
    final before = await fixture.store.list(
      AuthScimApplicationProjectionQuery(scope: subject.scope),
    );
    final command = AuthScimApplicationReconciliationCommand(
      operationId: 'reconcile-rollback',
      scope: subject.scope,
      expectedProjectionSnapshotId: before.projectionSnapshotId,
      authoritative: <AuthScimApplicationProjectionSnapshot>[
        _snapshot(subject, version: 'v2', digestSeed: 'b'),
      ],
    );
    fixture.faults.failNext(
      AuthScimApplicationProjectionStoreConformanceFaultPoint.reconcile,
    );
    await _throws(() => fixture.store.reconcile(command));
    final after = await fixture.store.list(
      AuthScimApplicationProjectionQuery(scope: subject.scope),
    );
    _require(after.projectionSnapshotId == before.projectionSnapshotId);
    final retry = await fixture.store.reconcile(command);
    _require(retry.status == AuthScimApplicationReconciliationStatus.applied);
  }

  Future<void> _scopeDeleteFence(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final subject = _user('delete-fence');
    await fixture.store.apply(_createCommand('delete-fence-seed', subject));
    final before = await fixture.store.list(
      AuthScimApplicationProjectionQuery(scope: subject.scope),
    );
    final command = AuthScimApplicationProjectionScopeDeletionCommand(
      operationId: 'delete-fence',
      scope: subject.scope,
      expectedProjectionSnapshotId: before.projectionSnapshotId,
    );
    final deleted = await fixture.store.deleteScope(command);
    final replay = await fixture.store.deleteScope(command);
    _require(
      deleted.status ==
          AuthScimApplicationProjectionScopeDeletionStatus.applied,
    );
    _require(deleted.deleted == 1);
    _require(
      replay.status ==
          AuthScimApplicationProjectionScopeDeletionStatus.replayed,
    );
    _require(await fixture.store.isScopeDeleted(subject.scope));
    _require(await fixture.store.find(subject) == null);
    final recreate = await fixture.store.apply(
      _createCommand('delete-fence-recreate', subject),
    );
    _require(
      recreate.status == AuthScimApplicationProjectionStatus.scopeDeleted,
    );
    final reconcile = await fixture.store.reconcile(
      AuthScimApplicationReconciliationCommand(
        operationId: 'delete-fence-reconcile',
        scope: subject.scope,
        expectedProjectionSnapshotId:
            authScimEmptyApplicationProjectionSnapshotId,
        authoritative: <AuthScimApplicationProjectionSnapshot>[
          _snapshot(subject),
        ],
      ),
    );
    _require(
      reconcile.status == AuthScimApplicationReconciliationStatus.scopeDeleted,
    );
  }

  Future<void> _scopeDeleteRollback(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    final subject = _user('delete-rollback');
    await fixture.store.apply(_createCommand('delete-rollback-seed', subject));
    final before = await fixture.store.list(
      AuthScimApplicationProjectionQuery(scope: subject.scope),
    );
    final command = AuthScimApplicationProjectionScopeDeletionCommand(
      operationId: 'delete-rollback',
      scope: subject.scope,
      expectedProjectionSnapshotId: before.projectionSnapshotId,
    );
    fixture.faults.failNext(
      AuthScimApplicationProjectionStoreConformanceFaultPoint.deleteScope,
    );
    await _throws(() => fixture.store.deleteScope(command));
    _require(!await fixture.store.isScopeDeleted(subject.scope));
    _require(await fixture.store.find(subject) != null);
    final retry = await fixture.store.deleteScope(command);
    _require(retry.committed);
  }

  Future<void> _boundedCatalog(
    AuthScimApplicationProjectionStoreConformanceFixture fixture,
  ) async {
    for (var index = 0; index < 5; index++) {
      final id = 'catalog-$index';
      await fixture.store.apply(_createCommand(id, _user(id)));
    }
    final page = await fixture.store.list(
      AuthScimApplicationProjectionQuery(scope: _scope(), offset: 1, limit: 2),
    );
    _require(page.total == 5 && page.records.length == 2);
    _require(page.records[0].subject.resourceId == 'catalog-1');
    _require(page.records[1].subject.resourceId == 'catalog-2');
  }
}

AuthScimApplicationProjectionScope _scope([
  String connectionId = 'connection-a',
]) => AuthScimApplicationProjectionScope(
  connectionId: connectionId,
  tenantId: 'tenant-a',
  organizationId: 'organization-a',
  provisioningDomainId: 'domain-a',
);

AuthScimApplicationProjectionSubject _user(
  String resourceId, {
  AuthScimApplicationProjectionScope? scope,
}) => AuthScimApplicationProjectionSubject(
  scope: scope ?? _scope(),
  resourceId: resourceId,
  kind: AuthScimApplicationSubjectKind.user,
);

AuthScimApplicationProjectionSnapshot _snapshot(
  AuthScimApplicationProjectionSubject subject, {
  String version = 'v1',
  String digestSeed = 'a',
  AuthScimApplicationProjectionState state =
      AuthScimApplicationProjectionState.active,
  Iterable<AuthScimApplicationProjectionSubject> members =
      const <AuthScimApplicationProjectionSubject>[],
}) => AuthScimApplicationProjectionSnapshot(
  subject: subject,
  sourceVersion: version,
  sourceDigest: digestSeed * 64,
  state: state,
  members: members,
);

AuthScimApplicationProjectionCommand _createCommand(
  String operationId,
  AuthScimApplicationProjectionSubject subject,
) => AuthScimApplicationProjectionCommand(
  operationId: operationId,
  mutation: AuthScimApplicationProjectionMutation.create,
  desired: _snapshot(subject),
);

void _require(bool condition, [String message = 'conformance check failed']) {
  if (!condition) throw StateError(message);
}

Future<void> _throws(FutureOr<Object?> Function() action) async {
  try {
    await Future.sync(action);
  } catch (_) {
    return;
  }
  throw StateError('expected operation to throw');
}
