import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

/// Maximum authoritative subjects accepted by one full reconciliation.
const int authScimMaximumReconciliationSubjects = 1000;

/// Maximum projection or drift records returned by one page.
const int authScimMaximumProjectionPageSize = 200;

/// Snapshot identifier for an empty projection scope.
final String authScimEmptyApplicationProjectionSnapshotId = sha256
    .convert(const <int>[])
    .toString();

/// Immutable application projection boundary for one SCIM connection.
final class AuthScimApplicationProjectionScope {
  AuthScimApplicationProjectionScope({
    required String connectionId,
    required String tenantId,
    required String organizationId,
    required String provisioningDomainId,
  }) : connectionId = _identifier(connectionId, 'connectionId'),
       tenantId = _identifier(tenantId, 'tenantId'),
       organizationId = _identifier(organizationId, 'organizationId'),
       provisioningDomainId = _identifier(
         provisioningDomainId,
         'provisioningDomainId',
       );

  final String connectionId;
  final String tenantId;
  final String organizationId;
  final String provisioningDomainId;

  bool sameBindingAs(AuthScimApplicationProjectionScope other) =>
      connectionId == other.connectionId &&
      tenantId == other.tenantId &&
      organizationId == other.organizationId &&
      provisioningDomainId == other.provisioningDomainId;

  @override
  bool operator ==(Object other) =>
      other is AuthScimApplicationProjectionScope && sameBindingAs(other);

  @override
  int get hashCode =>
      Object.hash(connectionId, tenantId, organizationId, provisioningDomainId);
}

/// Directory resource kind represented by an application projection.
enum AuthScimApplicationSubjectKind { user, group }

/// Stable directory subject key used by application-owned projection state.
///
/// Mutable SCIM attributes such as `userName`, email, and display name are
/// deliberately absent. A subject is identified only by its immutable
/// connection binding and SCIM resource ID.
final class AuthScimApplicationProjectionSubject {
  AuthScimApplicationProjectionSubject({
    required this.scope,
    required String resourceId,
    required this.kind,
  }) : resourceId = _identifier(resourceId, 'resourceId');

  final AuthScimApplicationProjectionScope scope;
  final String resourceId;
  final AuthScimApplicationSubjectKind kind;

  @override
  bool operator ==(Object other) =>
      other is AuthScimApplicationProjectionSubject &&
      scope == other.scope &&
      resourceId == other.resourceId &&
      kind == other.kind;

  @override
  int get hashCode => Object.hash(scope, resourceId, kind);
}

/// Application-visible lifecycle derived from directory provisioning.
///
/// This state does not imply a sign-in method, an authentication role, or an
/// auth user. Applications authorize those concerns independently.
enum AuthScimApplicationProjectionState { active, disabled, tombstoned }

/// Versioned, digest-bound directory state safe for application projection.
///
/// [sourceDigest] is a lowercase SHA-256 digest of the application's canonical
/// projection input. Raw source attributes, bearer tokens, and credentials do
/// not belong in this record.
final class AuthScimApplicationProjectionSnapshot {
  AuthScimApplicationProjectionSnapshot({
    required this.subject,
    required String sourceVersion,
    required String sourceDigest,
    required this.state,
    Iterable<AuthScimApplicationProjectionSubject> members =
        const <AuthScimApplicationProjectionSubject>[],
  }) : sourceVersion = _identifier(sourceVersion, 'sourceVersion'),
       sourceDigest = _digest(sourceDigest, 'sourceDigest'),
       members = List<AuthScimApplicationProjectionSubject>.unmodifiable(
         members,
       ) {
    if (subject.kind == AuthScimApplicationSubjectKind.user &&
        this.members.isNotEmpty) {
      throw ArgumentError('A SCIM User projection cannot contain members.');
    }
    if (state == AuthScimApplicationProjectionState.tombstoned &&
        this.members.isNotEmpty) {
      throw ArgumentError('A tombstoned projection cannot contain members.');
    }
    if (this.members.length > authScimMaximumReconciliationSubjects) {
      throw ArgumentError('SCIM projection membership is too large.');
    }
    final unique = <AuthScimApplicationProjectionSubject>{};
    for (final member in this.members) {
      if (!subject.scope.sameBindingAs(member.scope)) {
        throw ArgumentError('SCIM projection members crossed a binding.');
      }
      if (!unique.add(member)) {
        throw ArgumentError('SCIM projection members must be unique.');
      }
      if (member == subject) {
        throw ArgumentError('A SCIM projection cannot contain itself.');
      }
    }
  }

