import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart';

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'tokens.dart';

/// Stable ID for the built-in two-factor plugin.
const authTwoFactorPluginId = 'two_factor';

const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Protects TOTP secrets before they cross a persistence boundary.
///
/// Production applications should implement this with their key-management
/// system. The plugin never persists the raw secret directly; it only passes
/// the protected value to [AuthTwoFactorStore].
abstract interface class AuthTwoFactorSecretProtector {
  String protect(String secret);

  String reveal(String protectedSecret);
}

/// A deliberately explicit protector for tests and ephemeral examples.
///
/// Do not use this implementation for durable production storage.
final class PlaintextAuthTwoFactorSecretProtector
    implements AuthTwoFactorSecretProtector {
  const PlaintextAuthTwoFactorSecretProtector();

  @override
  String protect(String secret) => secret;

  @override
  String reveal(String protectedSecret) => protectedSecret;
}

/// Persisted two-factor state for one user.
///
/// [protectedSecret] is opaque to the persistence adapter and must contain
/// the output of the configured [AuthTwoFactorSecretProtector]. Recovery codes
/// are stored as digests and are removed atomically when consumed.
class AuthTwoFactorRecord {
  AuthTwoFactorRecord({
    required this.userId,
    required this.protectedSecret,
    required this.enrollmentExpiresAt,
    this.verified = false,
    this.recoveryCodeHashes = const <String>[],
    this.failedVerificationCount = 0,
    this.lockedUntil,
    this.updatedAt,
  }) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    if (protectedSecret.trim().isEmpty) {
      throw ArgumentError.value(
        protectedSecret,
        'protectedSecret',
        'must not be empty',
      );
    }
    if (failedVerificationCount < 0) {
      throw ArgumentError.value(
        failedVerificationCount,
        'failedVerificationCount',
        'must not be negative',
      );
    }
  }

  /// User owning this factor.
  final String userId;

  /// Protected TOTP secret, never a raw secret in durable storage.
  final String protectedSecret;

  /// Expiry for an unverified enrollment.
  final DateTime enrollmentExpiresAt;

  /// Whether the enrollment has been verified and activated.
  final bool verified;

  /// Digests of unused recovery codes.
  final List<String> recoveryCodeHashes;

  /// Consecutive failed TOTP attempts.
  final int failedVerificationCount;

  /// Temporary lockout expiry after repeated invalid codes.
  final DateTime? lockedUntil;

  /// Last persistence update time.
  final DateTime? updatedAt;

  /// Creates a changed persistence record.
  AuthTwoFactorRecord copyWith({
    String? protectedSecret,
    DateTime? enrollmentExpiresAt,
    bool? verified,
    List<String>? recoveryCodeHashes,
    int? failedVerificationCount,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
    DateTime? updatedAt,
  }) {
    return AuthTwoFactorRecord(
      userId: userId,
      protectedSecret: protectedSecret ?? this.protectedSecret,
      enrollmentExpiresAt: enrollmentExpiresAt ?? this.enrollmentExpiresAt,
      verified: verified ?? this.verified,
      recoveryCodeHashes: recoveryCodeHashes ?? this.recoveryCodeHashes,
      failedVerificationCount:
          failedVerificationCount ?? this.failedVerificationCount,
      lockedUntil: clearLockedUntil ? null : lockedUntil ?? this.lockedUntil,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Typed persistence contract owned by the two-factor plugin.
abstract interface class AuthTwoFactorStore {
  FutureOr<AuthTwoFactorRecord?> findByUserId(String userId);

  /// Creates or replaces the factor record for [record].
  FutureOr<AuthTwoFactorRecord> save(AuthTwoFactorRecord record);

  /// Replaces [expected] with [replacement] only when the stored record is
  /// unchanged. Durable implementations must perform this comparison and
  /// write atomically, for example with a conditional update in a transaction.
  FutureOr<bool> saveIfCurrent(
    AuthTwoFactorRecord expected,
    AuthTwoFactorRecord replacement,
  );

  FutureOr<void> delete(String userId);

  /// Consumes one matching recovery-code digest atomically and clears a
  /// temporary verification lockout.
  ///
  /// [now] must be checked inside the same transaction as the lookup and
  /// removal. Durable implementations must reject a matching code while the
  /// factor is locked, so a concurrent invalid attempt cannot race a valid
  /// recovery attempt past the lockout boundary.
  FutureOr<bool> consumeRecoveryCode(
    String userId,
    String codeHash, {
    required DateTime now,
  });

  /// Atomically records a failed verification and applies lockout policy.
  FutureOr<AuthTwoFactorRecord?> recordFailedVerification(
    String userId, {
    required DateTime now,
    required int maxAttempts,
    required Duration lockoutDuration,
  });

  /// Atomically clears failed verification state after a successful code.
  FutureOr<AuthTwoFactorRecord?> clearVerificationFailures(
    String userId, {
    required DateTime now,
  });
}

/// In-memory two-factor store for tests and local examples.
final class InMemoryAuthTwoFactorStore
    implements AuthTwoFactorStore, AuthInMemoryTransactionParticipant {
  final Map<String, AuthTwoFactorRecord> _records =
      <String, AuthTwoFactorRecord>{};

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, AuthTwoFactorRecord>.of(_records);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
    final records = checkpoint as Map<String, AuthTwoFactorRecord>;
    _records
      ..clear()
      ..addAll(records);
  }

  @override
  AuthTwoFactorRecord? findByUserId(String userId) => _records[userId];

  @override
  AuthTwoFactorRecord save(AuthTwoFactorRecord record) {
    _records[record.userId] = record;
    return record;
  }

  @override
  bool saveIfCurrent(
    AuthTwoFactorRecord expected,
    AuthTwoFactorRecord replacement,
  ) {
    final current = _records[expected.userId];
    if (current == null || !_sameRecord(current, expected)) return false;
    _records[expected.userId] = replacement;
    return true;
  }

  @override
  void delete(String userId) {
    _records.remove(userId);
  }

  @override
  bool consumeRecoveryCode(
    String userId,
    String codeHash, {
    required DateTime now,
  }) {
    final record = _records[userId];
    final current = now.toUtc();
    if (record == null ||
        !record.verified ||
        (record.lockedUntil != null &&
            current.isBefore(record.lockedUntil!.toUtc()))) {
      return false;
    }
    final remaining = List<String>.from(record.recoveryCodeHashes);
    final index = remaining.indexWhere(
      (candidate) => constantTimeStringEquals(candidate, codeHash),
    );
    if (index < 0) return false;
    remaining.removeAt(index);
    _records[userId] = record.copyWith(
      recoveryCodeHashes: List<String>.unmodifiable(remaining),
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: current,
    );
    return true;
  }

  @override
  AuthTwoFactorRecord? recordFailedVerification(
    String userId, {
    required DateTime now,
    required int maxAttempts,
    required Duration lockoutDuration,
  }) {
    final record = _records[userId];
    if (record == null) return null;
    final failures = record.failedVerificationCount + 1;
    final updated = record.copyWith(
      failedVerificationCount: failures,
      lockedUntil: failures >= maxAttempts
          ? now.toUtc().add(lockoutDuration)
          : record.lockedUntil,
      updatedAt: now.toUtc(),
    );
    _records[userId] = updated;
    return updated;
  }

  @override
  AuthTwoFactorRecord? clearVerificationFailures(
    String userId, {
    required DateTime now,
  }) {
    final record = _records[userId];
    if (record == null) return null;
    final updated = record.copyWith(
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: now.toUtc(),
    );
    _records[userId] = updated;
    return updated;
  }
}

bool _sameRecord(AuthTwoFactorRecord left, AuthTwoFactorRecord right) {
  if (left.userId != right.userId ||
      left.protectedSecret != right.protectedSecret ||
      left.enrollmentExpiresAt != right.enrollmentExpiresAt ||
      left.verified != right.verified ||
      left.failedVerificationCount != right.failedVerificationCount ||
      left.lockedUntil != right.lockedUntil ||
      left.updatedAt != right.updatedAt ||
      left.recoveryCodeHashes.length != right.recoveryCodeHashes.length) {
    return false;
  }
  for (var index = 0; index < left.recoveryCodeHashes.length; index++) {
    if (left.recoveryCodeHashes[index] != right.recoveryCodeHashes[index]) {
      return false;
    }
  }
  return true;
}

/// Data returned when a user starts TOTP enrollment.
class AuthTwoFactorEnrollment {
  const AuthTwoFactorEnrollment({
    required this.secret,
    required this.otpauthUri,
    required this.expiresAt,
  });

  /// Base32 secret for the authenticator application.
  final String secret;

  /// URI suitable for a QR code or authenticator import.
  final Uri otpauthUri;

  /// Time after which the enrollment must be restarted.
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'secret': secret,
    'otpauthUri': otpauthUri.toString(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

/// Recovery codes returned after verified enrollment or explicit regeneration.
class AuthTwoFactorRecoveryCodes {
  const AuthTwoFactorRecoveryCodes(this.codes);

  /// One-time codes. Applications must show these once and encourage secure
  /// offline storage; the plugin does not persist the plaintext values.
  final List<String> codes;

  Map<String, dynamic> toJson() => {'recoveryCodes': codes};
}

/// A short-lived pending sign-in challenge returned to a client.
class AuthTwoFactorSignInChallenge {
  const AuthTwoFactorSignInChallenge({
    required this.token,
    required this.expiresAt,
  });

  /// Opaque challenge token that must be returned to the verification route.
  final String token;

  /// Time after which the challenge cannot be completed.
  final DateTime expiresAt;
}

/// Atomic result of a pending-challenge verification attempt.
class AuthTwoFactorChallengeAttempt {
  const AuthTwoFactorChallengeAttempt({
    required this.accepted,
    required this.locked,
    required this.expired,
  });

  final bool accepted;
  final bool locked;
  final bool expired;
}

/// A short-lived trusted-device token returned only after TOTP verification.
class AuthTwoFactorTrustedDeviceToken {
  const AuthTwoFactorTrustedDeviceToken({
    required this.token,
    required this.expiresAt,
  });

  /// Opaque bearer value intended for an HTTP-only cookie.
  final String token;

  /// Time after which the device must complete TOTP again.
  final DateTime expiresAt;
}

/// Persisted state for one trusted device.
class AuthTwoFactorTrustedDeviceRecord {
  AuthTwoFactorTrustedDeviceRecord({
    required this.id,
    required this.userId,
    required this.tokenHash,
    required this.createdAt,
    required this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    if (tokenHash.trim().isEmpty) {
      throw ArgumentError.value(tokenHash, 'tokenHash', 'must not be empty');
    }
    if (!expiresAt.isAfter(createdAt)) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'must be after createdAt',
      );
    }
  }

  final String id;
  final String userId;
  final String tokenHash;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  bool isActive({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return revokedAt == null && current.isBefore(expiresAt.toUtc());
  }

  AuthTwoFactorTrustedDeviceRecord copyWith({
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) {
    return AuthTwoFactorTrustedDeviceRecord(
      id: id,
      userId: userId,
      tokenHash: tokenHash,
      createdAt: createdAt,
      expiresAt: expiresAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      revokedAt: revokedAt ?? this.revokedAt,
    );
  }
}

/// Persistence contract for expiring trusted two-factor devices.
abstract interface class AuthTwoFactorTrustedDeviceStore {
  /// Finds and marks a matching, unexpired device as used atomically.
  FutureOr<AuthTwoFactorTrustedDeviceRecord?> findActive(
    String userId,
    String tokenHash, {
    required DateTime now,
  });

  FutureOr<AuthTwoFactorTrustedDeviceRecord> create(
    AuthTwoFactorTrustedDeviceRecord record,
  );

  /// Revokes all trusted devices belonging to [userId].
  FutureOr<void> revokeAll(String userId, {required DateTime now});
}

/// In-memory trusted-device store for tests and local examples.
final class InMemoryAuthTwoFactorTrustedDeviceStore
    implements
        AuthTwoFactorTrustedDeviceStore,
        AuthInMemoryTransactionParticipant {
  InMemoryAuthTwoFactorTrustedDeviceStore({
    DateTime Function()? clock,
    this.maxEntries = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final Map<String, AuthTwoFactorTrustedDeviceRecord> _records =
      <String, AuthTwoFactorTrustedDeviceRecord>{};
  final DateTime Function() _clock;

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, AuthTwoFactorTrustedDeviceRecord>.of(_records);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
    final records = checkpoint as Map<String, AuthTwoFactorTrustedDeviceRecord>;
    _records
      ..clear()
      ..addAll(records);
  }

  /// Maximum number of trusted-device records retained by this local store.
  ///
  /// Expired and revoked records are removed on writes and lookups. If the
  /// store is full, the oldest record is evicted. Durable stores should
  /// enforce equivalent expiry and capacity policies in persistence.
  final int maxEntries;

  @override
  AuthTwoFactorTrustedDeviceRecord? findActive(
    String userId,
    String tokenHash, {
    required DateTime now,
  }) {
    _removeInactive(now.toUtc());
    final record = _records[tokenHash];
    if (record == null ||
        record.userId != userId ||
        !record.isActive(now: now)) {
      return null;
    }
    final updated = record.copyWith(lastUsedAt: now.toUtc());
    _records[tokenHash] = updated;
    return updated;
  }

  @override
  AuthTwoFactorTrustedDeviceRecord create(
    AuthTwoFactorTrustedDeviceRecord record,
  ) {
    final now = _clock().toUtc();
    _removeInactive(now);
    _records.remove(record.tokenHash);
    while (_records.length >= maxEntries) {
      _removeOldest();
    }
    _records[record.tokenHash] = record;
    return record;
  }

  @override
  void revokeAll(String userId, {required DateTime now}) {
    final revokedAt = now.toUtc();
    for (final entry in _records.entries.toList()) {
      if (entry.value.userId == userId && entry.value.revokedAt == null) {
        _records[entry.key] = entry.value.copyWith(revokedAt: revokedAt);
      }
    }
  }

  void _removeInactive(DateTime now) {
    _records.removeWhere((_, record) => !record.isActive(now: now));
  }

  void _removeOldest() {
    if (_records.isEmpty) return;
    final oldest = _records.entries.reduce(
      (left, right) =>
          left.value.createdAt.isAfter(right.value.createdAt) ? right : left,
    );
    _records.remove(oldest.key);
  }
}

/// Result of completing a pending sign-in challenge.
class AuthTwoFactorSignInCompletion {
  const AuthTwoFactorSignInCompletion({
    required this.userId,
    this.user,
    this.providerId,
    this.credentials,
    this.trustedDevice,
  });

  final String userId;
  final AuthUser? user;
  final String? providerId;
  final AuthCredentials? credentials;
  final AuthTwoFactorTrustedDeviceToken? trustedDevice;
}

/// Persisted state for a pending two-factor sign-in.
class AuthTwoFactorChallengeRecord {
  AuthTwoFactorChallengeRecord({
    required this.id,
    required this.tokenHash,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
    this.user,
    this.providerId,
    this.credentials,
    this.failedVerificationCount = 0,
    this.lockedUntil,
    this.completedAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (tokenHash.trim().isEmpty) {
      throw ArgumentError.value(tokenHash, 'tokenHash', 'must not be empty');
    }
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    if (!expiresAt.isAfter(createdAt)) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'must be after createdAt',
      );
    }
    if (failedVerificationCount < 0) {
      throw ArgumentError.value(
        failedVerificationCount,
        'failedVerificationCount',
        'must not be negative',
      );
    }
  }

  final String id;
  final String tokenHash;
  final String userId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final AuthUser? user;
  final String? providerId;
  final AuthCredentials? credentials;
  final int failedVerificationCount;
  final DateTime? lockedUntil;
  final DateTime? completedAt;

  bool isActive({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return completedAt == null && current.isBefore(expiresAt.toUtc());
  }

  AuthTwoFactorChallengeRecord copyWith({
    int? failedVerificationCount,
    DateTime? lockedUntil,
    DateTime? completedAt,
  }) {
    return AuthTwoFactorChallengeRecord(
      id: id,
      tokenHash: tokenHash,
      userId: userId,
      createdAt: createdAt,
      expiresAt: expiresAt,
      user: user,
      providerId: providerId,
      credentials: credentials,
      failedVerificationCount:
          failedVerificationCount ?? this.failedVerificationCount,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Typed persistence contract for pending two-factor sign-ins.
abstract interface class AuthTwoFactorChallengeStore {
  FutureOr<AuthTwoFactorChallengeRecord?> findByTokenHash(String tokenHash);

  FutureOr<AuthTwoFactorChallengeRecord> create(
    AuthTwoFactorChallengeRecord record,
  );

  /// Records a valid or invalid code attempt atomically.
  FutureOr<AuthTwoFactorChallengeAttempt> recordAttempt(
    String tokenHash, {
    required DateTime now,
    required bool valid,
    required int maxAttempts,
    required Duration lockoutDuration,
  });
}

/// In-memory pending-challenge store for tests and local examples.
final class InMemoryAuthTwoFactorChallengeStore
    implements AuthTwoFactorChallengeStore, AuthInMemoryTransactionParticipant {
  InMemoryAuthTwoFactorChallengeStore({
    DateTime Function()? clock,
    this.maxEntries = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final Map<String, AuthTwoFactorChallengeRecord> _records =
      <String, AuthTwoFactorChallengeRecord>{};
  final DateTime Function() _clock;

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, AuthTwoFactorChallengeRecord>.of(_records);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
    final records = checkpoint as Map<String, AuthTwoFactorChallengeRecord>;
    _records
      ..clear()
      ..addAll(records);
  }

  /// Maximum number of pending challenges retained by this local store.
  ///
  /// Expired and completed challenges are removed on writes and lookups. If
  /// the store is full, the oldest pending challenge is evicted. Durable
  /// stores should enforce equivalent expiry and capacity policies.
  final int maxEntries;

  @override
  AuthTwoFactorChallengeRecord? findByTokenHash(String tokenHash) {
    _removeInactive(_clock().toUtc());
    return _records[tokenHash];
  }

  @override
  AuthTwoFactorChallengeRecord create(AuthTwoFactorChallengeRecord record) {
    final now = _clock().toUtc();
    _removeInactive(now);
    _records.remove(record.tokenHash);
    while (_records.length >= maxEntries) {
      _removeOldest();
    }
    _records[record.tokenHash] = record;
    return record;
  }

  @override
  AuthTwoFactorChallengeAttempt recordAttempt(
    String tokenHash, {
    required DateTime now,
    required bool valid,
    required int maxAttempts,
    required Duration lockoutDuration,
  }) {
    final current = now.toUtc();
    _removeInactive(current);
    final record = _records[tokenHash];
    if (record == null || !record.isActive(now: current)) {
      return const AuthTwoFactorChallengeAttempt(
        accepted: false,
        locked: false,
        expired: true,
      );
    }
    if (record.lockedUntil != null &&
        current.isBefore(record.lockedUntil!.toUtc())) {
      return const AuthTwoFactorChallengeAttempt(
        accepted: false,
        locked: true,
        expired: false,
      );
    }
    if (valid) {
      _records[tokenHash] = record.copyWith(completedAt: current);
      return const AuthTwoFactorChallengeAttempt(
        accepted: true,
        locked: false,
        expired: false,
      );
    }
    final failures = record.failedVerificationCount + 1;
    _records[tokenHash] = record.copyWith(
      failedVerificationCount: failures,
      lockedUntil: failures >= maxAttempts
          ? current.add(lockoutDuration)
          : record.lockedUntil,
    );
    return AuthTwoFactorChallengeAttempt(
      accepted: false,
      locked: failures >= maxAttempts,
      expired: false,
    );
  }

  void _removeInactive(DateTime now) {
    _records.removeWhere((_, record) => !record.isActive(now: now));
  }

  void _removeOldest() {
    if (_records.isEmpty) return;
    final oldest = _records.entries.reduce(
      (left, right) =>
          left.value.createdAt.isAfter(right.value.createdAt) ? right : left,
    );
    _records.remove(oldest.key);
  }
}

/// Result of atomically completing a pending sign-in with a recovery code.
class AuthTwoFactorPendingRecoveryAttempt {
  const AuthTwoFactorPendingRecoveryAttempt({
    required this.accepted,
    required this.locked,
    required this.expired,
    this.userId,
  });

  final bool accepted;
  final bool locked;
  final bool expired;
  final String? userId;
}

/// Transaction boundary for pending recovery-code sign-ins.
///
/// Implementations must atomically consume the recovery-code digest and mark
/// the matching pending challenge complete. A database-backed implementation
/// should perform both changes in one transaction; composing two independent
/// network or database writes is not sufficient.
abstract interface class AuthTwoFactorPendingRecoveryStore {
  FutureOr<AuthTwoFactorPendingRecoveryAttempt> recordRecoveryAttempt(
    String tokenHash, {
    required String recoveryCodeHash,
    required DateTime now,
    required int maxAttempts,
    required Duration lockoutDuration,
  });
}

/// In-memory atomic pending-recovery store for tests and local examples.
///
/// Pass the same in-memory factor and challenge stores to this coordinator;
/// its operation performs all state changes synchronously in one isolate turn.
final class InMemoryAuthTwoFactorPendingRecoveryStore
    implements AuthTwoFactorPendingRecoveryStore {
  const InMemoryAuthTwoFactorPendingRecoveryStore({
    required this.factorStore,
    required this.challengeStore,
  });

  final InMemoryAuthTwoFactorStore factorStore;
  final InMemoryAuthTwoFactorChallengeStore challengeStore;

  @override
  AuthTwoFactorPendingRecoveryAttempt recordRecoveryAttempt(
    String tokenHash, {
    required String recoveryCodeHash,
    required DateTime now,
    required int maxAttempts,
    required Duration lockoutDuration,
  }) {
    final current = now.toUtc();
    final challenge = challengeStore._records[tokenHash];
    if (challenge == null || !challenge.isActive(now: current)) {
      return const AuthTwoFactorPendingRecoveryAttempt(
        accepted: false,
        locked: false,
        expired: true,
      );
    }
    if (challenge.lockedUntil != null &&
        current.isBefore(challenge.lockedUntil!.toUtc())) {
      return AuthTwoFactorPendingRecoveryAttempt(
        accepted: false,
        locked: true,
        expired: false,
        userId: challenge.userId,
      );
    }
    final factor = factorStore._records[challenge.userId];
    if (factor == null || !factor.verified) {
      return const AuthTwoFactorPendingRecoveryAttempt(
        accepted: false,
        locked: false,
        expired: true,
      );
    }
    if (factor.lockedUntil != null &&
        current.isBefore(factor.lockedUntil!.toUtc())) {
      return AuthTwoFactorPendingRecoveryAttempt(
        accepted: false,
        locked: true,
        expired: false,
        userId: challenge.userId,
      );
    }

    final remaining = List<String>.from(factor.recoveryCodeHashes);
    final recoveryIndex = remaining.indexWhere(
      (candidate) => constantTimeStringEquals(candidate, recoveryCodeHash),
    );
    if (recoveryIndex < 0) {
      final failures = challenge.failedVerificationCount + 1;
      final lockedUntil = failures >= maxAttempts
          ? current.add(lockoutDuration)
          : challenge.lockedUntil;
      challengeStore._records[tokenHash] = challenge.copyWith(
        failedVerificationCount: failures,
        lockedUntil: lockedUntil,
      );
      final factorFailures = factor.failedVerificationCount + 1;
      factorStore._records[challenge.userId] = factor.copyWith(
        failedVerificationCount: factorFailures,
        lockedUntil: factorFailures >= maxAttempts
            ? current.add(lockoutDuration)
            : factor.lockedUntil,
        updatedAt: current,
      );
      return AuthTwoFactorPendingRecoveryAttempt(
        accepted: false,
        locked: failures >= maxAttempts || factorFailures >= maxAttempts,
        expired: false,
        userId: challenge.userId,
      );
    }

    remaining.removeAt(recoveryIndex);
    factorStore._records[challenge.userId] = factor.copyWith(
      recoveryCodeHashes: List<String>.unmodifiable(remaining),
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: current,
    );
    challengeStore._records[tokenHash] = challenge.copyWith(
      completedAt: current,
    );
    return AuthTwoFactorPendingRecoveryAttempt(
      accepted: true,
      locked: false,
      expired: false,
      userId: challenge.userId,
    );
  }
}

/// A short-lived proof that a user recently completed TOTP verification.
class AuthTwoFactorStepUpToken {
  const AuthTwoFactorStepUpToken({
    required this.token,
    required this.expiresAt,
  });

  /// Opaque proof value intended for an HTTP-only cookie.
  final String token;

  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'verified': true,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

/// Persisted state for a recent step-up proof.
class AuthTwoFactorStepUpRecord {
  AuthTwoFactorStepUpRecord({
    required this.id,
    required this.userId,
    required this.sessionBindingHash,
    required this.tokenHash,
    required this.createdAt,
    required this.expiresAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    if (sessionBindingHash.trim().isEmpty) {
      throw ArgumentError.value(
        sessionBindingHash,
        'sessionBindingHash',
        'must not be empty',
      );
    }
    if (tokenHash.trim().isEmpty) {
      throw ArgumentError.value(tokenHash, 'tokenHash', 'must not be empty');
    }
    if (!expiresAt.isAfter(createdAt)) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'must be after createdAt',
      );
    }
  }

  final String id;
  final String userId;
  final String sessionBindingHash;
  final String tokenHash;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isActive({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return current.isBefore(expiresAt.toUtc());
  }
}

/// Persistence contract for short-lived step-up proofs.
abstract interface class AuthTwoFactorStepUpStore {
  FutureOr<AuthTwoFactorStepUpRecord> create(AuthTwoFactorStepUpRecord record);

  FutureOr<AuthTwoFactorStepUpRecord?> findActive(
    String userId,
    String sessionBindingHash,
    String tokenHash, {
    required DateTime now,
  });

  FutureOr<void> revokeAll(String userId, String sessionBindingHash);

  /// Revokes every proof issued for [userId], regardless of session binding.
  FutureOr<void> revokeAllForUser(String userId);
}

/// In-memory step-up store for tests and local examples.
final class InMemoryAuthTwoFactorStepUpStore
    implements AuthTwoFactorStepUpStore, AuthInMemoryTransactionParticipant {
  InMemoryAuthTwoFactorStepUpStore({
    DateTime Function()? clock,
    this.maxEntries = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final Map<String, AuthTwoFactorStepUpRecord> _records =
      <String, AuthTwoFactorStepUpRecord>{};
  final DateTime Function() _clock;

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, AuthTwoFactorStepUpRecord>.of(_records);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
    final records = checkpoint as Map<String, AuthTwoFactorStepUpRecord>;
    _records
      ..clear()
      ..addAll(records);
  }

  /// Maximum number of step-up proofs retained by this local store.
  ///
  /// Expired proofs are removed on writes and lookups. If the store is full,
  /// the oldest proof is evicted. Durable stores should enforce equivalent
  /// expiry and capacity policies.
  final int maxEntries;

  @override
  AuthTwoFactorStepUpRecord create(AuthTwoFactorStepUpRecord record) {
    final now = _clock().toUtc();
    _removeExpired(now);
    _records.remove(record.tokenHash);
    while (_records.length >= maxEntries) {
      _removeOldest();
    }
    _records[record.tokenHash] = record;
    return record;
  }

  @override
  AuthTwoFactorStepUpRecord? findActive(
    String userId,
    String sessionBindingHash,
    String tokenHash, {
    required DateTime now,
  }) {
    final current = now.toUtc();
    _removeExpired(current);
    final record = _records[tokenHash];
    if (record == null ||
        record.userId != userId ||
        record.sessionBindingHash != sessionBindingHash ||
        !record.isActive(now: current)) {
      return null;
    }
    return record;
  }

  @override
  void revokeAll(String userId, String sessionBindingHash) {
    _records.removeWhere(
      (_, record) =>
          record.userId == userId &&
          record.sessionBindingHash == sessionBindingHash,
    );
  }

  @override
  void revokeAllForUser(String userId) {
    _records.removeWhere((_, record) => record.userId == userId);
  }

  void _removeExpired(DateTime now) {
    _records.removeWhere((_, record) => !record.isActive(now: now));
  }

  void _removeOldest() {
    if (_records.isEmpty) return;
    final oldest = _records.entries.reduce(
      (left, right) =>
          left.value.createdAt.isAfter(right.value.createdAt) ? right : left,
    );
    _records.remove(oldest.key);
  }
}

/// Exception used by an adapter to return a pending sign-in response.
class AuthTwoFactorRequiredException extends AuthFlowException {
  AuthTwoFactorRequiredException({required this.challenge})
    : super('two_factor_required');

  final AuthTwoFactorSignInChallenge challenge;
}

/// Public two-factor status that never exposes the secret or code digests.
class AuthTwoFactorStatus {
  const AuthTwoFactorStatus({
    required this.enabled,
    required this.recoveryCodesRemaining,
    this.enrollmentExpiresAt,
    this.lockedUntil,
  });

  final bool enabled;
  final int recoveryCodesRemaining;
  final DateTime? enrollmentExpiresAt;
  final DateTime? lockedUntil;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'recoveryCodesRemaining': recoveryCodesRemaining,
    if (enrollmentExpiresAt != null)
      'enrollmentExpiresAt': enrollmentExpiresAt!.toUtc().toIso8601String(),
    if (lockedUntil != null)
      'lockedUntil': lockedUntil!.toUtc().toIso8601String(),
  };
}

/// Optional TOTP and recovery-code authentication plugin.
///
/// The plugin covers enrollment, activation, verification, recovery-code
/// consumption, regeneration, and disablement. A framework adapter can use
/// [verifyTotp] or [useRecoveryCode] to gate a pending sign-in challenge;
/// pending sign-in orchestration is intentionally kept in the adapter so the
/// plugin remains framework-agnostic.
final class TwoFactorPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthReversibleUserDataDeletionContributor {
  TwoFactorPlugin({
    required this.store,
    required this.secretProtector,
    this.issuer = 'server_auth',
    this.enrollmentTtl = const Duration(minutes: 10),
    this.period = 30,
    this.digits = 6,
    this.allowedClockSkew = 1,
    this.maxFailedVerificationAttempts = 5,
    this.lockoutDuration = const Duration(minutes: 15),
    required this.challengeStore,
    this.challengeTtl = const Duration(minutes: 5),
    this.pendingRecoveryStore,
    required this.trustedDeviceStore,
    this.trustedDeviceTtl = const Duration(days: 30),
    this.trustedDeviceCookieName = 'two_factor_trusted_device',
    this.stepUpStore,
    this.stepUpTtl = const Duration(minutes: 5),
    this.stepUpCookieName = 'two_factor_step_up',
    List<int> Function(int length)? secretGenerator,
  }) : _secretGenerator = secretGenerator ?? _secureBytes {
    if (issuer.trim().isEmpty) {
      throw ArgumentError.value(issuer, 'issuer', 'must not be empty');
    }
    if (enrollmentTtl <= Duration.zero) {
      throw ArgumentError.value(
        enrollmentTtl,
        'enrollmentTtl',
        'must be greater than zero',
      );
    }
    if (period <= 0) throw ArgumentError.value(period, 'period');
    if (digits < 6 || digits > 8) {
      throw ArgumentError.value(digits, 'digits', 'must be between 6 and 8');
    }
    if (allowedClockSkew < 0 || allowedClockSkew > 5) {
      throw ArgumentError.value(allowedClockSkew, 'allowedClockSkew');
    }
    if (maxFailedVerificationAttempts < 1) {
      throw ArgumentError.value(
        maxFailedVerificationAttempts,
        'maxFailedVerificationAttempts',
      );
    }
    if (lockoutDuration <= Duration.zero) {
      throw ArgumentError.value(
        lockoutDuration,
        'lockoutDuration',
        'must be greater than zero',
      );
    }
    if (challengeTtl <= Duration.zero) {
      throw ArgumentError.value(
        challengeTtl,
        'challengeTtl',
        'must be greater than zero',
      );
    }
    if (trustedDeviceTtl <= Duration.zero) {
      throw ArgumentError.value(
        trustedDeviceTtl,
        'trustedDeviceTtl',
        'must be greater than zero',
      );
    }
    if (trustedDeviceCookieName.trim().isEmpty) {
      throw ArgumentError.value(
        trustedDeviceCookieName,
        'trustedDeviceCookieName',
        'must not be empty',
      );
    }
    if (stepUpTtl <= Duration.zero) {
      throw ArgumentError.value(
        stepUpTtl,
        'stepUpTtl',
        'must be greater than zero',
      );
    }
    if (stepUpCookieName.trim().isEmpty) {
      throw ArgumentError.value(
        stepUpCookieName,
        'stepUpCookieName',
        'must not be empty',
      );
    }
  }

  @override
  String get id => authTwoFactorPluginId;

  final AuthTwoFactorStore store;
  final AuthTwoFactorSecretProtector secretProtector;
  final String issuer;
  final Duration enrollmentTtl;
  final int period;
  final int digits;
  final int allowedClockSkew;
  final int maxFailedVerificationAttempts;
  final Duration lockoutDuration;
  final AuthTwoFactorChallengeStore challengeStore;
  final Duration challengeTtl;
  final AuthTwoFactorPendingRecoveryStore? pendingRecoveryStore;
  final AuthTwoFactorTrustedDeviceStore trustedDeviceStore;
  final Duration trustedDeviceTtl;
  final String trustedDeviceCookieName;
  final AuthTwoFactorStepUpStore? stepUpStore;
  final Duration stepUpTtl;
  final String stepUpCookieName;
  final List<int> Function(int length) _secretGenerator;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    // The plugin owns its additional persistence contract. The shared store
    // remains available for user/session lookups in future composed hooks.
  }

  @override
  String get userDataNamespace => 'two_factor';

  @override
  Future<void> validateUserDeletion(String userId) async {}

  @override
  Future<void> deleteUserData(String userId) async {
    await store.delete(userId);
    final now = DateTime.now().toUtc();
    final trusted = trustedDeviceStore;
    if (trusted is InMemoryAuthTwoFactorTrustedDeviceStore) {
      trusted._records.removeWhere((_, record) => record.userId == userId);
    } else {
      await trusted.revokeAll(userId, now: now);
    }
    final challenges = challengeStore;
    if (challenges is InMemoryAuthTwoFactorChallengeStore) {
      challenges._records.removeWhere((_, record) => record.userId == userId);
    }
    await stepUpStore?.revokeAllForUser(userId);
  }

  @override
  AuthUserDataDeletionCheckpoint checkpointUserData(String userId) =>
      AuthUserDataDeletionCheckpoint.capture([
        store,
        trustedDeviceStore,
        challengeStore,
        ?stepUpStore,
      ]);

  /// Starts a short-lived challenge for a user whose TOTP is enabled.
  Future<AuthTwoFactorSignInChallenge?> beginSignInChallenge(
    String userId, {
    String? trustedDeviceToken,
    AuthUser? user,
    String? providerId,
    AuthCredentials? credentials,
    DateTime? now,
  }) async {
    final factor = await store.findByUserId(userId);
    if (factor == null || !factor.verified) return null;
    final issuedAt = (now ?? DateTime.now()).toUtc();
    _ensureNotLocked(factor, issuedAt);
    if (trustedDeviceToken != null && trustedDeviceToken.isNotEmpty) {
      final trusted = await trustedDeviceStore.findActive(
        userId,
        hashOpaqueToken(trustedDeviceToken),
        now: issuedAt,
      );
      if (trusted != null) return null;
    }
    final token = secureRandomToken();
    final expiresAt = issuedAt.add(challengeTtl);
    await challengeStore.create(
      AuthTwoFactorChallengeRecord(
        id: secureRandomToken(length: 16),
        tokenHash: hashOpaqueToken(token),
        userId: userId,
        createdAt: issuedAt,
        expiresAt: expiresAt,
        user: user,
        providerId: providerId,
        credentials: credentials?.redacted(),
      ),
    );
    return AuthTwoFactorSignInChallenge(token: token, expiresAt: expiresAt);
  }

  /// Verifies a TOTP code and atomically completes a pending sign-in.
  Future<AuthTwoFactorSignInCompletion> completeSignInChallenge(
    String token,
    String code, {
    bool trustDevice = false,
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final tokenHash = hashOpaqueToken(token);
    final challenge = await challengeStore.findByTokenHash(tokenHash);
    if (challenge == null || !challenge.isActive(now: current)) {
      throw AuthFlowException('two_factor_invalid_challenge');
    }
    if (challenge.lockedUntil != null &&
        current.isBefore(challenge.lockedUntil!.toUtc())) {
      throw AuthFlowException('two_factor_challenge_locked');
    }
    final factor = await _requireRecord(challenge.userId);
    _ensureNotLocked(factor, current);
    final valid = _matchesTotp(factor, code, current);
    final attempt = await challengeStore.recordAttempt(
      tokenHash,
      now: current,
      valid: valid,
      maxAttempts: maxFailedVerificationAttempts,
      lockoutDuration: lockoutDuration,
    );
    if (attempt.expired) {
      throw AuthFlowException('two_factor_invalid_challenge');
    }
    if (!valid) {
      await _recordFailure(challenge.userId, current);
    }
    if (attempt.locked) {
      throw AuthFlowException('two_factor_challenge_locked');
    }
    if (!attempt.accepted) {
      throw AuthFlowException('two_factor_invalid_code');
    }
    await store.clearVerificationFailures(challenge.userId, now: current);
    AuthTwoFactorTrustedDeviceToken? trustedDevice;
    if (trustDevice) {
      trustedDevice = await _issueTrustedDevice(challenge.userId, now: current);
    }
    return AuthTwoFactorSignInCompletion(
      userId: challenge.userId,
      user: challenge.user,
      providerId: challenge.providerId,
      credentials: challenge.credentials,
      trustedDevice: trustedDevice,
    );
  }

  /// Completes a pending credential sign-in with one recovery code.
  ///
  /// Recovery-code completion requires [pendingRecoveryStore] because the
  /// recovery digest and challenge record must be consumed in one transaction.
  /// It deliberately does not issue a trusted-device token: a device token
  /// requires a fresh TOTP proof, while the recovery code is a fallback path.
  Future<AuthTwoFactorSignInCompletion> completeRecoverySignInChallenge(
    String token,
    String recoveryCode, {
    DateTime? now,
  }) async {
    final transaction = pendingRecoveryStore;
    if (transaction == null) {
      throw AuthFlowException('two_factor_recovery_not_supported');
    }
    final tokenHash = hashOpaqueToken(token);
    final challenge = await challengeStore.findByTokenHash(tokenHash);
    if (challenge == null || !challenge.isActive(now: now)) {
      throw AuthFlowException('two_factor_invalid_challenge');
    }
    final attempt = await transaction.recordRecoveryAttempt(
      tokenHash,
      recoveryCodeHash: _hashRecoveryCode(recoveryCode),
      now: (now ?? DateTime.now()).toUtc(),
      maxAttempts: maxFailedVerificationAttempts,
      lockoutDuration: lockoutDuration,
    );
    if (attempt.expired) {
      throw AuthFlowException('two_factor_invalid_challenge');
    }
    if (attempt.locked) {
      throw AuthFlowException('two_factor_challenge_locked');
    }
    if (!attempt.accepted || attempt.userId == null) {
      throw AuthFlowException('two_factor_invalid_recovery_code');
    }
    return AuthTwoFactorSignInCompletion(
      userId: attempt.userId!,
      user: challenge.user,
      providerId: challenge.providerId,
      credentials: challenge.credentials,
    );
  }

  /// Creates a trusted-device token for an already-enabled two-factor user.
  ///
  /// A fresh TOTP code is required so callers cannot mint a device token from
  /// knowledge of the user ID alone.
  Future<AuthTwoFactorTrustedDeviceToken> issueTrustedDevice(
    String userId,
    String code, {
    DateTime? now,
  }) async {
    await verifyTotp(userId, code, now: now);
    return _issueTrustedDevice(userId, now: now);
  }

  /// Issues a trusted-device token after the caller has already completed a
  /// TOTP proof in this plugin.
  Future<AuthTwoFactorTrustedDeviceToken> _issueTrustedDevice(
    String userId, {
    DateTime? now,
  }) async {
    await _requireRecord(userId);
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final token = secureRandomToken();
    final expiresAt = issuedAt.add(trustedDeviceTtl);
    await trustedDeviceStore.create(
      AuthTwoFactorTrustedDeviceRecord(
        id: secureRandomToken(length: 16),
        userId: userId,
        tokenHash: hashOpaqueToken(token),
        createdAt: issuedAt,
        expiresAt: expiresAt,
      ),
    );
    return AuthTwoFactorTrustedDeviceToken(token: token, expiresAt: expiresAt);
  }

  /// Revokes every trusted device for [userId].
  Future<void> revokeAllTrustedDevices(String userId, {DateTime? now}) async {
    _requireUserId(userId);
    await trustedDeviceStore.revokeAll(
      userId,
      now: (now ?? DateTime.now()).toUtc(),
    );
  }

  /// Starts or replaces an unverified enrollment for [userId].
  Future<AuthTwoFactorEnrollment> beginEnrollment(
    String userId, {
    String? accountLabel,
    DateTime? now,
  }) async {
    _requireUserId(userId);
    final existing = await store.findByUserId(userId);
    if (existing?.verified == true) {
      throw AuthFlowException('two_factor_already_enabled');
    }
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final secretBytes = _secretGenerator(20);
    if (secretBytes.length != 20) {
      throw StateError('The TOTP secret generator returned an invalid size');
    }
    final secret = encodeAuthBase32(secretBytes);
    final expiresAt = issuedAt.add(enrollmentTtl);
    await store.save(
      AuthTwoFactorRecord(
        userId: userId,
        protectedSecret: secretProtector.protect(secret),
        enrollmentExpiresAt: expiresAt,
        updatedAt: issuedAt,
      ),
    );
    final label = accountLabel == null || accountLabel.trim().isEmpty
        ? userId
        : accountLabel.trim();
    final query = <String, String>{
      'secret': secret,
      'issuer': issuer,
      'algorithm': 'SHA1',
      'digits': '$digits',
      'period': '$period',
    };
    return AuthTwoFactorEnrollment(
      secret: secret,
      otpauthUri: Uri(
        scheme: 'otpauth',
        host: 'totp',
        path: '$issuer:$label',
        queryParameters: query,
      ),
      expiresAt: expiresAt,
    );
  }

  /// Activates a pending enrollment after verifying its first TOTP code.
  Future<AuthTwoFactorRecoveryCodes> verifyEnrollment(
    String userId,
    String code, {
    DateTime? now,
  }) async {
    final record = await _requireRecord(userId, requireVerified: false);
    final current = (now ?? DateTime.now()).toUtc();
    if (record.verified) {
      throw AuthFlowException('two_factor_already_enabled');
    }
    if (!current.isBefore(record.enrollmentExpiresAt.toUtc())) {
      throw AuthFlowException('two_factor_enrollment_expired');
    }
    _ensureNotLocked(record, current);
    if (!_matchesTotp(record, code, current)) {
      await _recordFailure(userId, current);
      throw AuthFlowException('two_factor_invalid_code');
    }
    final recovery = _newRecoveryCodes();
    final activated = record.copyWith(
      verified: true,
      recoveryCodeHashes: recovery.codes.map(_hashRecoveryCode).toList(),
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: current,
    );
    if (!await store.saveIfCurrent(record, activated)) {
      throw AuthFlowException('two_factor_enrollment_changed');
    }
    return recovery;
  }

  /// Returns the current public status for [userId].
  Future<AuthTwoFactorStatus> status(String userId, {DateTime? now}) async {
    final record = await store.findByUserId(userId);
    if (record == null) {
      return const AuthTwoFactorStatus(
        enabled: false,
        recoveryCodesRemaining: 0,
      );
    }
    final current = (now ?? DateTime.now()).toUtc();
    return AuthTwoFactorStatus(
      enabled: record.verified,
      recoveryCodesRemaining: record.recoveryCodeHashes.length,
      enrollmentExpiresAt: record.verified ? null : record.enrollmentExpiresAt,
      lockedUntil:
          record.lockedUntil != null &&
              current.isBefore(record.lockedUntil!.toUtc())
          ? record.lockedUntil
          : null,
    );
  }

  /// Verifies an enabled TOTP code.
  Future<void> verifyTotp(String userId, String code, {DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    final record = await _requireRecord(userId);
    _ensureNotLocked(record, current);
    if (!_matchesTotp(record, code, current)) {
      await _recordFailure(userId, current);
      throw AuthFlowException('two_factor_invalid_code');
    }
    await store.clearVerificationFailures(userId, now: current);
  }

  /// Verifies TOTP and issues a short-lived proof for a sensitive action.
  ///
  /// [sessionBinding] must be a stable, adapter-owned binding for the current
  /// authenticated credential. Adapters should pass a digest rather than a
  /// raw session or bearer token.
  Future<AuthTwoFactorStepUpToken> verifyStepUp(
    String userId,
    String sessionBinding,
    String code, {
    DateTime? now,
  }) async {
    final stepUpStore = this.stepUpStore;
    if (stepUpStore == null) {
      throw AuthFlowException('two_factor_step_up_not_supported');
    }
    _requireSessionBinding(sessionBinding);
    final current = (now ?? DateTime.now()).toUtc();
    final record = await _requireRecord(userId);
    _ensureNotLocked(record, current);
    if (!_matchesTotp(record, code, current)) {
      await _recordFailure(userId, current);
      throw AuthFlowException('two_factor_invalid_code');
    }
    await store.clearVerificationFailures(userId, now: current);
    final token = secureRandomToken();
    final expiresAt = current.add(stepUpTtl);
    await stepUpStore.create(
      AuthTwoFactorStepUpRecord(
        id: secureRandomToken(length: 16),
        userId: userId,
        sessionBindingHash: hashOpaqueToken(sessionBinding),
        tokenHash: hashOpaqueToken(token),
        createdAt: current,
        expiresAt: expiresAt,
      ),
    );
    return AuthTwoFactorStepUpToken(token: token, expiresAt: expiresAt);
  }

  /// Returns whether [token] is a current step-up proof for this session.
  Future<bool> isStepUpValid(
    String userId,
    String sessionBinding,
    String token, {
    DateTime? now,
  }) async {
    final stepUpStore = this.stepUpStore;
    if (stepUpStore == null ||
        sessionBinding.trim().isEmpty ||
        token.trim().isEmpty) {
      return false;
    }
    final record = await stepUpStore.findActive(
      userId,
      hashOpaqueToken(sessionBinding),
      hashOpaqueToken(token),
      now: (now ?? DateTime.now()).toUtc(),
    );
    return record != null;
  }

  /// Revokes all step-up proofs for the current user/session binding.
  Future<void> revokeStepUp(String userId, String sessionBinding) async {
    final stepUpStore = this.stepUpStore;
    if (stepUpStore == null) return;
    _requireSessionBinding(sessionBinding);
    await stepUpStore.revokeAll(userId, hashOpaqueToken(sessionBinding));
  }

  /// Revokes every step-up proof issued for [userId].
  Future<void> revokeAllStepUpProofs(String userId) async {
    _requireUserId(userId);
    final stepUpStore = this.stepUpStore;
    if (stepUpStore == null) return;
    await stepUpStore.revokeAllForUser(userId);
  }

  /// Consumes one recovery code for [userId].
  Future<void> useRecoveryCode(
    String userId,
    String code, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final record = await _requireRecord(userId);
    _ensureNotLocked(record, current);
    final consumed = await store.consumeRecoveryCode(
      userId,
      _hashRecoveryCode(code),
      now: current,
    );
    if (!consumed) {
      await _recordFailure(userId, current);
      throw AuthFlowException('two_factor_invalid_recovery_code');
    }
    await store.clearVerificationFailures(userId, now: current);
  }

  /// Replaces all recovery codes after verifying the current TOTP code.
  Future<AuthTwoFactorRecoveryCodes> regenerateRecoveryCodes(
    String userId,
    String code, {
    DateTime? now,
  }) async {
    await verifyTotp(userId, code, now: now);
    final record = await _requireRecord(userId);
    final recovery = _newRecoveryCodes();
    final replacement = record.copyWith(
      recoveryCodeHashes: recovery.codes.map(_hashRecoveryCode).toList(),
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
    if (!await store.saveIfCurrent(record, replacement)) {
      throw AuthFlowException('two_factor_state_changed');
    }
    return recovery;
  }

  /// Disables two-factor authentication after verifying the current TOTP code.
  Future<void> disable(String userId, String code, {DateTime? now}) async {
    await verifyTotp(userId, code, now: now);
    await revokeAllStepUpProofs(userId);
    await store.delete(userId);
    await revokeAllTrustedDevices(userId, now: now);
  }

  bool _matchesTotp(AuthTwoFactorRecord record, String code, DateTime now) {
    try {
      final secret = secretProtector.reveal(record.protectedSecret);
      final normalized = _normalizeTotpCode(code);
      if (normalized.length != digits) return false;
      final counter = now.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;
      for (
        var offset = -allowedClockSkew;
        offset <= allowedClockSkew;
        offset++
      ) {
        if (constantTimeStringEquals(
          generateAuthTotpCode(
            secret,
            timestampSeconds: (counter + offset) * period,
            period: period,
            digits: digits,
          ),
          normalized,
        )) {
          return true;
        }
      }
    } catch (_) {
      // Treat corrupt persisted secrets and protector failures as an invalid
      // code without exposing library, key-management, or storage details.
    }
    return false;
  }

  Future<AuthTwoFactorRecord> _requireRecord(
    String userId, {
    bool requireVerified = true,
  }) async {
    _requireUserId(userId);
    final record = await store.findByUserId(userId);
    if (record == null || (requireVerified && !record.verified)) {
      throw AuthFlowException('two_factor_not_enabled');
    }
    return record;
  }

  void _ensureNotLocked(AuthTwoFactorRecord record, DateTime now) {
    if (record.lockedUntil != null &&
        now.isBefore(record.lockedUntil!.toUtc())) {
      throw AuthFlowException('two_factor_locked');
    }
  }

  Future<void> _recordFailure(String userId, DateTime now) async {
    await store.recordFailedVerification(
      userId,
      now: now,
      maxAttempts: maxFailedVerificationAttempts,
      lockoutDuration: lockoutDuration,
    );
  }

  AuthTwoFactorRecoveryCodes _newRecoveryCodes() {
    final codes = <String>[];
    final seen = <String>{};
    var attempts = 0;
    const maxAttempts = 100;
    while (codes.length < 10) {
      if (++attempts > maxAttempts) {
        throw StateError(
          'The recovery-code generator could not produce unique codes',
        );
      }
      final code = _formatRecoveryCode(_encodeRandomCode(_secretGenerator(10)));
      if (seen.add(code)) codes.add(code);
    }
    return AuthTwoFactorRecoveryCodes(List<String>.unmodifiable(codes));
  }

  String _encodeRandomCode(List<int> bytes) {
    if (bytes.length != 10) {
      throw StateError('The recovery-code generator returned an invalid size');
    }
    return encodeAuthBase32(bytes);
  }

  String _formatRecoveryCode(String value) {
    return RegExp(
      '.{1,4}',
    ).allMatches(value).map((match) => match.group(0)!).join('-');
  }

  String _hashRecoveryCode(String code) {
    return hashOpaqueToken(_normalizeRecoveryCode(code));
  }
}

/// Encodes bytes in RFC 4648 base32 without padding.
String encodeAuthBase32(List<int> bytes) {
  var buffer = 0;
  var bits = 0;
  final output = StringBuffer();
  for (final byte in bytes) {
    buffer = (buffer << 8) | (byte & 0xff);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      output.write(_base32Alphabet[(buffer >> bits) & 31]);
    }
  }
  if (bits > 0) {
    output.write(_base32Alphabet[(buffer << (5 - bits)) & 31]);
  }
  return output.toString();
}

/// Decodes unpadded RFC 4648 base32, returning `null` for malformed input.
List<int>? decodeAuthBase32(String value) {
  final withoutSeparators = value
      .trim()
      .replaceAll(RegExp(r'[-\s]'), '')
      .toUpperCase();
  final paddingIndex = withoutSeparators.indexOf('=');
  final normalized = paddingIndex < 0
      ? withoutSeparators
      : withoutSeparators.substring(0, paddingIndex);
  if (paddingIndex >= 0 &&
      !RegExp(r'^=+$').hasMatch(withoutSeparators.substring(paddingIndex))) {
    return null;
  }
  if (normalized.isEmpty) return null;
  final remainder = normalized.length % 8;
  if (remainder == 1 || remainder == 3 || remainder == 6) return null;
  if (paddingIndex >= 0) {
    final expectedPadding = (8 - remainder) % 8;
    if (withoutSeparators.length - paddingIndex != expectedPadding) {
      return null;
    }
  }
  var buffer = 0;
  var bits = 0;
  final output = <int>[];
  for (final character in normalized.codeUnits) {
    final index = _base32Alphabet.indexOf(String.fromCharCode(character));
    if (index < 0) return null;
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.add((buffer >> bits) & 0xff);
    }
  }
  if (bits > 0 && (buffer & ((1 << bits) - 1)) != 0) return null;
  return output;
}

/// Generates an RFC 6238 TOTP code using the maintained [hashlib] OTP core.
String generateAuthTotpCode(
  String base32Secret, {
  int? timestampSeconds,
  int period = 30,
  int digits = 6,
}) {
  if (period <= 0) throw ArgumentError.value(period, 'period');
  if (digits < 6 || digits > 8) throw ArgumentError.value(digits, 'digits');
  final secret = decodeAuthBase32(base32Secret);
  if (secret == null || secret.isEmpty) {
    throw ArgumentError.value(base32Secret, 'base32Secret');
  }
  final seconds =
      timestampSeconds ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final counter = seconds ~/ period;
  final counterBytes = Uint8List(8);
  var value = counter;
  for (var index = counterBytes.length - 1; index >= 0; index--) {
    counterBytes[index] = value & 0xff;
    value >>= 8;
  }
  return HOTP(
    secret,
    counter: counterBytes,
    digits: digits,
    algo: sha1,
  ).valueString();
}

String _normalizeTotpCode(String code) => code.trim();

String _normalizeRecoveryCode(String code) =>
    code.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();

void _requireUserId(String userId) {
  if (userId.trim().isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must not be empty');
  }
}

void _requireSessionBinding(String sessionBinding) {
  if (sessionBinding.trim().isEmpty) {
    throw ArgumentError.value(
      sessionBinding,
      'sessionBinding',
      'must not be empty',
    );
  }
}

List<int> _secureBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
