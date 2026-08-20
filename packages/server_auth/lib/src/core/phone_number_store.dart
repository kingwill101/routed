import 'dart:async';

import 'deletion_transaction.dart';
import 'tokens.dart' show constantTimeStringEquals;

/// A verified E.164 phone number linked to one auth user.
final class AuthPhoneNumberIdentity {
  const AuthPhoneNumberIdentity({
    required this.phoneNumber,
    required this.userId,
    required this.createdAt,
    required this.verifiedAt,
  });

  final String phoneNumber;
  final String userId;
  final DateTime createdAt;
  final DateTime verifiedAt;

  Map<String, dynamic> toStorageJson() => <String, dynamic>{
    'phone_number': phoneNumber,
    'user_id': userId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'verified_at': verifiedAt.toUtc().toIso8601String(),
  };
}

/// A persisted phone verification challenge.
///
/// [codeDigest] is a keyed digest. The raw verification code must only be
/// supplied to the delivery provider and must never cross this store boundary.
final class AuthPhoneNumberVerification {
  const AuthPhoneNumberVerification({
    required this.id,
    required this.phoneNumber,
    required this.codeDigest,
    required this.createdAt,
    required this.expiresAt,
    required this.maxAttempts,
    this.attempts = 0,
    this.consumedAt,
  });

  final String id;
  final String phoneNumber;
  final String codeDigest;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxAttempts;
  final int attempts;
  final DateTime? consumedAt;

  bool get isConsumed => consumedAt != null;

  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

  AuthPhoneNumberVerification copyWith({int? attempts, DateTime? consumedAt}) =>
      AuthPhoneNumberVerification(
        id: id,
        phoneNumber: phoneNumber,
        codeDigest: codeDigest,
        createdAt: createdAt,
        expiresAt: expiresAt,
        maxAttempts: maxAttempts,
        attempts: attempts ?? this.attempts,
        consumedAt: consumedAt ?? this.consumedAt,
      );

  Map<String, dynamic> toStorageJson() => <String, dynamic>{
    'id': id,
    'phone_number': phoneNumber,
    'code_digest': codeDigest,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'max_attempts': maxAttempts,
    'attempts': attempts,
    'consumed_at': consumedAt?.toUtc().toIso8601String(),
  };
}

enum AuthPhoneNumberVerificationStatus {
  verified,
  invalid,
  expired,
  tooManyAttempts,
}

final class AuthPhoneNumberVerificationResult {
  const AuthPhoneNumberVerificationResult(this.status, [this.verification]);

  final AuthPhoneNumberVerificationStatus status;
  final AuthPhoneNumberVerification? verification;
}

/// Plugin-owned durable persistence for phone identities and challenges.
///
/// Durable implementations must make [consumeVerification] atomic. Exactly one
/// concurrent caller may receive [AuthPhoneNumberVerificationStatus.verified]
/// for a challenge. [bindIdentity] must enforce unique phone-number ownership.
abstract interface class AuthPhoneNumberStore {
  FutureOr<void> saveVerification(AuthPhoneNumberVerification verification);

  FutureOr<AuthPhoneNumberVerificationResult> consumeVerification(
    String phoneNumber,
    String codeDigest, {
    DateTime? now,
  });

  /// Removes [verificationId] only if it is still the active challenge.
  FutureOr<bool> deleteVerificationIfCurrent(
    String phoneNumber,
    String verificationId,
  );

  FutureOr<AuthPhoneNumberIdentity?> findIdentity(String phoneNumber);

  /// Finds the verified phone identity currently owned by [userId].
  FutureOr<AuthPhoneNumberIdentity?> findIdentityForUser(String userId);

  /// Binds a phone number, returning the canonical identity if already bound.
  FutureOr<AuthPhoneNumberIdentity> bindIdentity(
    AuthPhoneNumberIdentity identity,
  );

  FutureOr<void> deleteForUser(String userId);
}

