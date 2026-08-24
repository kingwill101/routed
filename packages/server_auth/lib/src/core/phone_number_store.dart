import 'dart:async';

import 'authentication_methods.dart';
import 'models.dart';

/// A verified E.164 phone number linked to one auth user.
final class AuthPhoneNumberIdentity {
  /// Creates a verified phone identity record.
  const AuthPhoneNumberIdentity({
    required this.phoneNumber,
    required this.userId,
    required this.createdAt,
    required this.verifiedAt,
  });

  /// Canonical E.164 phone number.
  final String phoneNumber;

  /// Identifier of the owning user.
  final String userId;

  /// Time at which the identity was created.
  final DateTime createdAt;

  /// Time at which the phone number was verified.
  final DateTime verifiedAt;

  /// Returns the persistence representation of this identity.
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
  /// Creates a persisted phone verification challenge.
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

  /// Stable identifier for the challenge.
  final String id;

  /// Canonical phone number being verified.
  final String phoneNumber;

  /// Keyed digest of the verification code.
  final String codeDigest;

  /// Time at which the challenge was created.
  final DateTime createdAt;

  /// Time after which the challenge cannot be used.
  final DateTime expiresAt;

  /// Maximum number of failed verification attempts.
  final int maxAttempts;

  /// Number of failed attempts recorded so far.
  final int attempts;

  /// Time at which verification became locked, if locked.
  final DateTime? lockedAt;

  /// Time at which the challenge was consumed, if consumed.
  final DateTime? consumedAt;

  /// Whether this challenge has been consumed.
  bool get isConsumed => consumedAt != null;

  /// Whether this challenge cannot accept another attempt.
  bool get isLocked => lockedAt != null || attempts >= maxAttempts;

  /// Returns whether this challenge is expired at [now].
  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

  /// Returns a copy with the supplied mutable state replaced.
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

  /// Returns the persistence representation of this challenge.
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

/// Outcomes of an atomic phone-code issue command.
enum AuthPhoneNumberIssueStatus {
  /// A new challenge was committed.
  issued,

  /// An identical issue command replayed an existing challenge.
  replayed,

  /// The command ID was reused with different challenge data.
  replayMismatch,
}

/// Store result returned by an atomic phone-code issue command.
final class AuthPhoneNumberIssueResult {
  /// Creates the outcome of an issue command.
  const AuthPhoneNumberIssueResult(this.status, {this.verification});

  /// Outcome of the issue operation.
  final AuthPhoneNumberIssueStatus status;

  /// Challenge committed by the store, when available.
  final AuthPhoneNumberVerification? verification;

  /// Whether the operation created or replayed a committed challenge.
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
  /// Creates a validated phone-code issue command.
  AuthPhoneNumberIssueCodeCommand({required this.verification}) {
    validateAuthPhoneNumberVerification(verification);
  }

  /// Challenge to install atomically.
  final AuthPhoneNumberVerification verification;
}

/// Outcomes of an atomic phone-code verification command.
enum AuthPhoneNumberVerifyStatus {
  /// The code was accepted and the identity was committed.
  verified,

  /// The supplied code did not match.
  invalid,

  /// The challenge has expired.
  expired,

  /// The challenge has exceeded its attempt limit.
  tooManyAttempts,

  /// No user could be resolved for the verified phone number.
  userNotFound,

  /// The resolved user cannot authenticate.
  userUnavailable,

  /// The phone number is already bound to another user.
  conflict,
}

/// Store result returned by an atomic phone-code verification command.
final class AuthPhoneNumberVerifyResult {
  /// Creates the outcome of a phone-code verification command.
  const AuthPhoneNumberVerifyResult(
    this.status, {
    this.verification,
    this.identity,
    this.user,
  });

  /// Outcome of the verification operation.
  final AuthPhoneNumberVerifyStatus status;

  /// Updated challenge, when the store can return it.
  final AuthPhoneNumberVerification? verification;

  /// Identity committed by a successful verification.
  final AuthPhoneNumberIdentity? identity;

  /// User resolved or created by a successful verification.
  final AuthUser? user;

