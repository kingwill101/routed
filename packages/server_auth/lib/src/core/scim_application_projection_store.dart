import 'dart:async';

import 'scim_application_projection.dart';

/// Bounded retention settings for the reference in-memory projection store.
final class AuthScimApplicationProjectionStoreOptions {
  /// Creates bounded receipt retention settings.
  AuthScimApplicationProjectionStoreOptions({
    this.maximumReceipts = 2048,
    this.receiptRetention = const Duration(days: 7),
  }) {
    if (maximumReceipts < 1 || maximumReceipts > 100000) {
      throw ArgumentError.value(maximumReceipts, 'maximumReceipts');
    }
    if (receiptRetention <= Duration.zero ||
        receiptRetention > const Duration(days: 365)) {
      throw ArgumentError.value(receiptRetention, 'receiptRetention');
    }
  }

  /// Maximum number of idempotency receipts retained.
  final int maximumReceipts;

  /// Maximum age of an idempotency receipt.
  final Duration receiptRetention;
}

/// Deterministic fault points exposed by the in-memory reference adapter.
enum AuthScimApplicationProjectionFaultPoint {
  /// Fault injection point after a direct projection write.
  afterProjectionWrite,

  /// Fault injection point during reconciliation.
  duringReconciliation,

  /// Fault injection point during scope deletion.
  duringScopeDeletion,
}

typedef AuthScimApplicationProjectionFaultInjector =
    FutureOr<void> Function(AuthScimApplicationProjectionFaultPoint point);

