import 'dart:async';

import 'deletion_transaction.dart';
import 'tokens.dart' show hashOpaqueToken;

/// Supported one-time-password purposes.
enum AuthEmailOtpType { signIn, emailVerification, forgetPassword, changeEmail }

/// A persisted email OTP transaction.
final class AuthEmailOtp {
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

  final String id;
  final String email;
  final String codeHash;
  final AuthEmailOtpType type;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxAttempts;
  final int attempts;
  final bool consumed;

  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

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

enum AuthEmailOtpVerificationStatus {
  verified,
  invalid,
  expired,
  tooManyAttempts,
}

final class AuthEmailOtpVerificationResult {
  const AuthEmailOtpVerificationResult(this.status, [this.otp]);

  final AuthEmailOtpVerificationStatus status;
  final AuthEmailOtp? otp;
}

/// Typed persistence boundary for email OTP records.
abstract interface class AuthEmailOtpStore {
  FutureOr<void> save(AuthEmailOtp otp);

  FutureOr<AuthEmailOtpVerificationResult> verify(
    String email,
    AuthEmailOtpType type,
    String code, {
    DateTime? now,
  });

  FutureOr<void> deleteForEmail(String email);
}

/// In-memory OTP store for tests and local development.
final class InMemoryAuthEmailOtpStore
    implements AuthEmailOtpStore, AuthInMemoryDeletionState {
  InMemoryAuthEmailOtpStore({this.maxEntries = 2048}) : assert(maxEntries > 0);

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
  Future<AuthEmailOtpVerificationResult> verify(
    String email,
    AuthEmailOtpType type,
    String code, {
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
    final candidate = hashAuthEmailOtpCode(code);
    if (candidate != existing.codeHash) {
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

String hashAuthEmailOtpCode(String code) => hashOpaqueToken(code.trim());

String normalizeAuthEmailOtpEmail(String email) => _normalizeEmail(email);

String _normalizeEmail(String email) => email.trim().toLowerCase();

void _validate(AuthEmailOtp otp) {
  if (otp.id.trim().isEmpty ||
      _normalizeEmail(otp.email).isEmpty ||
      otp.codeHash.trim().isEmpty ||
      otp.maxAttempts <= 0 ||
      otp.attempts < 0 ||
      otp.attempts > otp.maxAttempts ||
      !otp.expiresAt.toUtc().isAfter(otp.createdAt.toUtc())) {
    throw ArgumentError('Invalid email OTP');
  }
}
