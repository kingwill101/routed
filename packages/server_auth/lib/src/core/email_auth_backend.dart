import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:server_auth/src/core/email_otp_store.dart';
import 'package:server_auth/src/core/models.dart';

/// Maximum accepted length for an email authentication identifier.
const int authEmailIdentifierMaximumLength = 320;

/// Maximum raw OTP input accepted before digesting.
const int authEmailOtpMaximumLength = 128;

/// Minimum UTF-8 key size for digesting low-entropy email OTP values.
const int authEmailOtpDigestKeyMinimumLength = 32;

/// Normalizes and validates an email used by one-time email credentials.
///
/// Trims and lowercases [value], then throws an [ArgumentError] when it is
/// empty, malformed, too long, or contains control characters.
String normalizeAuthOneTimeEmail(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized.length > authEmailIdentifierMaximumLength ||
      normalized.contains(RegExp(r'[\u0000-\u001f\u007f]')) ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
    throw ArgumentError('must be a valid email address', 'email');
  }
  return normalized;
}

/// Validates a digest before it crosses an email-auth persistence boundary.
///
/// Returns the trimmed [value] when it is a 64-character hexadecimal or
/// 43-character unpadded base64url SHA-256 digest; otherwise throws an
/// [ArgumentError] using [name].
String validateAuthEmailSecretDigest(String value, String name) {
  final digest = value.trim();
  final isHex = RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
  final isBase64Url = RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(digest);
  if (!isHex && !isBase64Url) {
    throw ArgumentError('must be a SHA-256 digest', name);
  }
  return digest;
}

/// Produces the keyed digest persisted for a low-entropy email OTP.
///
/// A plain SHA-256 digest does not protect a short numeric OTP from offline
/// enumeration after a database leak. This boundary therefore requires an
/// application secret and domain-separates email OTP material from other HMAC
/// uses. The raw code must only be retained long enough for delivery.
String digestAuthEmailOtpCode({required String code, required String secret}) {
  final normalized = code.trim();
  final key = utf8.encode(secret);
  if (normalized.isEmpty || normalized.length > authEmailOtpMaximumLength) {
    throw ArgumentError(
      'must be non-empty and at most $authEmailOtpMaximumLength characters',
      'code',
    );
  }
  if (key.length < authEmailOtpDigestKeyMinimumLength) {
    throw ArgumentError(
      'must contain at least $authEmailOtpDigestKeyMinimumLength UTF-8 bytes',
      'secret',
    );
  }
  return Hmac(
    sha256,
    key,
  ).convert(utf8.encode('routed-auth:email-otp:$normalized')).toString();
}

String _validateProviderId(String value) {
  final id = value.trim();
  if (id.isEmpty || id != value || id.length > 128) {
    throw ArgumentError(
      'must be non-empty, trimmed, and at most 128 characters',
      'providerId',
    );
  }
  return id;
}

/// Digest-only magic-link record owned by an authentication backend.
final class AuthMagicLinkRecord {
  /// Creates a validated, digest-only magic-link record.
  ///
  /// Email and provider values are canonicalized, timestamps are converted to
  /// UTC, and [expiresAt] must be after [issuedAt]. The raw token is never
  /// accepted by this record.
  AuthMagicLinkRecord({
    required String providerId,
    required String email,
    required String tokenHash,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) : providerId = _validateProviderId(providerId),
       email = normalizeAuthOneTimeEmail(email),
       tokenHash = validateAuthEmailSecretDigest(tokenHash, 'tokenHash'),
       issuedAt = issuedAt.toUtc(),
       expiresAt = expiresAt.toUtc() {
    if (!this.expiresAt.isAfter(this.issuedAt)) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'must be after issuedAt',
      );
    }
  }

  /// Route-safe provider identifier for this link.
  final String providerId;

  /// Canonical email address bound to this link.
  final String email;

  /// SHA-256 digest of the one-time token.
  final String tokenHash;

  /// UTC time at which this link was issued.
  final DateTime issuedAt;

  /// UTC deadline after which this link cannot be consumed.
  final DateTime expiresAt;

  /// Whether [now] is at or after the expiry deadline.
  bool isExpired(DateTime now) => !now.toUtc().isBefore(expiresAt);

  /// Serializes persistence state without a deliverable raw token.
  Map<String, Object?> toStorageJson() => <String, Object?>{
    'provider_id': providerId,
    'email': email,
    'token_hash': tokenHash,
    'issued_at': issuedAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
  };
}