/// Transactional reference implementation of application-owned SCIM state.
///
/// The store contains no auth-user identifier, credential, email, username,
/// role, session, or sign-in operation. It serializes mutations, rolls back
/// failed writes, enforces exact scope/resource keys, and fences deleted
/// connection scopes. Durable adapters should implement the same behavior and
/// run [AuthScimApplicationProjectionStoreConformanceSuite] from
/// `package:server_auth/testing.dart`.
final class InMemoryAuthScimApplicationProjectionStore
    implements AuthScimApplicationProjectionStore {
  /// Creates a serialized, rollback-capable reference store.
  InMemoryAuthScimApplicationProjectionStore({
    AuthScimApplicationProjectionStoreOptions? options,
    DateTime Function()? clock,
    AuthScimApplicationProjectionFaultInjector? faultInjector,
  }) : options = options ?? AuthScimApplicationProjectionStoreOptions(),
       _clock = clock ?? DateTime.now,
       _faultInjector = faultInjector;

  /// Retention settings used by this store.
  final AuthScimApplicationProjectionStoreOptions options;
  final DateTime Function() _clock;
  final AuthScimApplicationProjectionFaultInjector? _faultInjector;

  final Map<
    AuthScimApplicationProjectionSubject,
    AuthScimApplicationProjectionRecord
  >
  _records =
      <
        AuthScimApplicationProjectionSubject,
        AuthScimApplicationProjectionRecord
      >{};
  final Map<String, _ProjectionReceipt> _receipts =
      <String, _ProjectionReceipt>{};
  final Set<AuthScimApplicationProjectionScope> _deletedScopes =
      <AuthScimApplicationProjectionScope>{};
  Future<void> _tail = Future<void>.value();

  /// Applies one command atomically and records its idempotency receipt.
  @override
  Future<AuthScimApplicationProjectionResult> apply(
    AuthScimApplicationProjectionCommand command,
  ) => _atomic(() async {
    final now = _clock().toUtc();
    _pruneReceipts(now);
    final scope = command.desired.subject.scope;
    if (_deletedScopes.contains(scope)) {
      return AuthScimApplicationProjectionResult(
        status: AuthScimApplicationProjectionStatus.scopeDeleted,
      );
    }
    final prior = _receipts[command.operationId];
    if (prior != null) {
      if (prior case _ApplyReceipt(
        :final payloadDigest,
        :final record,
      ) when payloadDigest == command.payloadDigest) {
        return AuthScimApplicationProjectionResult(
          status: AuthScimApplicationProjectionStatus.replayed,
          record: record,
        );
      }
      return AuthScimApplicationProjectionResult(
        status: AuthScimApplicationProjectionStatus.replayMismatch,
      );
    }

    final current = _records[command.desired.subject];
    if (command.mutation == AuthScimApplicationProjectionMutation.create) {
      if (current != null) {
        return AuthScimApplicationProjectionResult(
          status: AuthScimApplicationProjectionStatus.versionConflict,
        );
      }
    } else {
      if (current == null) {
        return AuthScimApplicationProjectionResult(
          status: AuthScimApplicationProjectionStatus.notFound,
        );
      }
      if (current.version != command.expectedVersion) {
        return AuthScimApplicationProjectionResult(
          status: AuthScimApplicationProjectionStatus.versionConflict,
        );
      }
    }
    if (current?.snapshot.state ==
            AuthScimApplicationProjectionState.tombstoned &&
        command.desired.state !=
            AuthScimApplicationProjectionState.tombstoned) {
      return AuthScimApplicationProjectionResult(
        status: AuthScimApplicationProjectionStatus.resourceTombstoned,
      );
    }
    if (!_membersAreActive(command.desired)) {
      return AuthScimApplicationProjectionResult(
        status: AuthScimApplicationProjectionStatus.memberConflict,
      );
    }
    if (command.desired.state ==
            AuthScimApplicationProjectionState.tombstoned &&
        _isReferenced(command.desired.subject)) {
      return AuthScimApplicationProjectionResult(
        status: AuthScimApplicationProjectionStatus.memberConflict,
      );
    }

    final recordsBefore =
        Map<
          AuthScimApplicationProjectionSubject,
          AuthScimApplicationProjectionRecord
        >.of(_records);
    final receiptsBefore = Map<String, _ProjectionReceipt>.of(_receipts);
    try {
      final record = AuthScimApplicationProjectionRecord(
        snapshot: command.desired,
        version: (current?.version ?? 0) + 1,
        updatedAt: now,
      );
      _records[record.subject] = record;
      await _inject(
        AuthScimApplicationProjectionFaultPoint.afterProjectionWrite,
      );
      _makeReceiptSpace();
      _receipts[command.operationId] = _ApplyReceipt(
        payloadDigest: command.payloadDigest,
        createdAt: now,
        record: record,
      );
      return AuthScimApplicationProjectionResult(
        status: AuthScimApplicationProjectionStatus.applied,
        record: record,
      );
    } catch (_) {
      _restore(_records, recordsBefore);
      _restore(_receipts, receiptsBefore);
      rethrow;
    }
  });

  /// Finds the current record for [subject], if it exists.
  @override
  Future<AuthScimApplicationProjectionRecord?> find(
    AuthScimApplicationProjectionSubject subject,
  ) => _atomic(() {
    if (_deletedScopes.contains(subject.scope)) return null;
    return _records[subject];
  });

  /// Lists records in [query].
  @override
  Future<AuthScimApplicationProjectionPage> list(
    AuthScimApplicationProjectionQuery query,
  ) => _atomic(() {
    final records = _scopeRecords(query.scope);
    final page = records
        .skip(query.offset)
        .take(query.limit)
        .toList(growable: false);
    return AuthScimApplicationProjectionPage(
      scope: query.scope,
      records: page,
      total: records.length,
      projectionSnapshotId: _projectionSnapshotId(query.scope),
    );
  });

  /// Compares projected state with authoritative state in [query].
  @override
  Future<AuthScimApplicationProjectionDriftPage> detectDrift(
    AuthScimApplicationProjectionDriftQuery query,
  ) => _atomic(() {
    final current =
        <
          AuthScimApplicationProjectionSubject,
          AuthScimApplicationProjectionRecord
        >{
          for (final record in _scopeRecords(query.scope))
            record.subject: record,
        };
    final authoritative =
        <
          AuthScimApplicationProjectionSubject,
          AuthScimApplicationProjectionSnapshot
        >{
          for (final snapshot in query.authoritative)
            snapshot.subject: snapshot,
        };
    final findings = <AuthScimApplicationProjectionDrift>[];
    for (final entry in authoritative.entries) {
      final existing = current[entry.key];
      if (existing == null) {
        findings.add(
          AuthScimApplicationProjectionDrift(
            kind: AuthScimApplicationProjectionDriftKind.missing,
            subject: entry.key,
            authoritative: entry.value,
          ),
        );
      } else if (!existing.snapshot.sameSourceAs(entry.value)) {
        findings.add(
          AuthScimApplicationProjectionDrift(
            kind: AuthScimApplicationProjectionDriftKind.diverged,
            subject: entry.key,
            authoritative: entry.value,
            current: existing,
          ),
        );
      }
    }
    for (final entry in current.entries) {
      if (!authoritative.containsKey(entry.key) &&
          entry.value.snapshot.state !=
              AuthScimApplicationProjectionState.tombstoned) {
        findings.add(
          AuthScimApplicationProjectionDrift(
            kind: AuthScimApplicationProjectionDriftKind.unexpected,
            subject: entry.key,
            current: entry.value,
          ),
        );
      }
    }
    findings.sort(
      (left, right) => _compareSubject(left.subject, right.subject),
    );
    return AuthScimApplicationProjectionDriftPage(
      scope: query.scope,
      findings: findings
          .skip(query.offset)
          .take(query.limit)
          .toList(growable: false),
      total: findings.length,
      projectionSnapshotId: _projectionSnapshotId(query.scope),
    );
  });

  /// Reconciles a complete authoritative snapshot atomically.
  @override
  Future<AuthScimApplicationReconciliationResult> reconcile(
    AuthScimApplicationReconciliationCommand command,
  ) => _atomic(() async {
    final now = _clock().toUtc();
    _pruneReceipts(now);
    if (_deletedScopes.contains(command.scope)) {
      return AuthScimApplicationReconciliationResult(
        status: AuthScimApplicationReconciliationStatus.scopeDeleted,
        projectionSnapshotId: authScimEmptyApplicationProjectionSnapshotId,
      );
    }
    final prior = _receipts[command.operationId];
    if (prior != null) {
      if (prior case _ReconciliationReceipt(
        :final payloadDigest,
        :final result,
      ) when payloadDigest == command.payloadDigest) {
        return AuthScimApplicationReconciliationResult(
          status: AuthScimApplicationReconciliationStatus.replayed,
          projectionSnapshotId: result.projectionSnapshotId,
          created: result.created,
          updated: result.updated,
          tombstoned: result.tombstoned,
        );
      }
      return AuthScimApplicationReconciliationResult(
        status: AuthScimApplicationReconciliationStatus.replayMismatch,
        projectionSnapshotId: _projectionSnapshotId(command.scope),
      );
    }
    if (_projectionSnapshotId(command.scope) !=
        command.expectedProjectionSnapshotId) {
      return AuthScimApplicationReconciliationResult(
        status: AuthScimApplicationReconciliationStatus.staleProjectionSnapshot,
        projectionSnapshotId: _projectionSnapshotId(command.scope),
      );
    }

    final authoritativeBySubject =
        <
          AuthScimApplicationProjectionSubject,
          AuthScimApplicationProjectionSnapshot
        >{
          for (final snapshot in command.authoritative)
            snapshot.subject: snapshot,
        };
    for (final current in _scopeRecords(command.scope)) {
      final desired = authoritativeBySubject[current.subject];
      if (current.snapshot.state ==
              AuthScimApplicationProjectionState.tombstoned &&
          desired != null &&
          desired.state != AuthScimApplicationProjectionState.tombstoned) {
        return AuthScimApplicationReconciliationResult(
          status: AuthScimApplicationReconciliationStatus.tombstoneConflict,
          projectionSnapshotId: _projectionSnapshotId(command.scope),
        );
      }
    }

    final recordsBefore =
        Map<
          AuthScimApplicationProjectionSubject,
          AuthScimApplicationProjectionRecord
        >.of(_records);
    final receiptsBefore = Map<String, _ProjectionReceipt>.of(_receipts);
    try {
      final authoritative = authoritativeBySubject;
      var created = 0;
      var updated = 0;
      var tombstoned = 0;
      final existing = _scopeRecords(command.scope);
      for (final snapshot in command.authoritative) {
        final current = _records[snapshot.subject];
        if (current == null) {
          _records[snapshot.subject] = AuthScimApplicationProjectionRecord(
            snapshot: snapshot,
            version: 1,
            updatedAt: now,
          );
          created++;
        } else if (!current.snapshot.sameSourceAs(snapshot)) {
          _records[snapshot.subject] = AuthScimApplicationProjectionRecord(
            snapshot: snapshot,
            version: current.version + 1,
            updatedAt: now,
          );
          updated++;
        }
      }
      for (final current in existing) {
        if (!authoritative.containsKey(current.subject) &&
            current.snapshot.state !=
                AuthScimApplicationProjectionState.tombstoned) {
          _records[current.subject] = AuthScimApplicationProjectionRecord(
            snapshot: AuthScimApplicationProjectionSnapshot(
              subject: current.subject,
              sourceVersion: command.sourceSnapshotId,
              sourceDigest: command.sourceSnapshotId,
              state: AuthScimApplicationProjectionState.tombstoned,
            ),
            version: current.version + 1,
            updatedAt: now,
          );
          tombstoned++;
        }
      }
      await _inject(
        AuthScimApplicationProjectionFaultPoint.duringReconciliation,
      );
      final result = AuthScimApplicationReconciliationResult(
        status: AuthScimApplicationReconciliationStatus.applied,
        projectionSnapshotId: _projectionSnapshotId(command.scope),
        created: created,
        updated: updated,
        tombstoned: tombstoned,
      );
      _makeReceiptSpace();
      _receipts[command.operationId] = _ReconciliationReceipt(
        payloadDigest: command.payloadDigest,
        createdAt: now,
        result: result,
      );
      return result;
    } catch (_) {
      _restore(_records, recordsBefore);
      _restore(_receipts, receiptsBefore);
      rethrow;
    }
  });

  /// Whether a deletion fence exists for [scope].
  @override
  Future<bool> isScopeDeleted(AuthScimApplicationProjectionScope scope) =>
      _atomic(() => _deletedScopes.contains(scope));

  /// Deletes all records in `command.scope` and installs its fence.
  @override
  Future<AuthScimApplicationProjectionScopeDeletionResult> deleteScope(
    AuthScimApplicationProjectionScopeDeletionCommand command,
  ) => _atomic(() async {
    final now = _clock().toUtc();
    _pruneReceipts(now);
    final prior = _receipts[command.operationId];
    if (prior != null) {
      if (prior case _ScopeDeletionReceipt(
        :final payloadDigest,
        :final result,
      ) when payloadDigest == command.payloadDigest) {
        return AuthScimApplicationProjectionScopeDeletionResult(
          status: AuthScimApplicationProjectionScopeDeletionStatus.replayed,
          deleted: result.deleted,
        );
      }
      return AuthScimApplicationProjectionScopeDeletionResult(
        status: AuthScimApplicationProjectionScopeDeletionStatus.replayMismatch,
        deleted: 0,
      );
    }
    if (_deletedScopes.contains(command.scope)) {
      return AuthScimApplicationProjectionScopeDeletionResult(
        status: AuthScimApplicationProjectionScopeDeletionStatus.applied,
        deleted: 0,
      );
    }
    if (_projectionSnapshotId(command.scope) !=
        command.expectedProjectionSnapshotId) {
      return AuthScimApplicationProjectionScopeDeletionResult(
        status: AuthScimApplicationProjectionScopeDeletionStatus
            .staleProjectionSnapshot,
        deleted: 0,
      );
    }

    final recordsBefore =
        Map<
          AuthScimApplicationProjectionSubject,
          AuthScimApplicationProjectionRecord
        >.of(_records);
    final receiptsBefore = Map<String, _ProjectionReceipt>.of(_receipts);
    final deletedBefore = Set<AuthScimApplicationProjectionScope>.of(
      _deletedScopes,
    );
    try {
      final subjects = _scopeRecords(
        command.scope,
      ).map((record) => record.subject).toList(growable: false);
      for (final subject in subjects) {
        _records.remove(subject);
      }
      _deletedScopes.add(command.scope);
      await _inject(
        AuthScimApplicationProjectionFaultPoint.duringScopeDeletion,
      );
      final result = AuthScimApplicationProjectionScopeDeletionResult(
        status: AuthScimApplicationProjectionScopeDeletionStatus.applied,
        deleted: subjects.length,
      );
      _makeReceiptSpace();
      _receipts[command.operationId] = _ScopeDeletionReceipt(
        payloadDigest: command.payloadDigest,
        createdAt: now,
        result: result,
      );
      return result;
    } catch (_) {
      _restore(_records, recordsBefore);
      _restore(_receipts, receiptsBefore);
      _restoreSet(_deletedScopes, deletedBefore);
      rethrow;
    }
  });

  List<AuthScimApplicationProjectionRecord> _scopeRecords(
    AuthScimApplicationProjectionScope scope,
  ) {
    if (_deletedScopes.contains(scope)) {
      return const <AuthScimApplicationProjectionRecord>[];
    }
    final records = _records.values
        .where((record) => record.subject.scope.sameBindingAs(scope))
        .toList(growable: false);
    records.sort((left, right) => _compareSubject(left.subject, right.subject));
    return records;
  }

  String _projectionSnapshotId(AuthScimApplicationProjectionScope scope) =>
      authScimApplicationSourceSnapshotId(
        scope,
        _scopeRecords(scope).map((record) => record.snapshot),
      );

  bool _membersAreActive(AuthScimApplicationProjectionSnapshot snapshot) {
    for (final member in snapshot.members) {
      final current = _records[member];
      if (current == null ||
          current.snapshot.state ==
              AuthScimApplicationProjectionState.tombstoned) {
        return false;
      }
    }
    return true;
  }

  bool _isReferenced(AuthScimApplicationProjectionSubject subject) => _records
      .values
      .where(
        (record) =>
            record.subject.scope.sameBindingAs(subject.scope) &&
            record.snapshot.state !=
                AuthScimApplicationProjectionState.tombstoned,
      )
      .any((record) => record.snapshot.members.contains(subject));

  Future<void> _inject(AuthScimApplicationProjectionFaultPoint point) async {
    final inject = _faultInjector;
    if (inject != null) await inject(point);
  }

  void _pruneReceipts(DateTime now) {
    final cutoff = now.subtract(options.receiptRetention);
    _receipts.removeWhere((_, receipt) => receipt.createdAt.isBefore(cutoff));
  }

  void _makeReceiptSpace() {
    while (_receipts.length >= options.maximumReceipts) {
      _receipts.remove(_receipts.keys.first);
    }
  }

  Future<T> _atomic<T>(FutureOr<T> Function() action) {
    final before = _tail;
    final release = Completer<void>();
    _tail = before.then((_) => release.future);
    return before.then((_) async {
      try {
        return await Future<T>.sync(action);
      } finally {
        release.complete();
      }
    });
  }
}

