import 'dart:async';

import 'deletion_transaction.dart';
import 'tokens.dart' show hashOpaqueToken;

/// State of an RFC 8628 device authorization transaction.
enum AuthDeviceAuthorizationStatus {
  /// The user has not approved or denied the request.
  pending,

  /// The user approved the request and it may be exchanged once.
  approved,

  /// The user denied the request and it cannot be exchanged.
  denied,

  /// Token issuance completed and the request cannot be replayed.
  consumed,
}

/// Outcome of trying to acquire the bounded token-issuance lease.
enum AuthDeviceAuthorizationIssuanceLeaseStatus {
  /// A lease was acquired by the caller.
  acquired,

  /// Another unexpired lease currently owns the request.
  busy,

  /// The request, client binding, or lease inputs are not valid.
  invalid,
}

/// A persisted device authorization request.
///
/// Both the device code and user code are stored as digests. The raw values
/// exist only in the response that starts the flow and in the user-entered
/// approval request.
final class AuthDeviceAuthorization {
  /// Creates a persisted device authorization record.
  ///
  /// Code values must already be digests. Timestamps should be UTC and the
  /// status fields describe the single-use approval and issuance lifecycle.
  AuthDeviceAuthorization({
    required this.id,
    required this.deviceCodeHash,
    required this.userCodeHash,
    required this.clientId,
    required this.scopes,
    required this.createdAt,
    required this.expiresAt,
    required this.interval,
    this.status = AuthDeviceAuthorizationStatus.pending,
    this.userId,
    this.approvedAt,
    this.deniedAt,
    this.lastPolledAt,
    this.issuanceLeaseDigest,
    this.issuanceLeaseExpiresAt,
    this.consumedAt,
  });

  /// Durable identifier for this authorization transaction.
  final String id;

  /// Digest of the raw device code used for polling.
  final String deviceCodeHash;

  /// Digest of the user-entered verification code.
  final String userCodeHash;

  /// OAuth client bound to the request.
  final String clientId;

  /// Scopes requested by the client.
  final List<String> scopes;

  /// Time at which the request was created.
  final DateTime createdAt;

  /// Expiry deadline; polling and approval fail at or after this time.
  final DateTime expiresAt;

  /// Current minimum polling interval.
  final Duration interval;

  /// Approval and issuance state of the request.
  final AuthDeviceAuthorizationStatus status;

  /// User who approved the request, when approved.
  final String? userId;

  /// Time at which the request was approved.
  final DateTime? approvedAt;

  /// Time at which the request was denied.
  final DateTime? deniedAt;

  /// Time of the latest accepted poll.
  final DateTime? lastPolledAt;

  /// Digest identifying the active issuance lease, when present.
  final String? issuanceLeaseDigest;

  /// Expiry of the active issuance lease, bounded by [expiresAt].
  final DateTime? issuanceLeaseExpiresAt;

  /// Time at which token issuance consumed the request.
  final DateTime? consumedAt;

  /// Whether [now] is at or after [expiresAt].
  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

  /// Creates a copy with selected lifecycle fields replaced.
  ///
  /// Immutable identity, code digests, client, scopes, and timestamps are
  /// retained. Set [clearIssuanceLease] to remove both lease fields together.
  AuthDeviceAuthorization copyWith({
    AuthDeviceAuthorizationStatus? status,
    String? userId,
    DateTime? approvedAt,
    DateTime? deniedAt,
    DateTime? lastPolledAt,
    Duration? interval,
    String? issuanceLeaseDigest,
    DateTime? issuanceLeaseExpiresAt,
    DateTime? consumedAt,
    bool clearIssuanceLease = false,
  }) {
    return AuthDeviceAuthorization(
      id: id,
      deviceCodeHash: deviceCodeHash,
      userCodeHash: userCodeHash,
      clientId: clientId,
      scopes: scopes,
      createdAt: createdAt,
      expiresAt: expiresAt,
      interval: interval ?? this.interval,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      approvedAt: approvedAt ?? this.approvedAt,
      deniedAt: deniedAt ?? this.deniedAt,
      lastPolledAt: lastPolledAt ?? this.lastPolledAt,
      issuanceLeaseDigest: clearIssuanceLease
          ? null
          : issuanceLeaseDigest ?? this.issuanceLeaseDigest,
      issuanceLeaseExpiresAt: clearIssuanceLease
          ? null
          : issuanceLeaseExpiresAt ?? this.issuanceLeaseExpiresAt,
      consumedAt: consumedAt ?? this.consumedAt,
    );
  }