/// Replaces every prior active magic link for one canonical email.
final class AuthMagicLinkIssueCommand {
  /// Creates an issuance command that replaces prior active links.
  const AuthMagicLinkIssueCommand(this.record);

  /// Digest-only record to persist atomically.
  final AuthMagicLinkRecord record;
}

/// Atomically consumes a magic link and resolves its verified local user.
///
/// [tokenHash] is derived before the command reaches persistence. [candidate]
/// is used only when no user owns [email]; its ID must remain stable for this
/// command attempt.
final class AuthMagicLinkConsumeCommand {
  /// Creates a command for atomic magic-link consumption.
  ///
  /// [candidate] is used only when the backend must create or resolve a user
  /// for [email]; it must have a stable ID and matching canonical email.
  AuthMagicLinkConsumeCommand({
    required String providerId,
    required String email,
    required String tokenHash,
    required DateTime now,
    required this.candidate,
  }) : providerId = _validateProviderId(providerId),
       email = normalizeAuthOneTimeEmail(email),
       tokenHash = validateAuthEmailSecretDigest(tokenHash, 'tokenHash'),
       now = now.toUtc() {
    if (candidate.id.trim().isEmpty ||
        candidate.email == null ||
        normalizeAuthOneTimeEmail(candidate.email!) != this.email) {
      throw ArgumentError(
        'must have a stable ID and the command email',
        'candidate',
      );
    }
  }

  /// Provider partition containing the link.
  final String providerId;

  /// Canonical email expected by the link.
  final String email;

  /// Digest of the raw callback token.
  final String tokenHash;

  /// UTC time used for expiry evaluation.
  final DateTime now;

  /// Stable candidate user data for a create-or-resolve operation.
  final AuthUser candidate;
}

/// Outcome of consuming a magic-link record.
enum AuthMagicLinkConsumeStatus {
  /// The link was consumed and [AuthMagicLinkConsumeResult.user] is available.
  consumed,

  /// The token did not match an active record.
  invalid,

  /// The matching record had expired.
  expired,

  /// The token was valid but the local user could not be used.
  userUnavailable,
}

/// Result of an atomic magic-link consume operation.
final class AuthMagicLinkConsumeResult {
  /// Creates a backend result with optional resolved-user metadata.
  const AuthMagicLinkConsumeResult(
    this.status, {
    this.user,
    this.created = false,
  });

  /// Outcome reported by the backend.
  final AuthMagicLinkConsumeStatus status;

  /// Resolved user when [status] is [AuthMagicLinkConsumeStatus.consumed].
  final AuthUser? user;

  /// Whether the backend created [user] during consumption.
  final bool created;
}

/// Required transaction boundary for email magic-link authentication.
///
/// Durable adapters must replace issuance state and perform token consumption,
/// user creation/lookup, and verified-email persistence in backend-native
/// transactions. There is intentionally no callback or store-level fallback.
abstract interface class AuthMagicLinkBackend {
  /// Replaces the active provider/email record atomically.
  ///
  /// The command contains only a token digest. Implementations should roll
  /// back the replacement if the transaction fails.
  FutureOr<void> issueMagicLink(AuthMagicLinkIssueCommand command);

  /// Consumes a link and resolves or creates its verified user atomically.
  ///
  /// Implementations must make concurrent consumption single-use and return a
  /// status rather than exposing persistence-specific failures.
  FutureOr<AuthMagicLinkConsumeResult> consumeMagicLink(
    AuthMagicLinkConsumeCommand command,
  );
}