  final AuthScimApplicationProjectionSubject subject;
  final String sourceVersion;
  final String sourceDigest;
  final AuthScimApplicationProjectionState state;
  final List<AuthScimApplicationProjectionSubject> members;

  bool sameSourceAs(AuthScimApplicationProjectionSnapshot other) =>
      subject == other.subject &&
      sourceVersion == other.sourceVersion &&
      sourceDigest == other.sourceDigest &&
      state == other.state &&
      _sameSubjects(members, other.members);
}

/// Durable application-owned projection record.
final class AuthScimApplicationProjectionRecord {
  AuthScimApplicationProjectionRecord({
    required this.snapshot,
    required this.version,
    required DateTime updatedAt,
  }) : updatedAt = updatedAt.toUtc() {
    if (version < 1) throw ArgumentError.value(version, 'version');
  }

  final AuthScimApplicationProjectionSnapshot snapshot;
  final int version;
  final DateTime updatedAt;

  AuthScimApplicationProjectionSubject get subject => snapshot.subject;
}

/// Explicit application projection mutation.
enum AuthScimApplicationProjectionMutation {
  create,
  update,
  disable,
  tombstone,
  groupMembershipChange,
}

/// Idempotent, version-bound application projection command.
final class AuthScimApplicationProjectionCommand {
  AuthScimApplicationProjectionCommand({
    required String operationId,
    required this.mutation,
    required this.desired,
    this.expectedVersion,
  }) : operationId = _identifier(operationId, 'operationId'),
       payloadDigest = _projectionCommandPayloadDigest(
         mutation,
         desired,
         expectedVersion,
       ) {
    if (mutation == AuthScimApplicationProjectionMutation.create) {
      if (expectedVersion != null) {
        throw ArgumentError('Create cannot bind an existing version.');
      }
    } else if (expectedVersion == null || expectedVersion! < 1) {
      throw ArgumentError('Projection mutation requires an expected version.');
    }
    switch (mutation) {
      case AuthScimApplicationProjectionMutation.create:
      case AuthScimApplicationProjectionMutation.update:
        if (desired.state == AuthScimApplicationProjectionState.tombstoned) {
          throw ArgumentError('Create/update cannot project a tombstone.');
        }
      case AuthScimApplicationProjectionMutation.disable:
        if (desired.subject.kind != AuthScimApplicationSubjectKind.user ||
            desired.state != AuthScimApplicationProjectionState.disabled) {
          throw ArgumentError('Disable requires a disabled User projection.');
        }
      case AuthScimApplicationProjectionMutation.tombstone:
        if (desired.state != AuthScimApplicationProjectionState.tombstoned) {
          throw ArgumentError('Tombstone requires tombstoned desired state.');
        }
      case AuthScimApplicationProjectionMutation.groupMembershipChange:
        if (desired.subject.kind != AuthScimApplicationSubjectKind.group ||
            desired.state != AuthScimApplicationProjectionState.active) {
          throw ArgumentError(
            'Membership changes require an active Group projection.',
          );
        }
    }
  }

  final String operationId;
  final String payloadDigest;
  final AuthScimApplicationProjectionMutation mutation;
  final AuthScimApplicationProjectionSnapshot desired;
  final int? expectedVersion;
}

enum AuthScimApplicationProjectionStatus {
  applied,
  replayed,
  replayMismatch,
  notFound,
  versionConflict,
  memberConflict,
  resourceTombstoned,
  scopeDeleted,
}

final class AuthScimApplicationProjectionResult {
  AuthScimApplicationProjectionResult({required this.status, this.record}) {
    final hasRecord = record != null;
    if ((status == AuthScimApplicationProjectionStatus.applied ||
            status == AuthScimApplicationProjectionStatus.replayed) !=
        hasRecord) {
      throw ArgumentError(
        'Only committed SCIM projection results may contain a record.',
      );
    }
  }

  final AuthScimApplicationProjectionStatus status;
  final AuthScimApplicationProjectionRecord? record;

  bool get committed =>
      status == AuthScimApplicationProjectionStatus.applied ||
      status == AuthScimApplicationProjectionStatus.replayed;

  bool get retryable =>
      status == AuthScimApplicationProjectionStatus.versionConflict;
}