  /// Serializes only persistence-safe metadata. Raw codes are never included.
  Map<String, dynamic> toStorageJson() => <String, dynamic>{
    'id': id,
    'device_code_hash': deviceCodeHash,
    'user_code_hash': userCodeHash,
    'client_id': clientId,
    'scopes': scopes,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'interval_seconds': interval.inSeconds,
    'status': status.name,
    'user_id': userId,
    'approved_at': approvedAt?.toUtc().toIso8601String(),
    'denied_at': deniedAt?.toUtc().toIso8601String(),
    'last_polled_at': lastPolledAt?.toUtc().toIso8601String(),
    'issuance_lease_digest': issuanceLeaseDigest,
    'issuance_lease_expires_at': issuanceLeaseExpiresAt
        ?.toUtc()
        .toIso8601String(),
    'consumed_at': consumedAt?.toUtc().toIso8601String(),
  };
}

/// One secret-free, bounded claim on an approved authorization.
///
/// [leaseDigest] is a digest of a process-local random value. Neither the raw
/// lease value nor issued access or refresh tokens cross this store boundary.
final class AuthDeviceAuthorizationIssuanceLease {
  /// Creates a secret-free claim on an approved authorization.
  ///
  /// [expiresAt] is bounded by the authorization expiry and the lease policy.
  const AuthDeviceAuthorizationIssuanceLease({
    required this.authorization,
    required this.leaseDigest,
    required this.expiresAt,
  });

  /// Approved authorization held by this lease.
  final AuthDeviceAuthorization authorization;

  /// Store-side digest identifying the lease owner.
  final String leaseDigest;

  /// Deadline after which another caller may recover the lease.
  final DateTime expiresAt;
}

/// Result of attempting to acquire an issuance lease.
final class AuthDeviceAuthorizationIssuanceLeaseResult {
  /// Creates a result with [status] and an optional acquired [lease].
  const AuthDeviceAuthorizationIssuanceLeaseResult(this.status, [this.lease]);

  /// Whether the lease was acquired, busy, or invalid.
  final AuthDeviceAuthorizationIssuanceLeaseStatus status;

  /// Acquired lease, or null for busy and invalid results.
  final AuthDeviceAuthorizationIssuanceLease? lease;
}

/// Result of atomically polling a device authorization request.
enum AuthDeviceAuthorizationPollStatus {
  /// The request exists but has not been approved.
  pending,

  /// The request is approved and ready for issuance.
  approved,

  /// The user denied the request.
  denied,

  /// The request was already exchanged successfully.
  consumed,

  /// The request passed its expiry deadline.
  expired,

  /// The request was polled too early and its interval increased.
  slowDown,

  /// No matching device-code record exists.
  invalid,
}

/// Result of atomically polling a device authorization request.
final class AuthDeviceAuthorizationPollResult {
  /// Creates a poll result with [status] and optional [authorization].
  const AuthDeviceAuthorizationPollResult(this.status, [this.authorization]);

  /// Store outcome mapped by the plugin to an RFC 8628 response.
  final AuthDeviceAuthorizationPollStatus status;

  /// Matching record, when one exists; null for an invalid lookup.
  final AuthDeviceAuthorization? authorization;
}

/// Persistence boundary for RFC 8628 device authorization transactions.
abstract interface class AuthDeviceAuthorizationStore {
  /// Validates and creates [authorization], rejecting duplicate code digests.
  ///
  /// Returns the stored record. Implementations should reject invalid
  /// timestamps, blank identifiers, and non-positive intervals. An expiry in
  /// the past may still be stored if it is otherwise structurally valid.
  FutureOr<AuthDeviceAuthorization> create(
    AuthDeviceAuthorization authorization,
  );

  /// Atomically records a poll and enforces the current polling interval.
  ///
  /// Returns `pending`, `approved`, `denied`, `consumed`, `expired`, or
  /// `invalid`; an early poll returns `slowDown` and increases the interval.
  FutureOr<AuthDeviceAuthorizationPollResult> poll(
    String deviceCodeHash, {
    DateTime? now,
  });