/// Persists a digest-only email OTP, replacing the active purpose-specific
/// record for its canonical email.
final class AuthEmailOtpIssueCommand {
  /// Creates a command for replacing a fresh digest-only OTP record.
  AuthEmailOtpIssueCommand(AuthEmailOtp otp)
    : otp = AuthEmailOtp(
        id: otp.id,
        email: normalizeAuthOneTimeEmail(otp.email),
        codeHash: validateAuthEmailSecretDigest(otp.codeHash, 'codeHash'),
        type: otp.type,
        createdAt: otp.createdAt.toUtc(),
        expiresAt: otp.expiresAt.toUtc(),
        maxAttempts: otp.maxAttempts,
        attempts: otp.attempts,
        consumed: otp.consumed,
      ) {
    if (this.otp.id.trim().isEmpty ||
        this.otp.id != this.otp.id.trim() ||
        this.otp.attempts != 0 ||
        this.otp.consumed ||
        this.otp.maxAttempts <= 0 ||
        !this.otp.expiresAt.isAfter(this.otp.createdAt)) {
      throw ArgumentError(
        'must be a fresh, bounded digest-only OTP record',
        'otp',
      );
    }
  }

  /// Validated OTP record to persist atomically.
  final AuthEmailOtp otp;
}

/// Atomically compares, counts, and consumes one OTP attempt.
final class AuthEmailOtpVerifyCommand {
  /// Creates an atomic OTP verification command.
  ///
  /// [codeHash] must be an application-keyed digest; raw OTP values never
  /// cross this backend boundary.
  AuthEmailOtpVerifyCommand({
    required String email,
    required this.type,
    required String codeHash,
    required DateTime now,
  }) : email = normalizeAuthOneTimeEmail(email),
       codeHash = validateAuthEmailSecretDigest(codeHash, 'codeHash'),
       now = now.toUtc();

  /// Canonical email bound to the OTP.
  final String email;

  /// Purpose partition for the OTP.
  final AuthEmailOtpType type;

  /// Application-keyed digest of the submitted code.
  final String codeHash;

  /// UTC time used for expiry and attempt accounting.
  final DateTime now;
}

/// Atomically consumes a sign-in OTP and resolves its verified local user.
final class AuthEmailOtpSignInCommand {
  /// Creates a command for atomic OTP sign-in and user transition.
  ///
  /// [candidate] supplies stable new-user data when sign-up is allowed.
  AuthEmailOtpSignInCommand({
    required String email,
    required String codeHash,
    required DateTime now,
    required this.candidate,
    required this.disableSignUp,
  }) : email = normalizeAuthOneTimeEmail(email),
       codeHash = validateAuthEmailSecretDigest(codeHash, 'codeHash'),
       now = now.toUtc() {
    if (candidate.id.trim().isEmpty ||
        candidate.email == null ||
        normalizeAuthOneTimeEmail(candidate.email!) != this.email) {
      throw ArgumentError(
        'must have a stable ID and the command email',
        'candidate',
      );
    }
  }

  /// Canonical email bound to the OTP.
  final String email;

  /// Application-keyed digest of the submitted code.
  final String codeHash;

  /// UTC time used for expiry and attempt accounting.
  final DateTime now;

  /// Stable candidate data for a possible user creation.
  final AuthUser candidate;

  /// Whether unknown email addresses must be rejected.
  final bool disableSignUp;
}

/// Atomically consumes an email-verification OTP bound to the current user and
/// their current email address.
final class AuthEmailOtpVerifyUserCommand {
  /// Creates a command for atomic authenticated email verification.
  AuthEmailOtpVerifyUserCommand({
    required String userId,
    required String email,
    required String codeHash,
    required DateTime now,
  }) : userId = userId.trim(),
       email = normalizeAuthOneTimeEmail(email),
       codeHash = validateAuthEmailSecretDigest(codeHash, 'codeHash'),
       now = now.toUtc() {
    if (this.userId.isEmpty) {
      throw ArgumentError('must be non-empty', 'userId');
    }
  }