/// Bounded query over one exact application projection scope.
final class AuthScimApplicationProjectionQuery {
  AuthScimApplicationProjectionQuery({
    required this.scope,
    this.offset = 0,
    this.limit = 100,
  }) {
    if (offset < 0 || offset > 1000000) {
      throw ArgumentError.value(offset, 'offset');
    }
    if (limit < 1 || limit > authScimMaximumProjectionPageSize) {
      throw ArgumentError.value(limit, 'limit');
    }
  }

  final AuthScimApplicationProjectionScope scope;
  final int offset;
  final int limit;
}

final class AuthScimApplicationProjectionPage {
  AuthScimApplicationProjectionPage({
    required this.scope,
    required Iterable<AuthScimApplicationProjectionRecord> records,
    required this.total,
    required String projectionSnapshotId,
  }) : records = List<AuthScimApplicationProjectionRecord>.unmodifiable(
         records,
       ),
       projectionSnapshotId = _digest(
         projectionSnapshotId,
         'projectionSnapshotId',
       ) {
    if (total < 0 || this.records.length > authScimMaximumProjectionPageSize) {
      throw ArgumentError('Invalid SCIM projection page.');
    }
    if (total < this.records.length ||
        this.records.any(
          (record) => !record.subject.scope.sameBindingAs(scope),
        )) {
      throw ArgumentError('SCIM projection page crossed its scope.');
    }
    if (this.records.map((record) => record.subject).toSet().length !=
        this.records.length) {
      throw ArgumentError('SCIM projection page contains duplicate subjects.');
    }
  }

  final AuthScimApplicationProjectionScope scope;
  final List<AuthScimApplicationProjectionRecord> records;
  final int total;
  final String projectionSnapshotId;
}

enum AuthScimApplicationProjectionDriftKind { missing, diverged, unexpected }

final class AuthScimApplicationProjectionDrift {
  AuthScimApplicationProjectionDrift({
    required this.kind,
    required this.subject,
    this.authoritative,
    this.current,
  }) {
    if (authoritative != null && authoritative!.subject != subject ||
        current != null && current!.subject != subject) {
      throw ArgumentError('SCIM drift records must share one subject.');
    }
    if (kind == AuthScimApplicationProjectionDriftKind.missing &&
        (authoritative == null || current != null)) {
      throw ArgumentError('Missing drift requires authoritative state only.');
    }
    if (kind == AuthScimApplicationProjectionDriftKind.unexpected &&
        (authoritative != null || current == null)) {
      throw ArgumentError('Unexpected drift requires current state only.');
    }
    if (kind == AuthScimApplicationProjectionDriftKind.diverged &&
        (authoritative == null || current == null)) {
      throw ArgumentError('Diverged drift requires both states.');
    }
  }

  final AuthScimApplicationProjectionDriftKind kind;
  final AuthScimApplicationProjectionSubject subject;
  final AuthScimApplicationProjectionSnapshot? authoritative;
  final AuthScimApplicationProjectionRecord? current;
}

/// Snapshot-bound, bounded drift query.
final class AuthScimApplicationProjectionDriftQuery {
  AuthScimApplicationProjectionDriftQuery({
    required this.scope,
    required String sourceSnapshotId,
    required Iterable<AuthScimApplicationProjectionSnapshot> authoritative,
    this.offset = 0,
    this.limit = 100,
  }) : sourceSnapshotId = _digest(sourceSnapshotId, 'sourceSnapshotId'),
       authoritative = List<AuthScimApplicationProjectionSnapshot>.unmodifiable(
         authoritative,
       ) {
    _validateAuthoritative(scope, this.authoritative);
    if (this.sourceSnapshotId !=
        authScimApplicationSourceSnapshotId(scope, this.authoritative)) {
      throw ArgumentError('SCIM source snapshot digest does not match input.');
    }
    if (offset < 0 || offset > 1000000) {
      throw ArgumentError.value(offset, 'offset');
    }
    if (limit < 1 || limit > authScimMaximumProjectionPageSize) {
      throw ArgumentError.value(limit, 'limit');
    }
  }

  final AuthScimApplicationProjectionScope scope;
  final String sourceSnapshotId;
  final List<AuthScimApplicationProjectionSnapshot> authoritative;
  final int offset;
  final int limit;
}