/// Bounded process-local phone store for tests and local development.
final class InMemoryAuthPhoneNumberStore
    implements AuthPhoneNumberStore, AuthInMemoryUserDeletionStore {
  InMemoryAuthPhoneNumberStore({this.maxVerifications = 2048}) {
    if (maxVerifications <= 0) {
      throw ArgumentError.value(
        maxVerifications,
        'maxVerifications',
        'must be greater than zero',
      );
    }
  }

  final int maxVerifications;
  final Map<String, AuthPhoneNumberVerification> _verifications =
      <String, AuthPhoneNumberVerification>{};
  final Map<String, AuthPhoneNumberIdentity> _identitiesByPhone =
      <String, AuthPhoneNumberIdentity>{};
  final Map<String, String> _phoneByUser = <String, String>{};

  @override
  Object captureDeletionState() => _PhoneNumberStoreCheckpoint(
    verifications: Map<String, AuthPhoneNumberVerification>.of(_verifications),
    identitiesByPhone: Map<String, AuthPhoneNumberIdentity>.of(
      _identitiesByPhone,
    ),
    phoneByUser: Map<String, String>.of(_phoneByUser),
  );

  @override
  void restoreDeletionState(Object checkpoint) {
    final state = checkpoint as _PhoneNumberStoreCheckpoint;
    _verifications
      ..clear()
      ..addAll(state.verifications);
    _identitiesByPhone
      ..clear()
      ..addAll(state.identitiesByPhone);
    _phoneByUser
      ..clear()
      ..addAll(state.phoneByUser);
  }

  @override
  Future<void> saveVerification(
    AuthPhoneNumberVerification verification,
  ) async {
    _validateVerification(verification);
    _removeExpired(DateTime.now().toUtc());
    while (_verifications.length >= maxVerifications &&
        !_verifications.containsKey(verification.phoneNumber)) {
      _verifications.remove(_verifications.keys.first);
    }
    _verifications[verification.phoneNumber] = verification;
  }

  @override
  Future<AuthPhoneNumberVerificationResult> consumeVerification(
    String phoneNumber,
    String codeDigest, {
    DateTime? now,
  }) async {
    final existing = _verifications[phoneNumber];
    final current = (now ?? DateTime.now()).toUtc();
    if (existing == null || existing.isConsumed) {
      return const AuthPhoneNumberVerificationResult(
        AuthPhoneNumberVerificationStatus.invalid,
      );
    }
    if (existing.isExpired(now: current)) {
      return AuthPhoneNumberVerificationResult(
        AuthPhoneNumberVerificationStatus.expired,
        existing,
      );
    }
    if (existing.attempts >= existing.maxAttempts) {
      return AuthPhoneNumberVerificationResult(
        AuthPhoneNumberVerificationStatus.tooManyAttempts,
        existing,
      );
    }

    final nextAttempts = existing.attempts + 1;
    if (!constantTimeStringEquals(existing.codeDigest, codeDigest)) {
      final updated = existing.copyWith(attempts: nextAttempts);
      _verifications[phoneNumber] = updated;
      return AuthPhoneNumberVerificationResult(
        nextAttempts >= existing.maxAttempts
            ? AuthPhoneNumberVerificationStatus.tooManyAttempts
            : AuthPhoneNumberVerificationStatus.invalid,
        updated,
      );
    }

    final consumed = existing.copyWith(
      attempts: nextAttempts,
      consumedAt: current,
    );
    _verifications[phoneNumber] = consumed;
    return AuthPhoneNumberVerificationResult(
      AuthPhoneNumberVerificationStatus.verified,
      consumed,
    );
  }

  @override
  Future<bool> deleteVerificationIfCurrent(
    String phoneNumber,
    String verificationId,
  ) async {
    final current = _verifications[phoneNumber];
    if (current?.id != verificationId) return false;
    _verifications.remove(phoneNumber);
    return true;
  }

  @override
  Future<AuthPhoneNumberIdentity?> findIdentity(String phoneNumber) async =>
      _identitiesByPhone[phoneNumber];

  @override
  Future<AuthPhoneNumberIdentity?> findIdentityForUser(String userId) async {
    final phone = _phoneByUser[userId.trim()];
    return phone == null ? null : _identitiesByPhone[phone];
  }

  @override
  Future<AuthPhoneNumberIdentity> bindIdentity(
    AuthPhoneNumberIdentity identity,
  ) async {
    _validateIdentity(identity);
    final existing = _identitiesByPhone[identity.phoneNumber];
    if (existing != null) return existing;

    final previousPhone = _phoneByUser[identity.userId];
    if (previousPhone != null && previousPhone != identity.phoneNumber) {
      _identitiesByPhone.remove(previousPhone);
      _verifications.remove(previousPhone);
    }
    _identitiesByPhone[identity.phoneNumber] = identity;
    _phoneByUser[identity.userId] = identity.phoneNumber;
    return identity;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) return;
    final phone = _phoneByUser.remove(normalized);
    if (phone != null) {
      _identitiesByPhone.remove(phone);
      _verifications.remove(phone);
    }
  }

  @override
  Future<void> deleteUserDataForDeletion(String userId) =>
      deleteForUser(userId);

  void _removeExpired(DateTime now) {
    _verifications.removeWhere((_, value) => value.isExpired(now: now));
  }
}

final class _PhoneNumberStoreCheckpoint {
  const _PhoneNumberStoreCheckpoint({
    required this.verifications,
    required this.identitiesByPhone,
    required this.phoneByUser,
  });

  final Map<String, AuthPhoneNumberVerification> verifications;
  final Map<String, AuthPhoneNumberIdentity> identitiesByPhone;
  final Map<String, String> phoneByUser;
}

void _validateVerification(AuthPhoneNumberVerification verification) {
  if (verification.id.trim().isEmpty ||
      !_isCanonicalE164(verification.phoneNumber) ||
      verification.codeDigest.trim().isEmpty ||
      verification.maxAttempts <= 0 ||
      verification.attempts < 0 ||
      verification.attempts > verification.maxAttempts ||
      !verification.expiresAt.toUtc().isAfter(verification.createdAt.toUtc())) {
    throw ArgumentError.value(verification, 'verification', 'is invalid');
  }
}

void _validateIdentity(AuthPhoneNumberIdentity identity) {
  if (!_isCanonicalE164(identity.phoneNumber) ||
      identity.userId.trim().isEmpty ||
      identity.verifiedAt.toUtc().isBefore(identity.createdAt.toUtc())) {
    throw ArgumentError.value(identity, 'identity', 'is invalid');
  }
}

bool _isCanonicalE164(String value) =>
    RegExp(r'^\+[1-9][0-9]{1,14}$').hasMatch(value);