  /// Existing user identifier that must be updated.
  final String userId;

  /// Canonical current email address.
  final String email;

  /// Application-keyed digest of the submitted code.
  final String codeHash;

  /// UTC time used for expiry and attempt accounting.
  final DateTime now;
}

/// Outcome of a user transition coupled to OTP consumption.
enum AuthEmailOtpUserTransitionStatus {
  /// The OTP was consumed and the user mutation was applied.
  applied,

  /// The code did not match.
  invalid,

  /// The OTP had expired.
  expired,

  /// The attempt limit was reached.
  tooManyAttempts,

  /// No eligible user exists.
  userNotFound,

  /// A user exists but cannot be used.
  userUnavailable,
}

/// Result of an OTP-backed user transition.
final class AuthEmailOtpUserTransitionResult {
  /// Creates a user-transition result with optional user metadata.
  const AuthEmailOtpUserTransitionResult(
    this.status, {
    this.user,
    this.created = false,
  });

  /// Outcome reported by the backend.
  final AuthEmailOtpUserTransitionStatus status;

  /// Resolved or created user when the transition was applied.
  final AuthUser? user;

  /// Whether [user] was created during the transition.
  final bool created;
}

/// Required transaction boundary for the email OTP plugin.
///
/// The backend owns OTP attempt accounting and every user mutation coupled to
/// successful consumption. Raw codes are hashed before reaching this API.
abstract interface class AuthEmailOtpBackend {
  /// OTP persistence boundary used by the plugin's deletion plan.
  AuthEmailOtpStore get emailOtpStore;

  /// Replaces the active email/purpose OTP atomically.
  FutureOr<void> issueEmailOtp(AuthEmailOtpIssueCommand command);

  /// Compares a digest, counts the attempt, and consumes a valid OTP atomically.
  FutureOr<AuthEmailOtpVerificationResult> verifyEmailOtp(
    AuthEmailOtpVerifyCommand command,
  );

  /// Consumes a sign-in OTP and applies its user transition atomically.
  FutureOr<AuthEmailOtpUserTransitionResult> signInWithEmailOtp(
    AuthEmailOtpSignInCommand command,
  );

  /// Consumes an authenticated user's email-verification OTP atomically.
  FutureOr<AuthEmailOtpUserTransitionResult> verifyUserEmailWithOtp(
    AuthEmailOtpVerifyUserCommand command,
  );
}

/// Fault locations supported by the deterministic in-memory rollback test
/// injector.
enum AuthEmailBackendFaultPoint {
  /// After a magic-link issuance record is written.
  afterMagicLinkWrite,

  /// After a magic-link record is consumed.
  afterMagicLinkConsume,

  /// After an OTP issuance record is written.
  afterEmailOtpWrite,

  /// After an OTP record is consumed.
  afterEmailOtpConsume,

  /// After a user mutation is written.
  afterUserWrite,
}

/// Exception raised when a configured email-transaction fault is triggered.
final class AuthEmailBackendInjectedFault implements Exception {
  /// Creates a test fault associated with [point].
  const AuthEmailBackendInjectedFault(this.point);

  /// Transaction location at which the fault was injected.
  final AuthEmailBackendFaultPoint point;

  @override
  String toString() => 'AuthEmailBackendInjectedFault(${point.name})';
}

/// One-shot fault injector for `InMemoryAuthStore` email transactions.
/// Schedules one-shot failures for in-memory email transaction tests.
final class AuthEmailBackendFaultInjector {
  final Set<AuthEmailBackendFaultPoint> _pending =
      <AuthEmailBackendFaultPoint>{};

  /// Schedules one failure at [point].
  void failNext(AuthEmailBackendFaultPoint point) => _pending.add(point);

  /// Throws once when [point] has been scheduled by a test.
  void throwIfScheduled(AuthEmailBackendFaultPoint point) {
    if (_pending.remove(point)) throw AuthEmailBackendInjectedFault(point);
  }
}
