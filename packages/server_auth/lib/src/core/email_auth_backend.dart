import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;

import 'email_otp_store.dart';
import 'models.dart';

/// Maximum accepted length for an email authentication identifier.
const int authEmailIdentifierMaximumLength = 320;

/// Maximum raw OTP input accepted before digesting.
const int authEmailOtpMaximumLength = 128;

/// Minimum UTF-8 key size for digesting low-entropy email OTP values.
const int authEmailOtpDigestKeyMinimumLength = 32;

/// Canonicalizes and validates an email used by one-time email credentials.
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

  final String providerId;
  final String email;
  final String tokenHash;
  final DateTime issuedAt;
  final DateTime expiresAt;

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
  const AuthMagicLinkIssueCommand(this.record);

  final AuthMagicLinkRecord record;
}

/// Atomically consumes a magic link and resolves its verified local user.
///
/// [tokenHash] is derived before the command reaches persistence. [candidate]
/// is used only when no user owns [email]; its ID must remain stable for this
/// command attempt.
final class AuthMagicLinkConsumeCommand {
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

  final String providerId;
  final String email;
  final String tokenHash;
  final DateTime now;
  final AuthUser candidate;
}

enum AuthMagicLinkConsumeStatus { consumed, invalid, expired, userUnavailable }

final class AuthMagicLinkConsumeResult {
  const AuthMagicLinkConsumeResult(
    this.status, {
    this.user,
    this.created = false,
  });

  final AuthMagicLinkConsumeStatus status;
  final AuthUser? user;
  final bool created;
}

/// Required transaction boundary for email magic-link authentication.
///
/// Durable adapters must replace issuance state and perform token consumption,
/// user creation/lookup, and verified-email persistence in backend-native
/// transactions. There is intentionally no callback or store-level fallback.
abstract interface class AuthMagicLinkBackend {
  FutureOr<void> issueMagicLink(AuthMagicLinkIssueCommand command);

  FutureOr<AuthMagicLinkConsumeResult> consumeMagicLink(
    AuthMagicLinkConsumeCommand command,
  );
}

/// Persists a digest-only email OTP, replacing the active purpose-specific
/// record for its canonical email.
final class AuthEmailOtpIssueCommand {
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

  final AuthEmailOtp otp;
}

/// Atomically compares, counts, and consumes one OTP attempt.
final class AuthEmailOtpVerifyCommand {
  AuthEmailOtpVerifyCommand({
    required String email,
    required this.type,
    required String codeHash,
    required DateTime now,
  }) : email = normalizeAuthOneTimeEmail(email),
       codeHash = validateAuthEmailSecretDigest(codeHash, 'codeHash'),
       now = now.toUtc();

  final String email;
  final AuthEmailOtpType type;
  final String codeHash;
  final DateTime now;
}

/// Atomically consumes a sign-in OTP and resolves its verified local user.
final class AuthEmailOtpSignInCommand {
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

  final String email;
  final String codeHash;
  final DateTime now;
  final AuthUser candidate;
  final bool disableSignUp;
}

/// Atomically consumes an email-verification OTP bound to the current user and
/// their current email address.
final class AuthEmailOtpVerifyUserCommand {
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

  final String userId;
  final String email;
  final String codeHash;
  final DateTime now;
}

enum AuthEmailOtpUserTransitionStatus {
  applied,
  invalid,
  expired,
  tooManyAttempts,
  userNotFound,
  userUnavailable,
}

final class AuthEmailOtpUserTransitionResult {
  const AuthEmailOtpUserTransitionResult(
    this.status, {
    this.user,
    this.created = false,
  });

  final AuthEmailOtpUserTransitionStatus status;
  final AuthUser? user;
  final bool created;
}

/// Required transaction boundary for the email OTP plugin.
///
/// The backend owns OTP attempt accounting and every user mutation coupled to
/// successful consumption. Raw codes are hashed before reaching this API.
abstract interface class AuthEmailOtpBackend {
  AuthEmailOtpStore get emailOtpStore;

  FutureOr<void> issueEmailOtp(AuthEmailOtpIssueCommand command);

  FutureOr<AuthEmailOtpVerificationResult> verifyEmailOtp(
    AuthEmailOtpVerifyCommand command,
  );

  FutureOr<AuthEmailOtpUserTransitionResult> signInWithEmailOtp(
    AuthEmailOtpSignInCommand command,
  );

  FutureOr<AuthEmailOtpUserTransitionResult> verifyUserEmailWithOtp(
    AuthEmailOtpVerifyUserCommand command,
  );
}

/// Deterministic in-memory fault locations used by rollback tests.
enum AuthEmailBackendFaultPoint {
  afterMagicLinkWrite,
  afterMagicLinkConsume,
  afterEmailOtpWrite,
  afterEmailOtpConsume,
  afterUserWrite,
}

final class AuthEmailBackendInjectedFault implements Exception {
  const AuthEmailBackendInjectedFault(this.point);

  final AuthEmailBackendFaultPoint point;

  @override
  String toString() => 'AuthEmailBackendInjectedFault(${point.name})';
}

/// One-shot fault injector for [InMemoryAuthStore] email transactions.
final class AuthEmailBackendFaultInjector {
  final Set<AuthEmailBackendFaultPoint> _pending =
      <AuthEmailBackendFaultPoint>{};

  void failNext(AuthEmailBackendFaultPoint point) => _pending.add(point);

  /// Throws once when [point] has been scheduled by a test.
  void throwIfScheduled(AuthEmailBackendFaultPoint point) {
    if (_pending.remove(point)) throw AuthEmailBackendInjectedFault(point);
  }
}