final class AuthScimApplicationProjectionDriftPage {
  AuthScimApplicationProjectionDriftPage({
    required this.scope,
    required Iterable<AuthScimApplicationProjectionDrift> findings,
    required this.total,
    required String projectionSnapshotId,
  }) : findings = List<AuthScimApplicationProjectionDrift>.unmodifiable(
         findings,
       ),
       projectionSnapshotId = _digest(
         projectionSnapshotId,
         'projectionSnapshotId',
       ) {
    if (total < 0 || this.findings.length > authScimMaximumProjectionPageSize) {
      throw ArgumentError('Invalid SCIM drift page.');
    }
    if (total < this.findings.length ||
        this.findings.any(
          (finding) => !finding.subject.scope.sameBindingAs(scope),
        )) {
      throw ArgumentError('SCIM drift page crossed its scope.');
    }
    if (this.findings.map((finding) => finding.subject).toSet().length !=
        this.findings.length) {
      throw ArgumentError('SCIM drift page contains duplicate subjects.');
    }
  }

  final AuthScimApplicationProjectionScope scope;
  final List<AuthScimApplicationProjectionDrift> findings;
  final int total;
  final String projectionSnapshotId;
}

/// Full, bounded application projection reconciliation command.
///
/// [authoritative] is complete for [scope]. Missing records are created,
/// divergent records are replaced, and records absent from this list are
/// tombstoned. A stale [expectedProjectionSnapshotId] must be rejected so a
/// caller can inspect drift and retry without overwriting concurrent work.
final class AuthScimApplicationReconciliationCommand {
  AuthScimApplicationReconciliationCommand({
    required String operationId,
    required this.scope,
    required String expectedProjectionSnapshotId,
    required Iterable<AuthScimApplicationProjectionSnapshot> authoritative,
  }) : operationId = _identifier(operationId, 'operationId'),
       expectedProjectionSnapshotId = _digest(
         expectedProjectionSnapshotId,
         'expectedProjectionSnapshotId',
       ),
       authoritative = List<AuthScimApplicationProjectionSnapshot>.unmodifiable(
         authoritative,
       ) {
    _validateAuthoritative(scope, this.authoritative);
    sourceSnapshotId = authScimApplicationSourceSnapshotId(
      scope,
      this.authoritative,
    );
    payloadDigest = _reconciliationPayloadDigest(
      scope,
      this.authoritative,
      this.expectedProjectionSnapshotId,
    );
  }

  final String operationId;
  late final String payloadDigest;
  final AuthScimApplicationProjectionScope scope;
  late final String sourceSnapshotId;
  final String expectedProjectionSnapshotId;
  final List<AuthScimApplicationProjectionSnapshot> authoritative;
}

enum AuthScimApplicationReconciliationStatus {
  applied,
  replayed,
  replayMismatch,
  staleProjectionSnapshot,
  tombstoneConflict,
  scopeDeleted,
}

final class AuthScimApplicationReconciliationResult {
  AuthScimApplicationReconciliationResult({
    required this.status,
    required String projectionSnapshotId,
    this.created = 0,
    this.updated = 0,
    this.tombstoned = 0,
  }) : projectionSnapshotId = _digest(
         projectionSnapshotId,
         'projectionSnapshotId',
       ) {
    if (created < 0 || updated < 0 || tombstoned < 0) {
      throw ArgumentError('SCIM reconciliation counts cannot be negative.');
    }
    if (!committed && (created != 0 || updated != 0 || tombstoned != 0)) {
      throw ArgumentError('An uncommitted reconciliation changed records.');
    }
  }

  final AuthScimApplicationReconciliationStatus status;
  final String projectionSnapshotId;
  final int created;
  final int updated;
  final int tombstoned;

  bool get committed =>
      status == AuthScimApplicationReconciliationStatus.applied ||
      status == AuthScimApplicationReconciliationStatus.replayed;

  bool get retryable =>
      status == AuthScimApplicationReconciliationStatus.staleProjectionSnapshot;
}

/// Final, idempotent cleanup command for one retired SCIM connection scope.
///
/// A successful deletion installs a durable fence. New projection or
/// reconciliation commands for the same scope must return `scopeDeleted`
/// rather than recreating state after connection deletion.
final class AuthScimApplicationProjectionScopeDeletionCommand {
  AuthScimApplicationProjectionScopeDeletionCommand({
    required String operationId,
    required this.scope,
    required String expectedProjectionSnapshotId,
  }) : operationId = _identifier(operationId, 'operationId'),
       expectedProjectionSnapshotId = _digest(
         expectedProjectionSnapshotId,
         'expectedProjectionSnapshotId',
       ) {
    payloadDigest = _scopeDeletionPayloadDigest(
      scope,
      this.expectedProjectionSnapshotId,
    );
  }