  /// Whether the operation committed the phone identity.
  bool get committed => status == AuthPhoneNumberVerifyStatus.verified;
}

/// Atomically verifies and consumes a phone challenge.
///
/// [codeDigest] is the only code representation accepted by the backend.
/// When no identity exists, [candidateUser] authorizes sign-up. The backend
/// creates that user, binds the phone, projects verified phone attributes, and
/// consumes the challenge in one transaction. A null candidate fails closed.
final class AuthPhoneNumberVerifyCodeCommand {
  /// Creates a validated phone-code verification command.
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

  /// Canonical phone number being verified.
  final String phoneNumber;

  /// Keyed digest of the code supplied by the caller.
  final String codeDigest;

  /// Time used for expiry and lockout decisions.
  final DateTime now;

  /// Candidate user used only when the phone is not yet registered.
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
  /// Issues a challenge in the store-owned transaction.
  FutureOr<AuthPhoneNumberIssueResult> issuePhoneNumberCode(
    AuthPhoneNumberIssueCodeCommand command,
  );

  /// Verifies and consumes a challenge in the store-owned transaction.
  FutureOr<AuthPhoneNumberVerifyResult> verifyPhoneNumberCode(
    AuthPhoneNumberVerifyCodeCommand command,
  );

  /// Finds the identity bound to [phoneNumber].
  FutureOr<AuthPhoneNumberIdentity?> findPhoneNumberIdentity(
    String phoneNumber,
  );

  /// Finds the phone identity owned by [userId].
  FutureOr<AuthPhoneNumberIdentity?> findPhoneNumberIdentityForUser(
    String userId,
  );
}

/// Complete input to an atomic phone-identity removal.
final class AuthPhoneNumberRemovalCommand {
  /// Creates a validated phone-identity removal command.
  AuthPhoneNumberRemovalCommand({
    required this.userId,
    required this.phoneNumber,
    required this.loadInventory,
  }) {
    if (userId.isEmpty || userId.trim() != userId) {
      throw ArgumentError.value(
        userId,
        'userId',
        'must be canonical and non-empty',
      );
    }
    validateAuthCanonicalPhoneNumber(phoneNumber);
  }

  /// Identifier of the user that owns the identity.
  final String userId;

  /// Canonical phone number to remove.
  final String phoneNumber;

  /// Loads the composed topology as evidence for the backend command.
  ///
  /// Durable backends must recheck every supported fallback inside their own
  /// transaction. This callback is not itself a transaction boundary.
  final AuthAuthenticationMethodInventoryLoader loadInventory;
}

/// Optional exact transaction for removing a verified phone identity safely.
abstract interface class AuthPhoneNumberMutationStore {
  /// Removes the identity when the composed auth topology remains usable.
  FutureOr<AuthAuthenticationMethodMutationResult> removePhoneNumberIfSafe(
    AuthPhoneNumberRemovalCommand command,
  );
}

/// Deterministic fault points exposed by the process-local backend.
enum AuthPhoneNumberInMemoryFaultPoint {
  /// Fault after writing a new challenge.
  issueAfterChallengeWrite,

  /// Fault after recording a failed attempt.
  verifyAfterAttemptWrite,

  /// Fault after consuming a challenge.
  verifyAfterChallengeConsumption,

  /// Fault after writing a user.
  verifyAfterUserWrite,

  /// Fault after writing a phone identity.
  verifyAfterIdentityWrite,

  /// Fault after projecting verified-phone attributes.
  verifyAfterUserProjection,
}

/// Callback used by the in-memory backend to inject deterministic failures.
typedef AuthPhoneNumberInMemoryFaultInjector =
    FutureOr<void> Function(AuthPhoneNumberInMemoryFaultPoint point);

/// Validates and returns a canonical E.164 phone number.
String validateAuthCanonicalPhoneNumber(String value) {
  if (!RegExp(r'^\+[1-9][0-9]{1,14}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'phoneNumber', 'must be canonical E.164');
  }
  return value;
}

/// Validates a challenge before a backend stores it.
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

/// Validates a candidate user before phone sign-up can create it.
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
