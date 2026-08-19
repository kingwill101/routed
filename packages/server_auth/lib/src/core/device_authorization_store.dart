import 'dart:async';

import 'tokens.dart' show hashOpaqueToken;

/// State of an RFC 8628 device authorization transaction.
enum AuthDeviceAuthorizationStatus { pending, approved, denied, consumed }

/// A persisted device authorization request.
///
/// Both the device code and user code are stored as digests. The raw values
/// exist only in the response that starts the flow and in the user-entered
/// approval request.
final class AuthDeviceAuthorization {
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
  });

  final String id;
  final String deviceCodeHash;
  final String userCodeHash;
  final String clientId;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Duration interval;
  final AuthDeviceAuthorizationStatus status;
  final String? userId;
  final DateTime? approvedAt;
  final DateTime? deniedAt;
  final DateTime? lastPolledAt;

  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

  AuthDeviceAuthorization copyWith({
    AuthDeviceAuthorizationStatus? status,
    String? userId,
    DateTime? approvedAt,
    DateTime? deniedAt,
    DateTime? lastPolledAt,
    Duration? interval,
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
  };
}

/// Result of atomically polling a device authorization request.
enum AuthDeviceAuthorizationPollStatus {
  pending,
  approved,
  denied,
  consumed,
  expired,
  slowDown,
  invalid,
}

final class AuthDeviceAuthorizationPollResult {
  const AuthDeviceAuthorizationPollResult(this.status, [this.authorization]);

  final AuthDeviceAuthorizationPollStatus status;
  final AuthDeviceAuthorization? authorization;
}

/// Persistence boundary for RFC 8628 device authorization transactions.
abstract interface class AuthDeviceAuthorizationStore {
  /// Creates a request and rejects duplicate hashes.
  FutureOr<AuthDeviceAuthorization> create(
    AuthDeviceAuthorization authorization,
  );

  /// Atomically records a poll and enforces the current polling interval.
  FutureOr<AuthDeviceAuthorizationPollResult> poll(
    String deviceCodeHash, {
    DateTime? now,
  });

  /// Atomically approves a pending request for [userId].
  FutureOr<AuthDeviceAuthorization?> approve(
    String userCodeHash,
    String userId, {
    DateTime? now,
  });

  /// Atomically denies a pending request.
  FutureOr<AuthDeviceAuthorization?> deny(String userCodeHash, {DateTime? now});

  /// Claims an approved request exactly once for token issuance.
  FutureOr<AuthDeviceAuthorization?> claimApproved(
    String deviceCodeHash, {
    String? clientId,
    DateTime? now,
  });

  /// Deletes approvals owned by a user as part of account deletion.
  FutureOr<void> deleteForUser(String userId);
}

/// In-memory device authorization store for tests and local development.
final class InMemoryAuthDeviceAuthorizationStore
    implements AuthDeviceAuthorizationStore {
  InMemoryAuthDeviceAuthorizationStore({this.maxEntries = 1024})
    : assert(maxEntries > 0);

  final int maxEntries;
  final Map<String, AuthDeviceAuthorization> _records =
      <String, AuthDeviceAuthorization>{};

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

  @override
  Future<AuthDeviceAuthorization?> claimApproved(
    String deviceCodeHash, {
    String? clientId,
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final key = deviceCodeHash.trim();
    final entry = _records[key];
    if (entry == null ||
        entry.isExpired(now: current) ||
        entry.status != AuthDeviceAuthorizationStatus.approved ||
        entry.userId == null ||
        clientId != null && entry.clientId != clientId.trim()) {
      return null;
    }
    final claimed = entry.copyWith(
      status: AuthDeviceAuthorizationStatus.consumed,
    );
    _records[key] = claimed;
    return claimed;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    _records.removeWhere((_, value) => value.userId == id);
  }

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
}

/// Builds a digest suitable for [AuthDeviceAuthorizationStore].
String hashAuthDeviceAuthorizationCode(String code) => hashOpaqueToken(code);

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
}
