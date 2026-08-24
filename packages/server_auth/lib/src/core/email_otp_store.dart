import 'dart:async';

import 'deletion_transaction.dart';
import 'tokens.dart' show constantTimeStringEquals;

/// Supported one-time-password purposes.
enum AuthEmailOtpType {
  /// OTP used to authenticate a sign-in attempt.
  signIn,

  /// OTP used to verify an email address.
  emailVerification,

  /// OTP used in a password-recovery flow.
  forgetPassword,

  /// OTP used to confirm an email change.
  changeEmail,
}

/// A persisted email OTP transaction.
final class AuthEmailOtp {
  /// Creates a persisted digest-only OTP record.
  ///
  /// [createdAt] and [expiresAt] are compared in UTC. The raw OTP must never
  /// be supplied in place of [codeHash].
  AuthEmailOtp({
    required this.id,
    required this.email,
    required this.codeHash,
    required this.type,
    required this.createdAt,
    required this.expiresAt,
    required this.maxAttempts,
    this.attempts = 0,
    this.consumed = false,
  });

  /// Stable persistence identifier.
  final String id;

  /// Canonical email address associated with the record.
  final String email;

  /// Application-keyed digest of the OTP.
  final String codeHash;

  /// Flow purpose that partitions records for this email.
  final AuthEmailOtpType type;

  /// UTC time at which the record was created.
  final DateTime createdAt;

  /// UTC deadline at which the record expires.
  final DateTime expiresAt;

  /// Maximum number of verification attempts.
  final int maxAttempts;

  /// Number of attempts already recorded.
  final int attempts;

  /// Whether a successful verification has consumed this record.
  final bool consumed;

  /// Whether [now] is at or after [expiresAt].
  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

  /// Returns a copy with updated attempt or consumption state.
  AuthEmailOtp copyWith({int? attempts, bool? consumed}) => AuthEmailOtp(
    id: id,
    email: email,
    codeHash: codeHash,
    type: type,
    createdAt: createdAt,
    expiresAt: expiresAt,
    maxAttempts: maxAttempts,
    attempts: attempts ?? this.attempts,
    consumed: consumed ?? this.consumed,
  );

  /// Serializes persistence metadata without a raw OTP.
  Map<String, dynamic> toStorageJson() => <String, dynamic>{
    'id': id,
    'email': email,
    'code_hash': codeHash,
    'type': type.name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'max_attempts': maxAttempts,
    'attempts': attempts,
    'consumed': consumed,
  };
}

/// Outcome of comparing an OTP digest with a stored record.
enum AuthEmailOtpVerificationStatus {
  /// The digest matched and the record was consumed.
  verified,

  /// The digest did not match or no usable record exists.
  invalid,

  /// The record reached its expiry deadline.
  expired,

  /// The record has no attempts remaining.
  tooManyAttempts,
}

/// Result of an OTP verification attempt.
final class AuthEmailOtpVerificationResult {
  /// Creates a verification result with optional record state.
  const AuthEmailOtpVerificationResult(this.status, [this.otp]);

  /// Outcome of the comparison and state transition.
  final AuthEmailOtpVerificationStatus status;

  /// Record state associated with non-missing outcomes.
  final AuthEmailOtp? otp;
}

/// Typed persistence boundary for email OTP records.
abstract interface class AuthEmailOtpStore {
  /// Saves or replaces the active record for an email and purpose.
  ///
  /// Implementations must retain only [AuthEmailOtp.codeHash], not a raw OTP,
  /// and must reject invalid or expired records.
  FutureOr<void> save(AuthEmailOtp otp);

  /// Compares an application-keyed digest and atomically records the attempt.
  ///
  /// Raw OTP values must be digested before this persistence boundary.
  FutureOr<AuthEmailOtpVerificationResult> verifyDigest(
    String email,
    AuthEmailOtpType type,
    String codeHash, {
    DateTime? now,
  });

  /// Deletes every OTP record associated with [email].
  FutureOr<void> deleteForEmail(String email);
}