  /// Atomically approves a pending request for [userId].
  ///
  /// Returns the transitioned record, or null when the user code is missing,
  /// expired, blank, or no longer pending.
  FutureOr<AuthDeviceAuthorization?> approve(
    String userCodeHash,
    String userId, {
    DateTime? now,
  });

  /// Atomically denies a pending request.
  ///
  /// Returns the transitioned record, or null when the user code is missing,
  /// expired, or no longer pending.
  FutureOr<AuthDeviceAuthorization?> deny(String userCodeHash, {DateTime? now});

  /// Atomically acquires a bounded issuance lease for an approved request.
  ///
  /// The request must belong to [clientId]. Returns `acquired` with a lease,
  /// `busy` while another unexpired lease owns it, or `invalid` for missing,
  /// expired, consumed, mismatched, or malformed inputs. Lease expiry must not
  /// exceed the authorization expiry.
  FutureOr<AuthDeviceAuthorizationIssuanceLeaseResult> beginIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    required DateTime leaseExpiresAt,
    DateTime? now,
  });

  /// Atomically consumes the request only when [leaseDigest] still owns it.
  ///
  /// Returns true only for an active lease bound to [clientId]; stale, expired,
  /// mismatched, or already terminal leases return false.
  FutureOr<bool> completeIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  });

  /// Releases only the matching lease after an issuer failure.
  ///
  /// Returns true when an approved record belongs to [clientId] and
  /// [leaseDigest]. Implementations may release a lease after its deadline;
  /// stale or mismatched owners return false.
  FutureOr<bool> releaseIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  });

  /// Deletes all device authorizations whose user ID matches [userId].
  ///
  /// Used by account deletion and access revocation; blank IDs should perform
  /// no deletion.
  FutureOr<void> deleteForUser(String userId);
}

