import 'dart:async';

import 'exceptions.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'password_reset_token_store.dart';
import 'store.dart';
import 'two_factor.dart';

/// Request passed to an application-owned password-reset delivery callback.
///
/// [token] is the raw one-time secret and must only be used to construct a
/// delivery message. Senders must not log, persist, or include it in events.
final class AuthPasswordResetRequest<TContext> {
  const AuthPasswordResetRequest({
    required this.context,
    required this.user,
    required this.token,
    required this.expiresAt,
  });

  final TContext context;
  final AuthUser user;
  final String token;
  final DateTime expiresAt;
}

/// Application-owned delivery callback for password-reset messages.
typedef AuthPasswordResetSender<TContext> =
    FutureOr<void> Function(AuthPasswordResetRequest<TContext> request);

/// Issues a one-time password-reset token for an existing user.
///
/// The returned raw token is intended only for delivery through a trusted
/// channel. The configured store receives only its digest. Callers handling a
/// public forgot-password request must return the same response whether this
/// returns a token or `null`, so account existence is not disclosed.
Future<String?> issueAuthPasswordResetTokenForUser({
  required AuthStore store,
  required String userId,
  required Duration ttl,
  String Function()? generateToken,
  DateTime? now,
}) async {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) {
    return null;
  }
  final token = generateToken?.call() ?? generateAuthPasswordResetToken();
  final record = buildAuthPasswordResetToken(
    userId: user.id,
    token: token,
    ttl: ttl,
    now: now,
  );
  await Future.sync(() => store.passwordResetTokens.save(record));
  return token;
}

/// Result of successfully replacing a password with a reset token.
class AuthPasswordResetResult {
  const AuthPasswordResetResult({
    required this.user,
    required this.credentialsUpdated,
    required this.sessionsRevoked,
  });

  final AuthUser user;
  final int credentialsUpdated;
  final int sessionsRevoked;
}

/// Consumes a reset token, replaces the user's password, and revokes sessions.
///
/// Password policy validation runs before token consumption so a caller can
/// correct weak input without burning a valid reset link. Once a valid token
/// is consumed, failures are deliberately fail-closed: the token cannot be
/// replayed to retry a potentially partially completed reset.
Future<AuthPasswordResetResult> resetAuthPasswordWithToken({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required String token,
  required String newPassword,
  AuthTwoFactorTrustedDeviceStore? trustedDeviceStore,
  PasswordPolicy passwordPolicy = const PasswordPolicy(),
  DateTime? now,
}) async {
  final passwordError = passwordPolicy.validateRegistration(newPassword);
  if (passwordError != null) {
    throw AuthFlowException(passwordError);
  }

  final consumed = await consumeAuthPasswordResetToken(
    store: store.passwordResetTokens,
    token: token,
  );
  if (consumed == null) {
    throw AuthFlowException('invalid_password_reset_token');
  }

  final user = await Future.sync(() => store.users.findById(consumed.userId));
  if (user == null || user.id.trim().isEmpty) {
    throw AuthFlowException('invalid_password_reset_token');
  }

  final changedAt = (now ?? DateTime.now()).toUtc();
  await trustedDeviceStore?.revokeAll(user.id, now: changedAt);

  // Fail closed before changing credentials: invalidate JWTs and revoke every
  // server-side session first. If either operation fails, the password remains
  // unchanged. Durable adapters may additionally wrap these mutations and the
  // credential replacement in their own transaction.
  await Future.sync(() => store.jwtVersions.rotate(user.id));
  final sessionsRevoked = await Future.sync(
    () => store.sessions.revokeAllForUser(user.id, revokedAt: changedAt),
  );

  final passwordHash = passwordHasher.hash(newPassword);
  if (passwordHash.trim().isEmpty) {
    throw AuthFlowException('password_reset_failed');
  }
  final credentialsUpdated = await Future.sync(
    () => store.credentials.updatePasswordForUser(
      userId: user.id,
      passwordHash: passwordHash,
      updatedAt: changedAt,
    ),
  );
  if (credentialsUpdated <= 0) {
    throw AuthFlowException('password_reset_failed');
  }

  await Future.sync(() => store.passwordResetTokens.deleteForUser(user.id));
  return AuthPasswordResetResult(
    user: user,
    credentialsUpdated: credentialsUpdated,
    sessionsRevoked: sessionsRevoked,
  );
}