  final String operationId;
  late final String payloadDigest;
  final AuthScimApplicationProjectionScope scope;
  final String expectedProjectionSnapshotId;
}

enum AuthScimApplicationProjectionScopeDeletionStatus {
  applied,
  replayed,
  replayMismatch,
  staleProjectionSnapshot,
}

final class AuthScimApplicationProjectionScopeDeletionResult {
  AuthScimApplicationProjectionScopeDeletionResult({
    required this.status,
    required this.deleted,
  }) {
    if (deleted < 0) throw ArgumentError.value(deleted, 'deleted');
    if (status != AuthScimApplicationProjectionScopeDeletionStatus.applied &&
        status != AuthScimApplicationProjectionScopeDeletionStatus.replayed &&
        deleted != 0) {
      throw ArgumentError('An uncommitted scope deletion removed records.');
    }
  }

  final AuthScimApplicationProjectionScopeDeletionStatus status;
  final int deleted;

  bool get committed =>
      status == AuthScimApplicationProjectionScopeDeletionStatus.applied ||
      status == AuthScimApplicationProjectionScopeDeletionStatus.replayed;

  bool get retryable =>
      status ==
      AuthScimApplicationProjectionScopeDeletionStatus.staleProjectionSnapshot;
}

/// Application-owned SCIM identity projection and reconciliation capability.
///
/// Implementations persist projection records separately from auth users and
/// must not infer a link from email or `userName`. Applying directory state
/// never grants a sign-in method or authorization role. Idempotency receipts
/// persist only operation and payload digests and must be bounded by count and
/// retention. Unexpected backend errors must be reported internally and
/// exposed as generic failures without bearer or token material.
///
/// This capability is deliberately not a callback inside the provisioning
/// store. Applications coordinate it through a durable outbox or a backend
/// transaction they own. Routed does not claim atomicity across unrelated
/// directory and application stores.
abstract interface class AuthScimApplicationProjectionStore {
  FutureOr<AuthScimApplicationProjectionResult> apply(
    AuthScimApplicationProjectionCommand command,
  );

  FutureOr<AuthScimApplicationProjectionRecord?> find(
    AuthScimApplicationProjectionSubject subject,
  );

  FutureOr<AuthScimApplicationProjectionPage> list(
    AuthScimApplicationProjectionQuery query,
  );

  FutureOr<AuthScimApplicationProjectionDriftPage> detectDrift(
    AuthScimApplicationProjectionDriftQuery query,
  );

  FutureOr<AuthScimApplicationReconciliationResult> reconcile(
    AuthScimApplicationReconciliationCommand command,
  );

  /// Whether a final deletion fence exists for [scope].
  FutureOr<bool> isScopeDeleted(AuthScimApplicationProjectionScope scope);

  /// Removes all records for one retired connection and fences recreation.
  FutureOr<AuthScimApplicationProjectionScopeDeletionResult> deleteScope(
    AuthScimApplicationProjectionScopeDeletionCommand command,
  );
}

/// Computes the canonical digest for a complete authoritative source snapshot.
///
/// Only stable scope/resource identifiers, source digests and versions,
/// lifecycle state, and stable member identifiers are included. Email,
/// username, credentials, auth-user IDs, and authorization state are not part
/// of this boundary.
String authScimApplicationSourceSnapshotId(
  AuthScimApplicationProjectionScope scope,
  Iterable<AuthScimApplicationProjectionSnapshot> authoritative,
) {
  final values = List<AuthScimApplicationProjectionSnapshot>.unmodifiable(
    authoritative,
  );
  _validateAuthoritative(scope, values);
  if (values.isEmpty) return authScimEmptyApplicationProjectionSnapshotId;
  final canonical = values.toList()
    ..sort((left, right) => _compareSubjects(left.subject, right.subject));
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(<Object?>[
            for (final snapshot in canonical) _snapshotJson(snapshot),
          ]),
        ),
      )
      .toString();
}

