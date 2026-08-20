import 'dart:async';

import 'models.dart';

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
/// [codeDigest] is a keyed digest. A raw verification code must never cross
/// the backend boundary or be persisted in an operation receipt.
final class AuthPhoneNumberVerification {
  const AuthPhoneNumberVerification({
    required this.id,
    required this.phoneNumber,
    required this.codeDigest,
    required this.createdAt,
    required this.expiresAt,
    required this.maxAttempts,
    this.attempts = 0,
    this.lockedAt,
    this.consumedAt,
  });

  final String id;
  final String phoneNumber;
  final String codeDigest;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxAttempts;
  final int attempts;
  final DateTime? lockedAt;
  final DateTime? consumedAt;

  bool get isConsumed => consumedAt != null;
  bool get isLocked => lockedAt != null || attempts >= maxAttempts;

  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

  AuthPhoneNumberVerification copyWith({
    int? attempts,
    DateTime? lockedAt,
    DateTime? consumedAt,
  }) => AuthPhoneNumberVerification(
    id: id,
    phoneNumber: phoneNumber,
    codeDigest: codeDigest,
    createdAt: createdAt,
    expiresAt: expiresAt,
    maxAttempts: maxAttempts,
    attempts: attempts ?? this.attempts,
    lockedAt: lockedAt ?? this.lockedAt,
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
    'locked_at': lockedAt?.toUtc().toIso8601String(),
    'consumed_at': consumedAt?.toUtc().toIso8601String(),
  };
}

enum AuthPhoneNumberIssueStatus { issued, replayed, replayMismatch }

final class AuthPhoneNumberIssueResult {
  const AuthPhoneNumberIssueResult(this.status, {this.verification});

  final AuthPhoneNumberIssueStatus status;
  final AuthPhoneNumberVerification? verification;

  bool get committed =>
      status == AuthPhoneNumberIssueStatus.issued ||
      status == AuthPhoneNumberIssueStatus.replayed;
}

/// Atomically installs one digest-only phone challenge.
///
/// A repeated command with the same ID and payload returns a replay. Reusing
/// the ID for different state must return
/// [AuthPhoneNumberIssueStatus.replayMismatch].
final class AuthPhoneNumberIssueCodeCommand {
  AuthPhoneNumberIssueCodeCommand({required this.verification}) {
    validateAuthPhoneNumberVerification(verification);
  }

  final AuthPhoneNumberVerification verification;
}

enum AuthPhoneNumberVerifyStatus {
  verified,
  invalid,
  expired,
  tooManyAttempts,
  userNotFound,
  userUnavailable,
  conflict,
}

final class AuthPhoneNumberVerifyResult {
  const AuthPhoneNumberVerifyResult(
    this.status, {
    this.verification,
    this.identity,
    this.user,
  });

  final AuthPhoneNumberVerifyStatus status;
  final AuthPhoneNumberVerification? verification;
  final AuthPhoneNumberIdentity? identity;
  final AuthUser? user;

  bool get committed => status == AuthPhoneNumberVerifyStatus.verified;
}

/// Atomically verifies and consumes a phone challenge.
///
/// [codeDigest] is the only code representation accepted by the backend.
/// When no identity exists, [candidateUser] authorizes sign-up. The backend
/// creates that user, binds the phone, projects verified phone attributes, and
/// consumes the challenge in one transaction. A null candidate fails closed.
final class AuthPhoneNumberVerifyCodeCommand {
  AuthPhoneNumberVerifyCodeCommand({
    required String phoneNumber,
    required String codeDigest,
    required DateTime now,
    this.candidateUser,
  }) : phoneNumber = validateAuthCanonicalPhoneNumber(phoneNumber),
       codeDigest = _validateDigest(codeDigest),
       now = now.toUtc() {
    final candidate = candidateUser;
    if (candidate != null) validateAuthPhoneNumberCandidateUser(candidate);
  }

  final String phoneNumber;
  final String codeDigest;
  final DateTime now;
  final AuthUser? candidateUser;
}

/// Required backend-owned command capability for phone authentication.
///
/// Durable implementations must run each command in a real transaction. Code
/// verification must atomically update attempts or lockout, consume one valid
/// challenge, resolve or create the user, bind the phone identity, and update
/// the user's verified-phone projection. Exactly one concurrent verifier may
/// commit. Hard deletion must remove identities, challenges, and issue
/// receipts in the same transaction as core user deletion.
///
/// SMS delivery, verification callbacks, and framework session/cookie issuance
/// intentionally happen after these commands commit and are not rolled back by
/// this API.
abstract interface class AuthPhoneNumberBackend {
  FutureOr<AuthPhoneNumberIssueResult> issuePhoneNumberCode(
    AuthPhoneNumberIssueCodeCommand command,
  );

  FutureOr<AuthPhoneNumberVerifyResult> verifyPhoneNumberCode(
    AuthPhoneNumberVerifyCodeCommand command,
  );

  FutureOr<AuthPhoneNumberIdentity?> findPhoneNumberIdentity(
    String phoneNumber,
  );

  FutureOr<AuthPhoneNumberIdentity?> findPhoneNumberIdentityForUser(
    String userId,
  );
}

/// Deterministic fault points exposed by the process-local backend.
enum AuthPhoneNumberInMemoryFaultPoint {
  issueAfterChallengeWrite,
  verifyAfterAttemptWrite,
  verifyAfterChallengeConsumption,
  verifyAfterUserWrite,
  verifyAfterIdentityWrite,
  verifyAfterUserProjection,
}

typedef AuthPhoneNumberInMemoryFaultInjector =
    FutureOr<void> Function(AuthPhoneNumberInMemoryFaultPoint point);

String validateAuthCanonicalPhoneNumber(String value) {
  if (!RegExp(r'^\+[1-9][0-9]{1,14}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'phoneNumber', 'must be canonical E.164');
  }
  return value;
}

void validateAuthPhoneNumberVerification(
  AuthPhoneNumberVerification verification,
) {
  if (verification.id.trim().isEmpty ||
      verification.id != verification.id.trim() ||
      verification.id.length > 256 ||
      verification.id.runes.any((rune) => rune < 0x20 || rune == 0x7f) ||
      verification.codeDigest.trim().isEmpty ||
      verification.codeDigest != verification.codeDigest.trim() ||
      verification.codeDigest.length > 256 ||
      verification.maxAttempts <= 0 ||
      verification.maxAttempts > 100 ||
      verification.attempts < 0 ||
      verification.attempts > verification.maxAttempts ||
      !verification.expiresAt.toUtc().isAfter(verification.createdAt.toUtc()) ||
      verification.consumedAt != null ||
      verification.lockedAt != null) {
    throw ArgumentError.value(verification, 'verification', 'is invalid');
  }
  validateAuthCanonicalPhoneNumber(verification.phoneNumber);
}

void validateAuthPhoneNumberCandidateUser(AuthUser user) {
  if (user.id.trim().isEmpty ||
      user.id != user.id.trim() ||
      user.id.length > 256 ||
      user.id.runes.any((rune) => rune < 0x20 || rune == 0x7f) ||
      user.isAnonymous) {
    throw ArgumentError.value(user, 'candidateUser', 'is invalid');
  }
}

String _validateDigest(String value) {
  if (value.trim().isEmpty ||
      value != value.trim() ||
      value.length > 256 ||
      value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw ArgumentError.value(value, 'codeDigest', 'is invalid');
  }
  return value;
}