/// In-memory device authorization store for tests and local development.
final class InMemoryAuthDeviceAuthorizationStore
    implements AuthDeviceAuthorizationStore, AuthInMemoryUserDeletionStore {
  /// Creates a bounded reference store for tests and local development.
  ///
  /// [maxEntries] must be positive; oldest insertion-order records are evicted
  /// when capacity is reached.
  InMemoryAuthDeviceAuthorizationStore({this.maxEntries = 1024})
    : assert(maxEntries > 0);

  /// Maximum number of unexpired records retained in memory.
  final int maxEntries;
  final Map<String, AuthDeviceAuthorization> _records =
      <String, AuthDeviceAuthorization>{};

  /// Captures a checkpoint for coordinated deletion rollback.
  @override
  Object captureDeletionState() =>
      Map<String, AuthDeviceAuthorization>.of(_records);

  /// Restores a checkpoint produced by [captureDeletionState].
  @override
  void restoreDeletionState(Object checkpoint) {
    final records = checkpoint as Map<String, AuthDeviceAuthorization>;
    _records
      ..clear()
      ..addAll(records);
  }

  /// Validates and stores a record, pruning expired entries first.
  ///
  /// Duplicate device or user-code digests throw [StateError]. At capacity,
  /// the oldest insertion-order record is evicted.
  @override
  Future<AuthDeviceAuthorization> create(
    AuthDeviceAuthorization authorization,
  ) async {
    _validate(authorization);
    _removeExpired(DateTime.now().toUtc());
    if (_records.containsKey(authorization.deviceCodeHash) ||
        _records.values.any(
          (record) => record.userCodeHash == authorization.userCodeHash,
        )) {
      throw StateError('Device authorization code already exists');
    }
    while (_records.length >= maxEntries) {
      _records.remove(_records.keys.first);
    }
    _records[authorization.deviceCodeHash] = authorization;
    return authorization;
  }

  /// Polls a record using UTC time and updates its last-poll timestamp.
  ///
  /// Polling before the current interval returns `slowDown` and adds five
  /// seconds to that interval. Terminal and expired states are returned
  /// without reopening the request.
  @override
  Future<AuthDeviceAuthorizationPollResult> poll(
    String deviceCodeHash, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final key = deviceCodeHash.trim();
    final existing = _records[key];
    if (existing == null) {
      return const AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.invalid,
      );
    }
    if (existing.isExpired(now: current)) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.expired,
        existing,
      );
    }
    if (existing.status == AuthDeviceAuthorizationStatus.denied) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.denied,
        existing,
      );
    }
    if (existing.status == AuthDeviceAuthorizationStatus.consumed) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.consumed,
        existing,
      );
    }
    final previousPoll = existing.lastPolledAt;
    if (previousPoll != null &&
        current.difference(previousPoll) < existing.interval) {
      final slowed = existing.copyWith(
        interval: existing.interval + const Duration(seconds: 5),
      );
      _records[key] = slowed;
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.slowDown,
        slowed,
      );
    }
    final updated = existing.copyWith(lastPolledAt: current);
    _records[key] = updated;
    return AuthDeviceAuthorizationPollResult(
      updated.status == AuthDeviceAuthorizationStatus.approved
          ? AuthDeviceAuthorizationPollStatus.approved
          : AuthDeviceAuthorizationPollStatus.pending,
      updated,
    );
  }

  /// Transitions one pending, unexpired record to approved.
  ///
  /// Approval is terminal with respect to the pending state and returns null
  /// for missing, expired, blank, or already transitioned records.
  @override
  Future<AuthDeviceAuthorization?> approve(
    String userCodeHash,
    String userId, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final key = userCodeHash.trim();
    final id = userId.trim();
    final entry = _findByUserCode(key);
    if (entry == null ||
        id.isEmpty ||
        entry.isExpired(now: current) ||
        entry.status != AuthDeviceAuthorizationStatus.pending) {
      return null;
    }
    final updated = entry.copyWith(
      status: AuthDeviceAuthorizationStatus.approved,
      userId: id,
      approvedAt: current,
    );
    _records[entry.deviceCodeHash] = updated;
    return updated;
  }

  /// Transitions one pending, unexpired record to denied.
  ///
  /// Denial is terminal and returns null when the code is missing, expired, or
  /// already transitioned.
  @override
  Future<AuthDeviceAuthorization?> deny(
    String userCodeHash, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final entry = _findByUserCode(userCodeHash.trim());
    if (entry == null ||
        entry.isExpired(now: current) ||
        entry.status != AuthDeviceAuthorizationStatus.pending) {
      return null;
    }
    final updated = entry.copyWith(
      status: AuthDeviceAuthorizationStatus.denied,
      deniedAt: current,
    );
    _records[entry.deviceCodeHash] = updated;
    return updated;
  }

  /// Acquires a client-bound lease for an approved record.
  ///
  /// An unexpired existing lease returns `busy`; an expired lease can be
  /// recovered. The requested expiry is bounded by the authorization expiry.
  @override
  Future<AuthDeviceAuthorizationIssuanceLeaseResult> beginIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    required DateTime leaseExpiresAt,
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final key = deviceCodeHash.trim();
    final client = clientId.trim();
    final digest = leaseDigest.trim();
    final requestedExpiry = leaseExpiresAt.toUtc();
    final entry = _records[key];
    if (entry == null ||
        entry.isExpired(now: current) ||
        entry.status != AuthDeviceAuthorizationStatus.approved ||
        entry.userId == null ||
        client.isEmpty ||
        entry.clientId != client ||
        digest.isEmpty ||
        !requestedExpiry.isAfter(current)) {
      return const AuthDeviceAuthorizationIssuanceLeaseResult(
        AuthDeviceAuthorizationIssuanceLeaseStatus.invalid,
      );
    }
    final activeLeaseExpiry = entry.issuanceLeaseExpiresAt?.toUtc();
    if (entry.issuanceLeaseDigest != null &&
        activeLeaseExpiry != null &&
        activeLeaseExpiry.isAfter(current)) {
      return const AuthDeviceAuthorizationIssuanceLeaseResult(
        AuthDeviceAuthorizationIssuanceLeaseStatus.busy,
      );
    }
    final boundedExpiry = requestedExpiry.isBefore(entry.expiresAt.toUtc())
        ? requestedExpiry
        : entry.expiresAt.toUtc();
    final leased = entry.copyWith(
      issuanceLeaseDigest: digest,
      issuanceLeaseExpiresAt: boundedExpiry,
    );
    _records[key] = leased;
    return AuthDeviceAuthorizationIssuanceLeaseResult(
      AuthDeviceAuthorizationIssuanceLeaseStatus.acquired,
      AuthDeviceAuthorizationIssuanceLease(
        authorization: leased,
        leaseDigest: digest,
        expiresAt: boundedExpiry,
      ),
    );
  }

  /// Marks a record consumed when the active lease owner completes issuance.
  ///
  /// Stale, expired, or mismatched lease owners return false.
  @override
  Future<bool> completeIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final key = deviceCodeHash.trim();
    final entry = _records[key];
    if (!_ownsActiveLease(entry, clientId, leaseDigest, current)) return false;
    _records[key] = entry!.copyWith(
      status: AuthDeviceAuthorizationStatus.consumed,
      consumedAt: current,
      clearIssuanceLease: true,
    );
    return true;
  }

  /// Clears an active lease after a failed token issuance.
  ///
  /// Only the matching client and lease digest can release it.
  @override
  Future<bool> releaseIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  }) async {
    final key = deviceCodeHash.trim();
    final entry = _records[key];
    if (entry == null ||
        entry.status != AuthDeviceAuthorizationStatus.approved ||
        entry.clientId != clientId.trim() ||
        entry.issuanceLeaseDigest != leaseDigest.trim()) {
      return false;
    }
    _records[key] = entry.copyWith(clearIssuanceLease: true);
    return true;
  }

  /// Removes all records whose approved user matches [userId].
  @override
  Future<void> deleteForUser(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    _records.removeWhere((_, value) => value.userId == id);
  }

  /// Adapts [deleteForUser] to the deletion coordinator contract.
  @override
  Future<void> deleteUserDataForDeletion(String userId) =>
      deleteForUser(userId);

  AuthDeviceAuthorization? _findByUserCode(String hash) {
    if (hash.isEmpty) return null;
    for (final record in _records.values) {
      if (record.userCodeHash == hash) return record;
    }
    return null;
  }

  void _removeExpired(DateTime now) {
    _records.removeWhere((_, value) => value.isExpired(now: now));
  }

  static bool _ownsActiveLease(
    AuthDeviceAuthorization? entry,
    String clientId,
    String leaseDigest,
    DateTime now,
  ) =>
      entry != null &&
      entry.status == AuthDeviceAuthorizationStatus.approved &&
      entry.clientId == clientId.trim() &&
      entry.issuanceLeaseDigest == leaseDigest.trim() &&
      entry.issuanceLeaseExpiresAt?.toUtc().isAfter(now) == true &&
      !entry.isExpired(now: now);
}

