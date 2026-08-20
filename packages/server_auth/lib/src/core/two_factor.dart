import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart';

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'rate_limit.dart';
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
    implements AuthTwoFactorStore, AuthInMemoryUserDeletionStore {
  final Map<String, AuthTwoFactorRecord> _records =
      <String, AuthTwoFactorRecord>{};

  @override
  Object captureDeletionState() =>
      Map<String, AuthTwoFactorRecord>.of(_records);

  @override
  void restoreDeletionState(Object checkpoint) {
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
  void deleteUserDataForDeletion(String userId) => delete(userId);

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
    implements AuthTwoFactorTrustedDeviceStore, AuthInMemoryUserDeletionStore {
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
  Object captureDeletionState() =>
      Map<String, AuthTwoFactorTrustedDeviceRecord>.of(_records);

  @override
  void restoreDeletionState(Object checkpoint) {
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

  @override
  void deleteUserDataForDeletion(String userId) =>
      revokeAll(userId, now: _clock().toUtc());

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
    implements AuthTwoFactorChallengeStore, AuthInMemoryUserDeletionStore {
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
  Object captureDeletionState() =>
      Map<String, AuthTwoFactorChallengeRecord>.of(_records);

  @override
  void restoreDeletionState(Object checkpoint) {
    final records = checkpoint as Map<String, AuthTwoFactorChallengeRecord>;
    _records
      ..clear()
      ..addAll(records);
  }

  @override
  void deleteUserDataForDeletion(String userId) {
    _records.removeWhere((_, record) => record.userId == userId.trim());
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
    implements AuthTwoFactorStepUpStore, AuthInMemoryUserDeletionStore {
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
  Object captureDeletionState() =>
      Map<String, AuthTwoFactorStepUpRecord>.of(_records);

  @override
  void restoreDeletionState(Object checkpoint) {
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

  @override
  void deleteUserDataForDeletion(String userId) => revokeAllForUser(userId);

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

/// Outcome of a backend-owned two-factor atomic command.
enum AuthTwoFactorCommandStatus {
  applied,
  bypassed,
  invalid,
  locked,
  expired,
  notFound,
  conflict,
}

/// Result returned by every two-factor atomic command.
///
/// [challenge] is populated only for commands operating on a pending sign-in.
/// It contains the already-redacted credential snapshot stored by the plugin.
class AuthTwoFactorCommandResult {
  const AuthTwoFactorCommandResult(this.status, {this.challenge});

  final AuthTwoFactorCommandStatus status;
  final AuthTwoFactorChallengeRecord? challenge;
}

/// Attempt and lockout policy evaluated inside an atomic command.
class AuthTwoFactorAttemptPolicy {
  const AuthTwoFactorAttemptPolicy({
    required this.now,
    required this.maxAttempts,
    required this.lockoutDuration,
  });

  final DateTime now;
  final int maxAttempts;
  final Duration lockoutDuration;
}

/// Atomically starts or replaces an unverified enrollment.
class AuthTwoFactorBeginEnrollmentCommand {
  const AuthTwoFactorBeginEnrollmentCommand(this.record);

  final AuthTwoFactorRecord record;
}

/// Atomically activates an enrollment or records its failed TOTP attempt.
class AuthTwoFactorVerifyEnrollmentCommand {
  const AuthTwoFactorVerifyEnrollmentCommand({
    required this.expected,
    required this.valid,
    required this.recoveryCodeHashes,
    required this.policy,
  });

  final AuthTwoFactorRecord expected;
  final bool valid;
  final List<String> recoveryCodeHashes;
  final AuthTwoFactorAttemptPolicy policy;
}

/// Atomically verifies TOTP and updates the account attempt state.
class AuthTwoFactorVerifyTotpCommand {
  const AuthTwoFactorVerifyTotpCommand({
    required this.expected,
    required this.valid,
    required this.policy,
  });

  final AuthTwoFactorRecord expected;
  final bool valid;
  final AuthTwoFactorAttemptPolicy policy;
}

/// Atomically consumes a recovery code or records the failed attempt.
class AuthTwoFactorUseRecoveryCodeCommand {
  const AuthTwoFactorUseRecoveryCodeCommand({
    required this.userId,
    required this.recoveryCodeHash,
    required this.policy,
  });

  final String userId;
  final String recoveryCodeHash;
  final AuthTwoFactorAttemptPolicy policy;
}

/// Atomically verifies TOTP and replaces every recovery-code digest.
class AuthTwoFactorRegenerateRecoveryCodesCommand {
  const AuthTwoFactorRegenerateRecoveryCodesCommand({
    required this.expected,
    required this.valid,
    required this.recoveryCodeHashes,
    required this.policy,
  });

  final AuthTwoFactorRecord expected;
  final bool valid;
  final List<String> recoveryCodeHashes;
  final AuthTwoFactorAttemptPolicy policy;
}

/// Atomically verifies TOTP and removes all two-factor state for a user.
class AuthTwoFactorDisableCommand {
  const AuthTwoFactorDisableCommand({
    required this.expected,
    required this.valid,
    required this.policy,
  });

  final AuthTwoFactorRecord expected;
  final bool valid;
  final AuthTwoFactorAttemptPolicy policy;
}

/// Atomically accepts a trusted device or creates a pending sign-in challenge.
class AuthTwoFactorBeginChallengeCommand {
  const AuthTwoFactorBeginChallengeCommand({
    required this.userId,
    required this.challenge,
    required this.now,
    this.trustedDeviceTokenHash,
  });

  final String userId;
  final AuthTwoFactorChallengeRecord challenge;
  final DateTime now;
  final String? trustedDeviceTokenHash;
}

/// Atomically completes a pending TOTP challenge and optionally trusts a device.
class AuthTwoFactorCompleteChallengeCommand {
  const AuthTwoFactorCompleteChallengeCommand({
    required this.tokenHash,
    required this.expectedFactor,
    required this.valid,
    required this.policy,
    this.trustedDevice,
  });

  final String tokenHash;
  final AuthTwoFactorRecord expectedFactor;
  final bool valid;
  final AuthTwoFactorAttemptPolicy policy;
  final AuthTwoFactorTrustedDeviceRecord? trustedDevice;
}

/// Atomically consumes recovery material and completes a pending challenge.
class AuthTwoFactorCompleteRecoveryChallengeCommand {
  const AuthTwoFactorCompleteRecoveryChallengeCommand({
    required this.tokenHash,
    required this.recoveryCodeHash,
    required this.policy,
  });

  final String tokenHash;
  final String recoveryCodeHash;
  final AuthTwoFactorAttemptPolicy policy;
}

/// Atomically verifies TOTP and creates a trusted-device record.
class AuthTwoFactorIssueTrustedDeviceCommand {
  const AuthTwoFactorIssueTrustedDeviceCommand({
    required this.expectedFactor,
    required this.valid,
    required this.trustedDevice,
    required this.policy,
  });

  final AuthTwoFactorRecord expectedFactor;
  final bool valid;
  final AuthTwoFactorTrustedDeviceRecord trustedDevice;
  final AuthTwoFactorAttemptPolicy policy;
}

/// Atomically verifies TOTP and creates a session-bound recent proof.
class AuthTwoFactorVerifyStepUpCommand {
  const AuthTwoFactorVerifyStepUpCommand({
    required this.expectedFactor,
    required this.valid,
    required this.proof,
    required this.policy,
  });

  final AuthTwoFactorRecord expectedFactor;
  final bool valid;
  final AuthTwoFactorStepUpRecord proof;
  final AuthTwoFactorAttemptPolicy policy;
}

class AuthTwoFactorRevokeTrustedDevicesCommand {
  const AuthTwoFactorRevokeTrustedDevicesCommand({
    required this.userId,
    required this.now,
  });

  final String userId;
  final DateTime now;
}

class AuthTwoFactorRevokeStepUpCommand {
  const AuthTwoFactorRevokeStepUpCommand({
    required this.userId,
    required this.sessionBindingHash,
  });

  final String userId;
  final String sessionBindingHash;
}

/// Required persistence boundary for the optional two-factor plugin.
///
/// Durable adapters implement these typed commands with backend-native
/// transactions. The plugin never supplies a transaction callback and never
/// falls back to coordinating individual writes itself.
abstract interface class AuthTwoFactorBackend {
  AuthTwoFactorStore get factorStore;
  AuthTwoFactorChallengeStore get challengeStore;
  AuthTwoFactorTrustedDeviceStore get trustedDeviceStore;
  AuthTwoFactorStepUpStore get stepUpStore;

  FutureOr<AuthTwoFactorCommandResult> beginEnrollment(
    AuthTwoFactorBeginEnrollmentCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> verifyEnrollment(
    AuthTwoFactorVerifyEnrollmentCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> verifyTotp(
    AuthTwoFactorVerifyTotpCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> useRecoveryCode(
    AuthTwoFactorUseRecoveryCodeCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> regenerateRecoveryCodes(
    AuthTwoFactorRegenerateRecoveryCodesCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> disable(
    AuthTwoFactorDisableCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> beginChallenge(
    AuthTwoFactorBeginChallengeCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> completeChallenge(
    AuthTwoFactorCompleteChallengeCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> completeRecoveryChallenge(
    AuthTwoFactorCompleteRecoveryChallengeCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> issueTrustedDevice(
    AuthTwoFactorIssueTrustedDeviceCommand command,
  );

  FutureOr<AuthTwoFactorCommandResult> verifyStepUp(
    AuthTwoFactorVerifyStepUpCommand command,
  );

  FutureOr<void> revokeTrustedDevices(
    AuthTwoFactorRevokeTrustedDevicesCommand command,
  );

  FutureOr<void> revokeStepUp(AuthTwoFactorRevokeStepUpCommand command);

  FutureOr<void> revokeAllStepUp(String userId);
}

/// In-memory fault locations used to prove rollback behavior.
enum AuthTwoFactorAtomicFaultPoint {
  afterFactorWrite,
  afterChallengeWrite,
  afterTrustedDeviceWrite,
  afterStepUpWrite,
}

final class AuthTwoFactorInjectedFault implements Exception {
  const AuthTwoFactorInjectedFault(this.point);

  final AuthTwoFactorAtomicFaultPoint point;

  @override
  String toString() => 'AuthTwoFactorInjectedFault(${point.name})';
}

/// Deterministic, one-shot fault injection for the in-memory backend.
final class AuthTwoFactorFaultInjector {
  final Set<AuthTwoFactorAtomicFaultPoint> _pending =
      <AuthTwoFactorAtomicFaultPoint>{};

  void failNext(AuthTwoFactorAtomicFaultPoint point) => _pending.add(point);

  void _check(AuthTwoFactorAtomicFaultPoint point) {
    if (_pending.remove(point)) throw AuthTwoFactorInjectedFault(point);
  }
}

/// Transactional in-memory backend for tests and local applications.
///
/// Commands are serialized per user. Every command snapshots all two-factor
/// stores and restores them if a write or injected fault fails.
final class InMemoryAuthTwoFactorBackend
    implements AuthTwoFactorBackend, AuthInMemoryDeletionState {
  InMemoryAuthTwoFactorBackend({
    InMemoryAuthTwoFactorStore? factorStore,
    InMemoryAuthTwoFactorChallengeStore? challengeStore,
    InMemoryAuthTwoFactorTrustedDeviceStore? trustedDeviceStore,
    InMemoryAuthTwoFactorStepUpStore? stepUpStore,
    this.faultInjector,
    DateTime Function()? clock,
  }) : factorStore = factorStore ?? InMemoryAuthTwoFactorStore(),
       challengeStore =
           challengeStore ?? InMemoryAuthTwoFactorChallengeStore(clock: clock),
       trustedDeviceStore =
           trustedDeviceStore ??
           InMemoryAuthTwoFactorTrustedDeviceStore(clock: clock),
       stepUpStore =
           stepUpStore ?? InMemoryAuthTwoFactorStepUpStore(clock: clock);

  @override
  final InMemoryAuthTwoFactorStore factorStore;

  @override
  final InMemoryAuthTwoFactorChallengeStore challengeStore;

  @override
  final InMemoryAuthTwoFactorTrustedDeviceStore trustedDeviceStore;

  @override
  final InMemoryAuthTwoFactorStepUpStore stepUpStore;

  final AuthTwoFactorFaultInjector? faultInjector;
  final Map<String, Future<void>> _userTails = <String, Future<void>>{};

  @override
  Object captureDeletionState() => _captureState();

  @override
  void restoreDeletionState(Object checkpoint) => _restoreState(checkpoint);

  @override
  Future<AuthTwoFactorCommandResult> beginEnrollment(
    AuthTwoFactorBeginEnrollmentCommand command,
  ) => _atomic(command.record.userId, () {
    final current = factorStore._records[command.record.userId];
    if (current?.verified == true) {
      return const AuthTwoFactorCommandResult(
        AuthTwoFactorCommandStatus.conflict,
      );
    }
    factorStore._records[command.record.userId] = command.record;
    _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
    return const AuthTwoFactorCommandResult(AuthTwoFactorCommandStatus.applied);
  });

  @override
  Future<AuthTwoFactorCommandResult> verifyEnrollment(
    AuthTwoFactorVerifyEnrollmentCommand command,
  ) => _atomic(command.expected.userId, () {
    final current = factorStore._records[command.expected.userId];
    if (current == null) return _notFound;
    if (current.verified || !_sameFactorIdentity(current, command.expected)) {
      return _conflict;
    }
    final now = command.policy.now.toUtc();
    if (!now.isBefore(current.enrollmentExpiresAt.toUtc())) return _expired;
    if (_isLocked(current, now)) return _locked;
    if (!command.valid) return _failFactor(current, command.policy);
    factorStore._records[current.userId] = current.copyWith(
      verified: true,
      recoveryCodeHashes: List<String>.unmodifiable(command.recoveryCodeHashes),
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: now,
    );
    _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
    return _applied;
  });

  @override
  Future<AuthTwoFactorCommandResult> verifyTotp(
    AuthTwoFactorVerifyTotpCommand command,
  ) => _atomic(command.expected.userId, () {
    final current = factorStore._records[command.expected.userId];
    final checked = _checkVerifiedFactor(
      current,
      command.expected,
      command.policy,
    );
    if (checked != null) return checked;
    if (!command.valid) return _failFactor(current!, command.policy);
    _clearFactorFailures(current!, command.policy.now);
    return _applied;
  });

  @override
  Future<AuthTwoFactorCommandResult> useRecoveryCode(
    AuthTwoFactorUseRecoveryCodeCommand command,
  ) => _atomic(command.userId, () {
    final current = factorStore._records[command.userId];
    if (current == null || !current.verified) return _notFound;
    final now = command.policy.now.toUtc();
    if (_isLocked(current, now)) return _locked;
    final remaining = List<String>.from(current.recoveryCodeHashes);
    final index = remaining.indexWhere(
      (candidate) =>
          constantTimeStringEquals(candidate, command.recoveryCodeHash),
    );
    if (index < 0) return _failFactor(current, command.policy);
    remaining.removeAt(index);
    factorStore._records[command.userId] = current.copyWith(
      recoveryCodeHashes: List<String>.unmodifiable(remaining),
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: now,
    );
    _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
    return _applied;
  });

  @override
  Future<AuthTwoFactorCommandResult> regenerateRecoveryCodes(
    AuthTwoFactorRegenerateRecoveryCodesCommand command,
  ) => _atomic(command.expected.userId, () {
    final current = factorStore._records[command.expected.userId];
    final checked = _checkVerifiedFactor(
      current,
      command.expected,
      command.policy,
    );
    if (checked != null) return checked;
    if (!command.valid) return _failFactor(current!, command.policy);
    if (!_sameRecord(current!, command.expected)) return _conflict;
    factorStore._records[current.userId] = current.copyWith(
      recoveryCodeHashes: List<String>.unmodifiable(command.recoveryCodeHashes),
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: command.policy.now.toUtc(),
    );
    _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
    return _applied;
  });

  @override
  Future<AuthTwoFactorCommandResult> disable(
    AuthTwoFactorDisableCommand command,
  ) => _atomic(command.expected.userId, () {
    final current = factorStore._records[command.expected.userId];
    final checked = _checkVerifiedFactor(
      current,
      command.expected,
      command.policy,
    );
    if (checked != null) return checked;
    if (!command.valid) return _failFactor(current!, command.policy);
    if (!_sameRecord(current!, command.expected)) return _conflict;
    factorStore._records.remove(current.userId);
    _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
    challengeStore._records.removeWhere(
      (_, challenge) => challenge.userId == current.userId,
    );
    _fault(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);
    trustedDeviceStore.revokeAll(
      current.userId,
      now: command.policy.now.toUtc(),
    );
    _fault(AuthTwoFactorAtomicFaultPoint.afterTrustedDeviceWrite);
    stepUpStore.revokeAllForUser(current.userId);
    _fault(AuthTwoFactorAtomicFaultPoint.afterStepUpWrite);
    return _applied;
  });

  @override
  Future<AuthTwoFactorCommandResult> beginChallenge(
    AuthTwoFactorBeginChallengeCommand command,
  ) => _atomic(command.userId, () {
    final factor = factorStore._records[command.userId];
    if (factor == null || !factor.verified) return _bypassed;
    final now = command.now.toUtc();
    if (_isLocked(factor, now)) return _locked;
    final trustedHash = command.trustedDeviceTokenHash;
    if (trustedHash != null && trustedHash.isNotEmpty) {
      final trusted = trustedDeviceStore.findActive(
        command.userId,
        trustedHash,
        now: now,
      );
      if (trusted != null) {
        _fault(AuthTwoFactorAtomicFaultPoint.afterTrustedDeviceWrite);
        return _bypassed;
      }
    }
    if (command.challenge.userId != command.userId) return _conflict;
    challengeStore.create(command.challenge);
    _fault(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);
    return AuthTwoFactorCommandResult(
      AuthTwoFactorCommandStatus.applied,
      challenge: command.challenge,
    );
  });

  @override
  Future<AuthTwoFactorCommandResult> completeChallenge(
    AuthTwoFactorCompleteChallengeCommand command,
  ) async {
    final observed = challengeStore._records[command.tokenHash];
    if (observed == null) return _expired;
    return _atomic(observed.userId, () {
      final now = command.policy.now.toUtc();
      final challenge = challengeStore._records[command.tokenHash];
      if (challenge == null || !challenge.isActive(now: now)) return _expired;
      if (_challengeLocked(challenge, now)) {
        return AuthTwoFactorCommandResult(
          AuthTwoFactorCommandStatus.locked,
          challenge: challenge,
        );
      }
      final factor = factorStore._records[challenge.userId];
      final checked = _checkVerifiedFactor(
        factor,
        command.expectedFactor,
        command.policy,
      );
      if (checked != null) {
        return AuthTwoFactorCommandResult(checked.status, challenge: challenge);
      }
      if (!command.valid) {
        final challengeFailures = challenge.failedVerificationCount + 1;
        challengeStore._records[command.tokenHash] = challenge.copyWith(
          failedVerificationCount: challengeFailures,
          lockedUntil: challengeFailures >= command.policy.maxAttempts
              ? now.add(command.policy.lockoutDuration)
              : challenge.lockedUntil,
        );
        _fault(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);
        final factorResult = _failFactor(factor!, command.policy);
        final locked =
            challengeFailures >= command.policy.maxAttempts ||
            factorResult.status == AuthTwoFactorCommandStatus.locked;
        return AuthTwoFactorCommandResult(
          locked
              ? AuthTwoFactorCommandStatus.locked
              : AuthTwoFactorCommandStatus.invalid,
          challenge: challenge,
        );
      }
      final trusted = command.trustedDevice;
      if (trusted != null && trusted.userId != challenge.userId) {
        return _conflict;
      }
      challengeStore._records[command.tokenHash] = challenge.copyWith(
        completedAt: now,
      );
      _fault(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);
      _clearFactorFailures(factor!, now);
      if (trusted != null) {
        trustedDeviceStore.create(trusted);
        _fault(AuthTwoFactorAtomicFaultPoint.afterTrustedDeviceWrite);
      }
      return AuthTwoFactorCommandResult(
        AuthTwoFactorCommandStatus.applied,
        challenge: challenge,
      );
    });
  }

  @override
  Future<AuthTwoFactorCommandResult> completeRecoveryChallenge(
    AuthTwoFactorCompleteRecoveryChallengeCommand command,
  ) async {
    final observed = challengeStore._records[command.tokenHash];
    if (observed == null) return _expired;
    return _atomic(observed.userId, () {
      final now = command.policy.now.toUtc();
      final challenge = challengeStore._records[command.tokenHash];
      if (challenge == null || !challenge.isActive(now: now)) return _expired;
      if (_challengeLocked(challenge, now)) {
        return AuthTwoFactorCommandResult(
          AuthTwoFactorCommandStatus.locked,
          challenge: challenge,
        );
      }
      final factor = factorStore._records[challenge.userId];
      if (factor == null || !factor.verified) return _expired;
      if (_isLocked(factor, now)) {
        return AuthTwoFactorCommandResult(
          AuthTwoFactorCommandStatus.locked,
          challenge: challenge,
        );
      }
      final remaining = List<String>.from(factor.recoveryCodeHashes);
      final index = remaining.indexWhere(
        (candidate) =>
            constantTimeStringEquals(candidate, command.recoveryCodeHash),
      );
      if (index < 0) {
        final challengeFailures = challenge.failedVerificationCount + 1;
        challengeStore._records[command.tokenHash] = challenge.copyWith(
          failedVerificationCount: challengeFailures,
          lockedUntil: challengeFailures >= command.policy.maxAttempts
              ? now.add(command.policy.lockoutDuration)
              : challenge.lockedUntil,
        );
        _fault(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);
        final factorResult = _failFactor(factor, command.policy);
        final locked =
            challengeFailures >= command.policy.maxAttempts ||
            factorResult.status == AuthTwoFactorCommandStatus.locked;
        return AuthTwoFactorCommandResult(
          locked
              ? AuthTwoFactorCommandStatus.locked
              : AuthTwoFactorCommandStatus.invalid,
          challenge: challenge,
        );
      }
      remaining.removeAt(index);
      factorStore._records[factor.userId] = factor.copyWith(
        recoveryCodeHashes: List<String>.unmodifiable(remaining),
        failedVerificationCount: 0,
        clearLockedUntil: true,
        updatedAt: now,
      );
      _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
      challengeStore._records[command.tokenHash] = challenge.copyWith(
        completedAt: now,
      );
      _fault(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);
      return AuthTwoFactorCommandResult(
        AuthTwoFactorCommandStatus.applied,
        challenge: challenge,
      );
    });
  }

  @override
  Future<AuthTwoFactorCommandResult> issueTrustedDevice(
    AuthTwoFactorIssueTrustedDeviceCommand command,
  ) => _atomic(command.expectedFactor.userId, () {
    final factor = factorStore._records[command.expectedFactor.userId];
    final checked = _checkVerifiedFactor(
      factor,
      command.expectedFactor,
      command.policy,
    );
    if (checked != null) return checked;
    if (!command.valid) return _failFactor(factor!, command.policy);
    if (command.trustedDevice.userId != factor!.userId) return _conflict;
    _clearFactorFailures(factor, command.policy.now);
    trustedDeviceStore.create(command.trustedDevice);
    _fault(AuthTwoFactorAtomicFaultPoint.afterTrustedDeviceWrite);
    return _applied;
  });

  @override
  Future<AuthTwoFactorCommandResult> verifyStepUp(
    AuthTwoFactorVerifyStepUpCommand command,
  ) => _atomic(command.expectedFactor.userId, () {
    final factor = factorStore._records[command.expectedFactor.userId];
    final checked = _checkVerifiedFactor(
      factor,
      command.expectedFactor,
      command.policy,
    );
    if (checked != null) return checked;
    if (!command.valid) return _failFactor(factor!, command.policy);
    if (command.proof.userId != factor!.userId) return _conflict;
    _clearFactorFailures(factor, command.policy.now);
    stepUpStore.create(command.proof);
    _fault(AuthTwoFactorAtomicFaultPoint.afterStepUpWrite);
    return _applied;
  });

  @override
  Future<void> revokeTrustedDevices(
    AuthTwoFactorRevokeTrustedDevicesCommand command,
  ) => _atomic(command.userId, () {
    trustedDeviceStore.revokeAll(command.userId, now: command.now.toUtc());
    _fault(AuthTwoFactorAtomicFaultPoint.afterTrustedDeviceWrite);
  });

  @override
  Future<void> revokeStepUp(AuthTwoFactorRevokeStepUpCommand command) =>
      _atomic(command.userId, () {
        stepUpStore.revokeAll(command.userId, command.sessionBindingHash);
        _fault(AuthTwoFactorAtomicFaultPoint.afterStepUpWrite);
      });

  @override
  Future<void> revokeAllStepUp(String userId) => _atomic(userId, () {
    stepUpStore.revokeAllForUser(userId);
    _fault(AuthTwoFactorAtomicFaultPoint.afterStepUpWrite);
  });

  AuthTwoFactorCommandResult? _checkVerifiedFactor(
    AuthTwoFactorRecord? current,
    AuthTwoFactorRecord expected,
    AuthTwoFactorAttemptPolicy policy,
  ) {
    if (current == null || !current.verified) return _notFound;
    if (!_sameFactorIdentity(current, expected)) return _conflict;
    if (_isLocked(current, policy.now.toUtc())) return _locked;
    return null;
  }

  AuthTwoFactorCommandResult _failFactor(
    AuthTwoFactorRecord record,
    AuthTwoFactorAttemptPolicy policy,
  ) {
    final failures = record.failedVerificationCount + 1;
    final locked = failures >= policy.maxAttempts;
    factorStore._records[record.userId] = record.copyWith(
      failedVerificationCount: failures,
      lockedUntil: locked
          ? policy.now.toUtc().add(policy.lockoutDuration)
          : record.lockedUntil,
      updatedAt: policy.now.toUtc(),
    );
    _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
    return locked ? _locked : _invalid;
  }

  void _clearFactorFailures(AuthTwoFactorRecord record, DateTime now) {
    factorStore._records[record.userId] = record.copyWith(
      failedVerificationCount: 0,
      clearLockedUntil: true,
      updatedAt: now.toUtc(),
    );
    _fault(AuthTwoFactorAtomicFaultPoint.afterFactorWrite);
  }

  bool _isLocked(AuthTwoFactorRecord record, DateTime now) =>
      record.lockedUntil != null && now.isBefore(record.lockedUntil!.toUtc());

  bool _challengeLocked(AuthTwoFactorChallengeRecord record, DateTime now) =>
      record.lockedUntil != null && now.isBefore(record.lockedUntil!.toUtc());

  Future<T> _atomic<T>(String userId, T Function() operation) async {
    _requireUserId(userId);
    final previous = _userTails[userId] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = release.future;
    _userTails[userId] = tail;
    await previous;
    final checkpoint = _captureState();
    try {
      return operation();
    } catch (_) {
      _restoreState(checkpoint);
      rethrow;
    } finally {
      release.complete();
      if (identical(_userTails[userId], tail)) _userTails.remove(userId);
    }
  }

  Object _captureState() => (
    factors: factorStore.captureDeletionState(),
    challenges: challengeStore.captureDeletionState(),
    trustedDevices: trustedDeviceStore.captureDeletionState(),
    stepUps: stepUpStore.captureDeletionState(),
  );

  void _restoreState(Object checkpoint) {
    final state =
        checkpoint
            as ({
              Object factors,
              Object challenges,
              Object trustedDevices,
              Object stepUps,
            });
    factorStore.restoreDeletionState(state.factors);
    challengeStore.restoreDeletionState(state.challenges);
    trustedDeviceStore.restoreDeletionState(state.trustedDevices);
    stepUpStore.restoreDeletionState(state.stepUps);
  }

  void _fault(AuthTwoFactorAtomicFaultPoint point) =>
      faultInjector?._check(point);
}

const AuthTwoFactorCommandResult _applied = AuthTwoFactorCommandResult(
  AuthTwoFactorCommandStatus.applied,
);
const AuthTwoFactorCommandResult _bypassed = AuthTwoFactorCommandResult(
  AuthTwoFactorCommandStatus.bypassed,
);
const AuthTwoFactorCommandResult _invalid = AuthTwoFactorCommandResult(
  AuthTwoFactorCommandStatus.invalid,
);
const AuthTwoFactorCommandResult _locked = AuthTwoFactorCommandResult(
  AuthTwoFactorCommandStatus.locked,
);
const AuthTwoFactorCommandResult _expired = AuthTwoFactorCommandResult(
  AuthTwoFactorCommandStatus.expired,
);
const AuthTwoFactorCommandResult _notFound = AuthTwoFactorCommandResult(
  AuthTwoFactorCommandStatus.notFound,
);
const AuthTwoFactorCommandResult _conflict = AuthTwoFactorCommandResult(
  AuthTwoFactorCommandStatus.conflict,
);

bool _sameFactorIdentity(AuthTwoFactorRecord left, AuthTwoFactorRecord right) =>
    left.userId == right.userId &&
    left.protectedSecret == right.protectedSecret &&
    left.enrollmentExpiresAt == right.enrollmentExpiresAt &&
    left.verified == right.verified;

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
        AuthHostEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthUserDeletionPlanContributor {
  TwoFactorPlugin({
    required this.backend,
    required this.secretProtector,
    this.issuer = 'server_auth',
    this.enrollmentTtl = const Duration(minutes: 10),
    this.period = 30,
    this.digits = 6,
    this.allowedClockSkew = 1,
    this.maxFailedVerificationAttempts = 5,
    this.lockoutDuration = const Duration(minutes: 15),
    this.challengeTtl = const Duration(minutes: 5),
    this.trustedDeviceTtl = const Duration(days: 30),
    this.trustedDeviceCookieName = 'two_factor_trusted_device',
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

  final AuthTwoFactorBackend backend;
  final AuthTwoFactorSecretProtector secretProtector;
  final String issuer;
  final Duration enrollmentTtl;
  final int period;
  final int digits;
  final int allowedClockSkew;
  final int maxFailedVerificationAttempts;
  final Duration lockoutDuration;
  final Duration challengeTtl;
  final Duration trustedDeviceTtl;
  final String trustedDeviceCookieName;
  final Duration stepUpTtl;
  final String stepUpCookieName;
  final List<int> Function(int length) _secretGenerator;
  late AuthUserDeletionDomain _deletionDomain;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError('TwoFactorPlugin requires a deletion-coordinator host.');
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
  }

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get hostEndpoints =>
      <AuthEndpointDescriptor<TContext>>[
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.status',
          method: AuthOperationMethod.get,
          path: const AuthRoutePath('/2fa/status'),
          requestSchema: _emptyObjectSchema,
          responseSchema: _twoFactorStatusSchema,
          protectMutation: false,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.enroll',
          path: const AuthRoutePath('/2fa/enroll'),
          requestSchema: _twoFactorEnrollRequestSchema,
          responseSchema: _twoFactorEnrollmentSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.enrollVerify',
          path: const AuthRoutePath('/2fa/enroll/verify'),
          requestSchema: _twoFactorCodeRequestSchema,
          responseSchema: _twoFactorRecoveryCodesSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.verify',
          path: const AuthRoutePath('/2fa/verify'),
          requestSchema: _twoFactorCodeRequestSchema,
          responseSchema: _twoFactorVerifiedSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.recoveryCode',
          path: const AuthRoutePath('/2fa/recovery-code'),
          requestSchema: _twoFactorRecoveryCodeRequestSchema,
          responseSchema: _twoFactorRecoveryVerifiedSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.recoveryCodesRegenerate',
          path: const AuthRoutePath('/2fa/recovery-codes/regenerate'),
          requestSchema: _twoFactorCodeRequestSchema,
          responseSchema: _twoFactorRecoveryCodesSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.disable',
          path: const AuthRoutePath('/2fa/disable'),
          requestSchema: _twoFactorCodeRequestSchema,
          responseSchema: _twoFactorDisabledSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.challengeVerify',
          path: const AuthRoutePath('/2fa/challenge/verify'),
          requestSchema: _twoFactorChallengeCodeRequestSchema,
          responseSchema: _authSessionResponseSchema,
          authentication: AuthOperationAuthentication.none,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.challengeRecoveryCode',
          path: const AuthRoutePath('/2fa/challenge/recovery-code'),
          requestSchema: _twoFactorChallengeRecoveryRequestSchema,
          responseSchema: _authSessionResponseSchema,
          authentication: AuthOperationAuthentication.none,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.trustedDevicesRevoke',
          path: const AuthRoutePath('/2fa/trusted-devices/revoke'),
          requestSchema: _emptyObjectSchema,
          responseSchema: _trustedDevicesRevokedSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.stepUp',
          path: const AuthRoutePath('/2fa/step-up'),
          requestSchema: _twoFactorCodeRequestSchema,
          responseSchema: _twoFactorStepUpSchema,
        ),
        _twoFactorHostEndpoint<TContext>(
          id: 'twoFactor.stepUpRevoke',
          path: const AuthRoutePath('/2fa/step-up/revoke'),
          requestSchema: _emptyObjectSchema,
          responseSchema: _twoFactorStepUpRevokedSchema,
        ),
      ];

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authTwoFactorPluginId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'two_factor',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'user_id', kind: 'string'),
            AuthFieldDescriptor(
              name: 'protected_secret',
              kind: 'secret_ciphertext',
            ),
            AuthFieldDescriptor(name: 'verified', kind: 'boolean'),
            AuthFieldDescriptor(
              name: 'recovery_code_hashes',
              kind: 'secret_digest[]',
            ),
            AuthFieldDescriptor(
              name: 'enrollment_expires_at',
              kind: 'timestamp',
            ),
            AuthFieldDescriptor(name: 'failed_attempts', kind: 'integer'),
            AuthFieldDescriptor(name: 'locked_until', kind: 'timestamp?'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(
              field: 'user_id',
              targetEntity: 'user',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: <List<String>>[
            <String>['user_id'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'two_factor_challenge',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'string'),
            AuthFieldDescriptor(name: 'token_hash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'user_id', kind: 'string'),
            AuthFieldDescriptor(name: 'expires_at', kind: 'timestamp'),
            AuthFieldDescriptor(name: 'failed_attempts', kind: 'integer'),
            AuthFieldDescriptor(name: 'locked_until', kind: 'timestamp?'),
            AuthFieldDescriptor(name: 'completed_at', kind: 'timestamp?'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(
              field: 'user_id',
              targetEntity: 'user',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: <List<String>>[
            <String>['id'],
            <String>['token_hash'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'two_factor_trusted_device',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'string'),
            AuthFieldDescriptor(name: 'user_id', kind: 'string'),
            AuthFieldDescriptor(name: 'token_hash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'expires_at', kind: 'timestamp'),
            AuthFieldDescriptor(name: 'last_used_at', kind: 'timestamp?'),
            AuthFieldDescriptor(name: 'revoked_at', kind: 'timestamp?'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(
              field: 'user_id',
              targetEntity: 'user',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: <List<String>>[
            <String>['id'],
            <String>['token_hash'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'two_factor_step_up',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'string'),
            AuthFieldDescriptor(name: 'user_id', kind: 'string'),
            AuthFieldDescriptor(
              name: 'session_binding_hash',
              kind: 'secret_digest',
            ),
            AuthFieldDescriptor(name: 'token_hash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'expires_at', kind: 'timestamp'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(
              field: 'user_id',
              targetEntity: 'user',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: <List<String>>[
            <String>['id'],
            <String>['token_hash'],
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'two_factor.begin_enrollment',
          description: 'Create or replace an unverified enrollment atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.verify_enrollment',
          description:
              'Verify enrollment state and install recovery digests atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.verify_totp',
          description:
              'Verify outcome and update bounded attempt state atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.use_recovery_code',
          description:
              'Consume one recovery digest or record its failed attempt atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.regenerate_recovery_codes',
          description:
              'Verify TOTP and replace every recovery digest atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.disable',
          description:
              'Remove the factor and revoke challenges, devices, and proofs atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.begin_challenge',
          description:
              'Touch a trusted device or create a pending challenge atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.complete_challenge',
          description:
              'Consume a TOTP challenge, update attempts, and trust a device atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.complete_recovery_challenge',
          description:
              'Consume a recovery digest and pending challenge atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.issue_trusted_device',
          description:
              'Verify TOTP and persist a hashed trusted-device token atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.revoke_trusted_devices',
          description: 'Revoke every trusted device for one user atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.verify_step_up',
          description:
              'Verify TOTP and persist a session-bound recent proof atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'two_factor.revoke_step_up',
          description: 'Revoke session-bound recent proofs atomically.',
        ),
      ],
    ),
  ];

  @override
  String get userDataNamespace => 'two_factor';

  @override
  Future<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user) async {
    if (_deletionDomain is! AuthInMemoryUserDeletionDomain ||
        backend is! InMemoryAuthTwoFactorBackend) {
      throw StateError('The two-factor adapter has no plan for this domain.');
    }
    return AuthInMemoryUserDeletionPlan(
      domain: _deletionDomain as AuthInMemoryUserDeletionDomain,
      userId: user.id,
      namespace: userDataNamespace,
      operation: _InMemoryTwoFactorDeletionOperation(
        userId: user.id,
        backend: backend as InMemoryAuthTwoFactorBackend,
      ),
    );
  }

  /// Starts a short-lived challenge for a user whose TOTP is enabled.
  Future<AuthTwoFactorSignInChallenge?> beginSignInChallenge(
    String userId, {
    String? trustedDeviceToken,
    AuthUser? user,
    String? providerId,
    AuthCredentials? credentials,
    DateTime? now,
  }) async {
    _requireUserId(userId);
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final token = secureRandomToken();
    final expiresAt = issuedAt.add(challengeTtl);
    final result = await backend.beginChallenge(
      AuthTwoFactorBeginChallengeCommand(
        userId: userId,
        trustedDeviceTokenHash:
            trustedDeviceToken == null || trustedDeviceToken.isEmpty
            ? null
            : hashOpaqueToken(trustedDeviceToken),
        now: issuedAt,
        challenge: AuthTwoFactorChallengeRecord(
          id: secureRandomToken(length: 16),
          tokenHash: hashOpaqueToken(token),
          userId: userId,
          createdAt: issuedAt,
          expiresAt: expiresAt,
          user: user,
          providerId: providerId,
          credentials: credentials?.redacted(),
        ),
      ),
    );
    switch (result.status) {
      case AuthTwoFactorCommandStatus.applied:
        return AuthTwoFactorSignInChallenge(token: token, expiresAt: expiresAt);
      case AuthTwoFactorCommandStatus.bypassed:
      case AuthTwoFactorCommandStatus.notFound:
        return null;
      case AuthTwoFactorCommandStatus.locked:
        throw AuthFlowException('two_factor_locked');
      case AuthTwoFactorCommandStatus.invalid:
      case AuthTwoFactorCommandStatus.expired:
      case AuthTwoFactorCommandStatus.conflict:
        throw AuthFlowException('two_factor_challenge_failed');
    }
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
    final challenge = await backend.challengeStore.findByTokenHash(tokenHash);
    if (challenge == null || !challenge.isActive(now: current)) {
      throw AuthFlowException('two_factor_invalid_challenge');
    }
    final factor = await backend.factorStore.findByUserId(challenge.userId);
    if (factor == null || !factor.verified) {
      throw AuthFlowException('two_factor_invalid_challenge');
    }
    final valid = _matchesTotp(factor, code, current);
    final rawTrustedToken = trustDevice ? secureRandomToken() : null;
    final trustedExpiresAt = current.add(trustedDeviceTtl);
    final result = await backend.completeChallenge(
      AuthTwoFactorCompleteChallengeCommand(
        tokenHash: tokenHash,
        expectedFactor: factor,
        valid: valid,
        policy: _policy(current),
        trustedDevice: rawTrustedToken == null
            ? null
            : AuthTwoFactorTrustedDeviceRecord(
                id: secureRandomToken(length: 16),
                userId: challenge.userId,
                tokenHash: hashOpaqueToken(rawTrustedToken),
                createdAt: current,
                expiresAt: trustedExpiresAt,
              ),
      ),
    );
    _requireAppliedChallenge(result, invalidCode: 'two_factor_invalid_code');
    final completed = result.challenge!;
    AuthTwoFactorTrustedDeviceToken? trustedDevice;
    if (rawTrustedToken != null) {
      trustedDevice = AuthTwoFactorTrustedDeviceToken(
        token: rawTrustedToken,
        expiresAt: trustedExpiresAt,
      );
    }
    return AuthTwoFactorSignInCompletion(
      userId: completed.userId,
      user: completed.user,
      providerId: completed.providerId,
      credentials: completed.credentials,
      trustedDevice: trustedDevice,
    );
  }

  /// Completes a pending credential sign-in with one recovery code.
  ///
  /// The backend consumes the recovery digest and challenge together. It does
  /// not issue a trusted-device token because that requires a fresh TOTP proof.
  Future<AuthTwoFactorSignInCompletion> completeRecoverySignInChallenge(
    String token,
    String recoveryCode, {
    DateTime? now,
  }) async {
    final tokenHash = hashOpaqueToken(token);
    final result = await backend.completeRecoveryChallenge(
      AuthTwoFactorCompleteRecoveryChallengeCommand(
        tokenHash: tokenHash,
        recoveryCodeHash: _hashRecoveryCode(recoveryCode),
        policy: _policy((now ?? DateTime.now()).toUtc()),
      ),
    );
    _requireAppliedChallenge(
      result,
      invalidCode: 'two_factor_invalid_recovery_code',
    );
    final challenge = result.challenge!;
    return AuthTwoFactorSignInCompletion(
      userId: challenge.userId,
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
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final factor = await _requireRecord(userId);
    final token = secureRandomToken();
    final expiresAt = issuedAt.add(trustedDeviceTtl);
    final result = await backend.issueTrustedDevice(
      AuthTwoFactorIssueTrustedDeviceCommand(
        expectedFactor: factor,
        valid: _matchesTotp(factor, code, issuedAt),
        policy: _policy(issuedAt),
        trustedDevice: AuthTwoFactorTrustedDeviceRecord(
          id: secureRandomToken(length: 16),
          userId: userId,
          tokenHash: hashOpaqueToken(token),
          createdAt: issuedAt,
          expiresAt: expiresAt,
        ),
      ),
    );
    _requireAppliedFactor(result, invalidCode: 'two_factor_invalid_code');
    return AuthTwoFactorTrustedDeviceToken(token: token, expiresAt: expiresAt);
  }

  /// Revokes every trusted device for [userId].
  Future<void> revokeAllTrustedDevices(String userId, {DateTime? now}) async {
    _requireUserId(userId);
    await backend.revokeTrustedDevices(
      AuthTwoFactorRevokeTrustedDevicesCommand(
        userId: userId,
        now: (now ?? DateTime.now()).toUtc(),
      ),
    );
  }

  /// Starts or replaces an unverified enrollment for [userId].
  Future<AuthTwoFactorEnrollment> beginEnrollment(
    String userId, {
    String? accountLabel,
    DateTime? now,
  }) async {
    _requireUserId(userId);
    final existing = await backend.factorStore.findByUserId(userId);
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
    final result = await backend.beginEnrollment(
      AuthTwoFactorBeginEnrollmentCommand(
        AuthTwoFactorRecord(
          userId: userId,
          protectedSecret: secretProtector.protect(secret),
          enrollmentExpiresAt: expiresAt,
          updatedAt: issuedAt,
        ),
      ),
    );
    if (result.status != AuthTwoFactorCommandStatus.applied) {
      throw AuthFlowException('two_factor_already_enabled');
    }
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
    final valid = _matchesTotp(record, code, current);
    final recovery = valid
        ? _newRecoveryCodes()
        : const AuthTwoFactorRecoveryCodes(<String>[]);
    final result = await backend.verifyEnrollment(
      AuthTwoFactorVerifyEnrollmentCommand(
        expected: record,
        valid: valid,
        recoveryCodeHashes: recovery.codes.map(_hashRecoveryCode).toList(),
        policy: _policy(current),
      ),
    );
    if (result.status == AuthTwoFactorCommandStatus.conflict) {
      throw AuthFlowException('two_factor_enrollment_changed');
    }
    _requireAppliedFactor(result, invalidCode: 'two_factor_invalid_code');
    return recovery;
  }

  /// Returns the current public status for [userId].
  Future<AuthTwoFactorStatus> status(String userId, {DateTime? now}) async {
    final record = await backend.factorStore.findByUserId(userId);
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
    final result = await backend.verifyTotp(
      AuthTwoFactorVerifyTotpCommand(
        expected: record,
        valid: _matchesTotp(record, code, current),
        policy: _policy(current),
      ),
    );
    _requireAppliedFactor(result, invalidCode: 'two_factor_invalid_code');
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
    _requireSessionBinding(sessionBinding);
    final current = (now ?? DateTime.now()).toUtc();
    final record = await _requireRecord(userId);
    final token = secureRandomToken();
    final expiresAt = current.add(stepUpTtl);
    final result = await backend.verifyStepUp(
      AuthTwoFactorVerifyStepUpCommand(
        expectedFactor: record,
        valid: _matchesTotp(record, code, current),
        policy: _policy(current),
        proof: AuthTwoFactorStepUpRecord(
          id: secureRandomToken(length: 16),
          userId: userId,
          sessionBindingHash: hashOpaqueToken(sessionBinding),
          tokenHash: hashOpaqueToken(token),
          createdAt: current,
          expiresAt: expiresAt,
        ),
      ),
    );
    _requireAppliedFactor(result, invalidCode: 'two_factor_invalid_code');
    return AuthTwoFactorStepUpToken(token: token, expiresAt: expiresAt);
  }

  /// Returns whether [token] is a current step-up proof for this session.
  Future<bool> isStepUpValid(
    String userId,
    String sessionBinding,
    String token, {
    DateTime? now,
  }) async {
    if (sessionBinding.trim().isEmpty || token.trim().isEmpty) {
      return false;
    }
    final record = await backend.stepUpStore.findActive(
      userId,
      hashOpaqueToken(sessionBinding),
      hashOpaqueToken(token),
      now: (now ?? DateTime.now()).toUtc(),
    );
    return record != null;
  }

  /// Revokes all step-up proofs for the current user/session binding.
  Future<void> revokeStepUp(String userId, String sessionBinding) async {
    _requireSessionBinding(sessionBinding);
    await backend.revokeStepUp(
      AuthTwoFactorRevokeStepUpCommand(
        userId: userId,
        sessionBindingHash: hashOpaqueToken(sessionBinding),
      ),
    );
  }

  /// Revokes every step-up proof issued for [userId].
  Future<void> revokeAllStepUpProofs(String userId) async {
    _requireUserId(userId);
    await backend.revokeAllStepUp(userId);
  }

  /// Consumes one recovery code for [userId].
  Future<void> useRecoveryCode(
    String userId,
    String code, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    await _requireRecord(userId);
    final result = await backend.useRecoveryCode(
      AuthTwoFactorUseRecoveryCodeCommand(
        userId: userId,
        recoveryCodeHash: _hashRecoveryCode(code),
        policy: _policy(current),
      ),
    );
    _requireAppliedFactor(
      result,
      invalidCode: 'two_factor_invalid_recovery_code',
    );
  }

  /// Replaces all recovery codes after verifying the current TOTP code.
  Future<AuthTwoFactorRecoveryCodes> regenerateRecoveryCodes(
    String userId,
    String code, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final record = await _requireRecord(userId);
    final valid = _matchesTotp(record, code, current);
    final recovery = valid
        ? _newRecoveryCodes()
        : const AuthTwoFactorRecoveryCodes(<String>[]);
    final result = await backend.regenerateRecoveryCodes(
      AuthTwoFactorRegenerateRecoveryCodesCommand(
        expected: record,
        valid: valid,
        recoveryCodeHashes: recovery.codes.map(_hashRecoveryCode).toList(),
        policy: _policy(current),
      ),
    );
    if (result.status == AuthTwoFactorCommandStatus.conflict) {
      throw AuthFlowException('two_factor_state_changed');
    }
    _requireAppliedFactor(result, invalidCode: 'two_factor_invalid_code');
    return recovery;
  }

  /// Disables two-factor authentication after verifying the current TOTP code.
  Future<void> disable(String userId, String code, {DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    final record = await _requireRecord(userId);
    final result = await backend.disable(
      AuthTwoFactorDisableCommand(
        expected: record,
        valid: _matchesTotp(record, code, current),
        policy: _policy(current),
      ),
    );
    if (result.status == AuthTwoFactorCommandStatus.conflict) {
      throw AuthFlowException('two_factor_state_changed');
    }
    _requireAppliedFactor(result, invalidCode: 'two_factor_invalid_code');
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
    final record = await backend.factorStore.findByUserId(userId);
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

  AuthTwoFactorAttemptPolicy _policy(DateTime now) {
    return AuthTwoFactorAttemptPolicy(
      now: now.toUtc(),
      maxAttempts: maxFailedVerificationAttempts,
      lockoutDuration: lockoutDuration,
    );
  }

  void _requireAppliedFactor(
    AuthTwoFactorCommandResult result, {
    required String invalidCode,
  }) {
    switch (result.status) {
      case AuthTwoFactorCommandStatus.applied:
        return;
      case AuthTwoFactorCommandStatus.locked:
        throw AuthFlowException('two_factor_locked');
      case AuthTwoFactorCommandStatus.expired:
        throw AuthFlowException('two_factor_enrollment_expired');
      case AuthTwoFactorCommandStatus.notFound:
        throw AuthFlowException('two_factor_not_enabled');
      case AuthTwoFactorCommandStatus.invalid:
        throw AuthFlowException(invalidCode);
      case AuthTwoFactorCommandStatus.conflict:
        throw AuthFlowException('two_factor_state_changed');
      case AuthTwoFactorCommandStatus.bypassed:
        throw AuthFlowException(invalidCode);
    }
  }

  void _requireAppliedChallenge(
    AuthTwoFactorCommandResult result, {
    required String invalidCode,
  }) {
    switch (result.status) {
      case AuthTwoFactorCommandStatus.applied:
        if (result.challenge == null) {
          throw AuthFlowException('two_factor_invalid_challenge');
        }
        return;
      case AuthTwoFactorCommandStatus.locked:
        throw AuthFlowException('two_factor_challenge_locked');
      case AuthTwoFactorCommandStatus.invalid:
        throw AuthFlowException(invalidCode);
      case AuthTwoFactorCommandStatus.bypassed:
      case AuthTwoFactorCommandStatus.expired:
      case AuthTwoFactorCommandStatus.notFound:
      case AuthTwoFactorCommandStatus.conflict:
        throw AuthFlowException('two_factor_invalid_challenge');
    }
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

final class _InMemoryTwoFactorDeletionOperation
    implements AuthInMemoryUserDeletionOperation {
  _InMemoryTwoFactorDeletionOperation({
    required this.userId,
    required this.backend,
  });

  final String userId;
  final InMemoryAuthTwoFactorBackend backend;

  @override
  Object captureState() => backend.captureDeletionState();

  @override
  void apply() {
    backend.factorStore._records.remove(userId);
    backend.trustedDeviceStore._records.removeWhere(
      (_, record) => record.userId == userId,
    );
    backend.challengeStore._records.removeWhere(
      (_, record) => record.userId == userId,
    );
    backend.stepUpStore._records.removeWhere(
      (_, record) => record.userId == userId,
    );
  }

  @override
  void restoreState(Object state) => backend.restoreDeletionState(state);
}

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

AuthEndpointDescriptor<TContext> _twoFactorHostEndpoint<TContext>({
  required String id,
  AuthOperationMethod method = AuthOperationMethod.post,
  required AuthRoutePath path,
  required Map<String, Object?> requestSchema,
  required Map<String, Object?> responseSchema,
  AuthOperationAuthentication authentication =
      AuthOperationAuthentication.session,
  bool protectMutation = true,
}) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
  id: id,
  method: method,
  path: path,
  semantics: _twoFactorOperationSemantics(id),
  requestCodec: AuthOperationCodec<Map<String, dynamic>>(
    decode: _decodeTwoFactorMap,
    encode: _encodeTwoFactorMap,
    schema: requestSchema,
    required: requestSchema['required'] is List,
  ),
  responseCodec: AuthOperationCodec<Object?>(
    decode: _decodeTwoFactorObject,
    encode: _encodeTwoFactorObject,
    schema: responseSchema,
  ),
  authentication: authentication,
  originPolicy: protectMutation
      ? AuthOperationOriginPolicy.browser
      : AuthOperationOriginPolicy.none,
  csrfPolicy: protectMutation
      ? AuthOperationCsrfPolicy.required
      : AuthOperationCsrfPolicy.none,
  rateLimitOperation: protectMutation
      ? const AuthRateLimitOperation('core', 'twoFactor')
      : null,
  handler: (invocation, request) =>
      throw UnsupportedError('This endpoint is implemented by the auth host.'),
);

AuthOperationSemantics _twoFactorOperationSemantics(String id) {
  switch (id) {
    case 'twoFactor.status':
      return const AuthOperationSemantics.readOnly();
    case 'twoFactor.stepUp':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.boundedEphemeral(),
        replaySafety: AuthMutationReplaySafety.repeatable,
      );
    case 'twoFactor.stepUpRevoke':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.boundedEphemeral(),
        replaySafety: AuthMutationReplaySafety.idempotent,
      );
    case 'twoFactor.challengeVerify':
    case 'twoFactor.challengeRecoveryCode':
      return const AuthOperationSemantics.mutation(
        // The two-factor command commits before the host issues its session
        // and cookies, so the public endpoint is not end-to-end atomic.
        persistence: AuthMutationPersistence.session(),
        replaySafety: AuthMutationReplaySafety.singleUse,
      );
    case 'twoFactor.enroll':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authTwoFactorPluginId,
            atomicOperationId: 'two_factor.begin_enrollment',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.repeatable,
      );
    case 'twoFactor.trustedDevicesRevoke':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authTwoFactorPluginId,
            atomicOperationId: 'two_factor.revoke_trusted_devices',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.idempotent,
      );
    case 'twoFactor.enrollVerify':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authTwoFactorPluginId,
            atomicOperationId: 'two_factor.verify_enrollment',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.singleUse,
      );
    case 'twoFactor.recoveryCode':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authTwoFactorPluginId,
            atomicOperationId: 'two_factor.use_recovery_code',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.singleUse,
      );
    case 'twoFactor.disable':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authTwoFactorPluginId,
            atomicOperationId: 'two_factor.disable',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.singleUse,
      );
    case 'twoFactor.verify':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authTwoFactorPluginId,
            atomicOperationId: 'two_factor.verify_totp',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.repeatable,
      );
    case 'twoFactor.recoveryCodesRegenerate':
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authTwoFactorPluginId,
            atomicOperationId: 'two_factor.regenerate_recovery_codes',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.repeatable,
      );
  }
  throw StateError('Unknown two-factor operation $id');
}

Map<String, dynamic> _decodeTwoFactorMap(Map<String, dynamic> value) => value;
Object? _encodeTwoFactorMap(Map<String, dynamic> value) => value;
Object? _decodeTwoFactorObject(Map<String, dynamic> value) => value;
Object? _encodeTwoFactorObject(Object? value) => value;

const Map<String, Object?> _emptyObjectSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
};

const Map<String, Object?> _twoFactorStatusSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['enabled', 'recoveryCodesRemaining'],
  'properties': <String, Object?>{
    'enabled': <String, Object?>{'type': 'boolean'},
    'recoveryCodesRemaining': <String, Object?>{
      'type': 'integer',
      'minimum': 0,
    },
    'enrollmentExpiresAt': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
    'lockedUntil': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
  },
};

const Map<String, Object?> _twoFactorEnrollRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': <String, Object?>{
    'accountLabel': <String, Object?>{'type': 'string'},
  },
};

const Map<String, Object?> _twoFactorEnrollmentSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['secret', 'otpauthUri', 'expiresAt'],
  'properties': <String, Object?>{
    'secret': <String, Object?>{'type': 'string', 'readOnly': true},
    'otpauthUri': <String, Object?>{'type': 'string', 'format': 'uri'},
    'expiresAt': <String, Object?>{'type': 'string', 'format': 'date-time'},
  },
};

const Map<String, Object?> _twoFactorCodeRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['code'],
  'properties': <String, Object?>{
    'code': <String, Object?>{'type': 'string', 'writeOnly': true},
  },
};

const Map<String, Object?> _twoFactorRecoveryCodeRequestSchema =
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['recoveryCode'],
      'properties': <String, Object?>{
        'recoveryCode': <String, Object?>{'type': 'string', 'writeOnly': true},
      },
    };

const Map<String, Object?> _twoFactorRecoveryCodesSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['recoveryCodes'],
  'properties': <String, Object?>{
    'enabled': <String, Object?>{'type': 'boolean'},
    'recoveryCodes': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string', 'readOnly': true},
    },
  },
};

const Map<String, Object?> _twoFactorVerifiedSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['verified'],
  'properties': <String, Object?>{
    'verified': <String, Object?>{'const': true},
  },
};

const Map<String, Object?> _twoFactorRecoveryVerifiedSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['verified', 'method'],
  'properties': <String, Object?>{
    'verified': <String, Object?>{'const': true},
    'method': <String, Object?>{'const': 'recovery_code'},
  },
};

const Map<String, Object?> _twoFactorDisabledSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['disabled'],
  'properties': <String, Object?>{
    'disabled': <String, Object?>{'const': true},
  },
};

const Map<String, Object?> _twoFactorChallengeCodeRequestSchema =
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['challengeToken', 'code'],
      'properties': <String, Object?>{
        'challengeToken': <String, Object?>{
          'type': 'string',
          'writeOnly': true,
        },
        'code': <String, Object?>{'type': 'string', 'writeOnly': true},
        'trustDevice': <String, Object?>{'type': 'boolean'},
      },
    };

const Map<String, Object?> _twoFactorChallengeRecoveryRequestSchema =
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['challengeToken', 'recoveryCode'],
      'properties': <String, Object?>{
        'challengeToken': <String, Object?>{
          'type': 'string',
          'writeOnly': true,
        },
        'recoveryCode': <String, Object?>{'type': 'string', 'writeOnly': true},
      },
    };

const Map<String, Object?> _authSessionResponseSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
  'required': <String>['user', 'strategy'],
  'properties': <String, Object?>{
    'user': <String, Object?>{'type': 'object'},
    'expires': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
    'strategy': <String, Object?>{'type': 'string'},
    'token': <String, Object?>{
      'type': 'string',
      'readOnly': true,
      'description': 'Present only when JWT response-body exposure is enabled.',
    },
  },
};

const Map<String, Object?> _trustedDevicesRevokedSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['status'],
  'properties': <String, Object?>{
    'status': <String, Object?>{'const': 'trusted_devices_revoked'},
  },
};

const Map<String, Object?> _twoFactorStepUpSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['verified', 'expiresAt'],
  'properties': <String, Object?>{
    'verified': <String, Object?>{'const': true},
    'expiresAt': <String, Object?>{'type': 'string', 'format': 'date-time'},
  },
};

const Map<String, Object?> _twoFactorStepUpRevokedSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['status'],
  'properties': <String, Object?>{
    'status': <String, Object?>{'const': 'step_up_revoked'},
  },
};