sealed class _ProjectionReceipt {
  const _ProjectionReceipt({
    required this.payloadDigest,
    required this.createdAt,
  });

  final String payloadDigest;
  final DateTime createdAt;
}

final class _ApplyReceipt extends _ProjectionReceipt {
  const _ApplyReceipt({
    required super.payloadDigest,
    required super.createdAt,
    required this.record,
  });

  final AuthScimApplicationProjectionRecord record;
}

final class _ReconciliationReceipt extends _ProjectionReceipt {
  const _ReconciliationReceipt({
    required super.payloadDigest,
    required super.createdAt,
    required this.result,
  });

  final AuthScimApplicationReconciliationResult result;
}

final class _ScopeDeletionReceipt extends _ProjectionReceipt {
  const _ScopeDeletionReceipt({
    required super.payloadDigest,
    required super.createdAt,
    required this.result,
  });

  final AuthScimApplicationProjectionScopeDeletionResult result;
}

int _compareSubject(
  AuthScimApplicationProjectionSubject left,
  AuthScimApplicationProjectionSubject right,
) {
  final kind = left.kind.name.compareTo(right.kind.name);
  if (kind != 0) return kind;
  return left.resourceId.compareTo(right.resourceId);
}

void _restore<K, V>(Map<K, V> target, Map<K, V> snapshot) {
  target
    ..clear()
    ..addAll(snapshot);
}

void _restoreSet<T>(Set<T> target, Set<T> snapshot) {
  target
    ..clear()
    ..addAll(snapshot);
}