/// Builds the opaque digest stored for a raw device or user code.
///
/// Callers may pass the raw delivery or approval value; only the returned
/// digest should cross the [AuthDeviceAuthorizationStore] boundary.
String hashAuthDeviceAuthorizationCode(String code) => hashOpaqueToken(code);

/// Builds a digest for a process-local random issuance lease identity.
///
/// Store only the returned digest; the raw lease value is not a persistence
/// credential and is not returned by the store.
String hashAuthDeviceAuthorizationIssuanceLease(String lease) =>
    hashOpaqueToken(lease);

void _validate(AuthDeviceAuthorization authorization) {
  if (authorization.id.trim().isEmpty ||
      authorization.deviceCodeHash.trim().isEmpty ||
      authorization.userCodeHash.trim().isEmpty ||
      authorization.clientId.trim().isEmpty ||
      authorization.scopes.any((scope) => scope.trim().isEmpty) ||
      authorization.interval <= Duration.zero ||
      !authorization.expiresAt.toUtc().isAfter(
        authorization.createdAt.toUtc(),
      )) {
    throw ArgumentError('Invalid device authorization');
  }
  if (authorization.userId?.trim().isEmpty == true) {
    throw ArgumentError('Device authorization userId must not be empty');
  }
  final leaseDigest = authorization.issuanceLeaseDigest;
  final leaseExpiresAt = authorization.issuanceLeaseExpiresAt;
  if ((leaseDigest == null) != (leaseExpiresAt == null) ||
      leaseDigest?.trim().isEmpty == true ||
      leaseExpiresAt?.toUtc().isAfter(authorization.expiresAt.toUtc()) ==
          true) {
    throw ArgumentError('Invalid device authorization issuance lease');
  }
}