/// In-memory OTP store for tests and local development.
final class InMemoryAuthEmailOtpStore
    implements AuthEmailOtpStore, AuthInMemoryDeletionState {
  /// Creates a bounded in-memory store for tests and local development.
  ///
  /// Expired entries are pruned on save and the oldest entry is evicted when
  /// [maxEntries] is reached.
  InMemoryAuthEmailOtpStore({this.maxEntries = 2048}) : assert(maxEntries > 0);

  /// Maximum number of active records retained by this store.
  final int maxEntries;
  final Map<String, AuthEmailOtp> _records = <String, AuthEmailOtp>{};

  @override
  Object captureDeletionState() => Map<String, AuthEmailOtp>.of(_records);

  @override
  void restoreDeletionState(Object checkpoint) {
    final records = checkpoint as Map<String, AuthEmailOtp>;
    _records
      ..clear()
      ..addAll(records);
  }

  /// Validates and stores [otp], replacing the same email/purpose record.
  @override
  Future<void> save(AuthEmailOtp otp) async {
    _validate(otp);
    _removeExpired(DateTime.now().toUtc());
    while (_records.length >= maxEntries &&
        !_records.containsKey(_key(otp.email, otp.type))) {
      _records.remove(_records.keys.first);
    }
    _records[_key(otp.email, otp.type)] = otp;
  }

  @override
  Future<AuthEmailOtpVerificationResult> verifyDigest(
    String email,
    AuthEmailOtpType type,
    String codeHash, {
    DateTime? now,
  }) async {
    final key = _key(email, type);
    final existing = _records[key];
    final current = (now ?? DateTime.now()).toUtc();
    if (existing == null || existing.consumed) {
      return const AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.invalid,
      );
    }
    if (existing.isExpired(now: current)) {
      return AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.expired,
        existing,
      );
    }
    if (existing.attempts >= existing.maxAttempts) {
      return AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.tooManyAttempts,
        existing,
      );
    }
    if (!constantTimeStringEquals(codeHash, existing.codeHash)) {
      final attempts = existing.attempts + 1;
      final updated = existing.copyWith(attempts: attempts);
      _records[key] = updated;
      return AuthEmailOtpVerificationResult(
        attempts >= existing.maxAttempts
            ? AuthEmailOtpVerificationStatus.tooManyAttempts
            : AuthEmailOtpVerificationStatus.invalid,
        updated,
      );
    }
    final consumed = existing.copyWith(
      attempts: existing.attempts + 1,
      consumed: true,
    );
    _records[key] = consumed;
    return AuthEmailOtpVerificationResult(
      AuthEmailOtpVerificationStatus.verified,
      consumed,
    );
  }

  /// Deletes all records whose canonical email equals [email].
  @override
  Future<void> deleteForEmail(String email) async {
    final normalized = _normalizeEmail(email);
    if (normalized.isEmpty) return;
    _records.removeWhere((_, value) => value.email == normalized);
  }

  static String _key(String email, AuthEmailOtpType type) =>
      '${_normalizeEmail(email)}:${type.name}';

  void _removeExpired(DateTime now) {
    _records.removeWhere((_, value) => value.isExpired(now: now));
  }
}

/// Normalizes an OTP storage key without full email-address validation.
///
/// This helper trims and lowercases [email]; authentication flows should use
/// the stricter email validator when accepting an address from a user.
String normalizeAuthEmailOtpEmail(String email) => _normalizeEmail(email);

String _normalizeEmail(String email) => email.trim().toLowerCase();

void _validate(AuthEmailOtp otp) {
  if (otp.id.trim().isEmpty ||
      _normalizeEmail(otp.email).isEmpty ||
      otp.email != _normalizeEmail(otp.email) ||
      otp.codeHash.length != 64 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(otp.codeHash) ||
      otp.maxAttempts <= 0 ||
      otp.attempts < 0 ||
      otp.attempts > otp.maxAttempts ||
      !otp.expiresAt.toUtc().isAfter(otp.createdAt.toUtc())) {
    throw ArgumentError('Invalid email OTP');
  }
}