void _validateAuthoritative(
  AuthScimApplicationProjectionScope scope,
  List<AuthScimApplicationProjectionSnapshot> authoritative,
) {
  if (authoritative.length > authScimMaximumReconciliationSubjects) {
    throw ArgumentError('SCIM reconciliation input is too large.');
  }
  final subjects = <AuthScimApplicationProjectionSubject>{};
  final bySubject =
      <
        AuthScimApplicationProjectionSubject,
        AuthScimApplicationProjectionSnapshot
      >{};
  for (final snapshot in authoritative) {
    if (!scope.sameBindingAs(snapshot.subject.scope)) {
      throw ArgumentError('SCIM reconciliation crossed a binding.');
    }
    if (!subjects.add(snapshot.subject)) {
      throw ArgumentError('SCIM reconciliation subjects must be unique.');
    }
    bySubject[snapshot.subject] = snapshot;
  }
  for (final snapshot in authoritative) {
    for (final member in snapshot.members) {
      final target = bySubject[member];
      if (target == null ||
          target.state == AuthScimApplicationProjectionState.tombstoned) {
        throw ArgumentError(
          'SCIM reconciliation contains a missing or tombstoned member.',
        );
      }
    }
  }
}

bool _sameSubjects(
  List<AuthScimApplicationProjectionSubject> left,
  List<AuthScimApplicationProjectionSubject> right,
) {
  if (left.length != right.length) return false;
  final remaining = right.toSet();
  return remaining.length == right.length && left.every(remaining.remove);
}

int _compareSubjects(
  AuthScimApplicationProjectionSubject left,
  AuthScimApplicationProjectionSubject right,
) {
  final kind = left.kind.name.compareTo(right.kind.name);
  if (kind != 0) return kind;
  return left.resourceId.compareTo(right.resourceId);
}

Map<String, Object?> _snapshotJson(
  AuthScimApplicationProjectionSnapshot snapshot,
) => <String, Object?>{
  'scope': <String, String>{
    'connectionId': snapshot.subject.scope.connectionId,
    'tenantId': snapshot.subject.scope.tenantId,
    'organizationId': snapshot.subject.scope.organizationId,
    'provisioningDomainId': snapshot.subject.scope.provisioningDomainId,
  },
  'resourceId': snapshot.subject.resourceId,
  'kind': snapshot.subject.kind.name,
  'sourceVersion': snapshot.sourceVersion,
  'sourceDigest': snapshot.sourceDigest,
  'state': snapshot.state.name,
  'members': <Object?>[
    for (final member in snapshot.members.toList()..sort(_compareSubjects))
      <String, String>{
        'resourceId': member.resourceId,
        'kind': member.kind.name,
      },
  ],
};

String _projectionCommandPayloadDigest(
  AuthScimApplicationProjectionMutation mutation,
  AuthScimApplicationProjectionSnapshot desired,
  int? expectedVersion,
) => _jsonDigest(<String, Object?>{
  'kind': 'projection',
  'mutation': mutation.name,
  'expectedVersion': expectedVersion,
  'desired': _snapshotJson(desired),
});

String _reconciliationPayloadDigest(
  AuthScimApplicationProjectionScope scope,
  Iterable<AuthScimApplicationProjectionSnapshot> authoritative,
  String expectedProjectionSnapshotId,
) {
  final snapshots = authoritative.toList()
    ..sort((left, right) => _compareSubjects(left.subject, right.subject));
  return _jsonDigest(<String, Object?>{
    'kind': 'reconciliation',
    'scope': _scopeJson(scope),
    'expectedProjectionSnapshotId': expectedProjectionSnapshotId,
    'authoritative': <Object?>[
      for (final snapshot in snapshots) _snapshotJson(snapshot),
    ],
  });
}

String _scopeDeletionPayloadDigest(
  AuthScimApplicationProjectionScope scope,
  String expectedProjectionSnapshotId,
) => _jsonDigest(<String, Object?>{
  'kind': 'scopeDeletion',
  'scope': _scopeJson(scope),
  'expectedProjectionSnapshotId': expectedProjectionSnapshotId,
});

Map<String, String> _scopeJson(AuthScimApplicationProjectionScope scope) =>
    <String, String>{
      'connectionId': scope.connectionId,
      'tenantId': scope.tenantId,
      'organizationId': scope.organizationId,
      'provisioningDomainId': scope.provisioningDomainId,
    };

String _jsonDigest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

String _identifier(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 256 ||
      normalized.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw ArgumentError('Invalid SCIM projection $name.');
  }
  return normalized;
}

String _digest(String value, String name) {
  final normalized = value.trim();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
    throw ArgumentError('Invalid SCIM projection $name.');
  }
  return normalized;
}
