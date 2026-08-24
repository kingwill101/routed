import 'dart:async';

import 'package:server_auth/src/core/exceptions.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/password_hasher.dart';
import 'package:server_auth/src/core/password_policy.dart';
import 'package:server_auth/src/core/store.dart';
import 'package:server_auth/src/core/two_factor.dart';
import 'package:server_auth/src/core/users.dart' show normalizeAuthEmail;

/// Result of successfully changing a user's password.
class AuthPasswordChangeResult {
  /// Creates the result of a password change transaction.
  const AuthPasswordChangeResult({
    required this.user,
    required this.credentialsUpdated,
    required this.sessionsRevoked,
  });

  /// The user whose password was changed.
  final AuthUser user;

  /// Number of credential records updated by the store.
  final int credentialsUpdated;

  /// Number of active sessions revoked by the store.
  final int sessionsRevoked;
}

/// Reauthenticates a user, replaces their password, and revokes all sessions.
///
/// The identifier is supplied separately because a session principal may not
/// contain the credential identifier for custom credential providers. The
/// credential must still belong to [userId], so an identifier cannot be used
/// to change another user's password.
Future<AuthPasswordChangeResult> changeAuthPasswordForUser({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required String userId,
  required String identifier,
  required String currentPassword,
  required String newPassword,
  AuthTwoFactorTrustedDeviceStore? trustedDeviceStore,
  PasswordPolicy passwordPolicy = const PasswordPolicy(),
  DateTime? now,
  FutureOr<void> Function(AuthUser user)? beforeCommit,
}) async {
  final normalizedUserId = userId.trim();
  final normalizedIdentifier = _normalizeIdentifier(identifier);
  if (normalizedUserId.isEmpty || normalizedIdentifier.isEmpty) {
    throw AuthFlowException('invalid_current_password');
  }
  if (currentPassword.isEmpty ||
      !passwordPolicy.allowsAuthentication(currentPassword)) {
    throw AuthFlowException('invalid_current_password');
  }
  final passwordError = passwordPolicy.validateRegistration(newPassword);
  if (passwordError != null) {
    throw AuthFlowException(passwordError);
  }

  final credential = await Future.sync(
    () => store.credentials.findByIdentifier(normalizedIdentifier),
  );
  if (credential == null ||
      !credential.enabled ||
      credential.userId != normalizedUserId ||
      !passwordHasher
          .verify(currentPassword, credential.passwordHash)
          .matches) {
    throw AuthFlowException('invalid_current_password');
  }

  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) {
    throw AuthFlowException('password_change_failed');
  }

  // Policy contributors run only after the current password has been
  // reauthenticated and before any session or credential mutation begins.
  await beforeCommit?.call(user);

  final changedAt = (now ?? DateTime.now()).toUtc();
  await trustedDeviceStore?.revokeAll(normalizedUserId, now: changedAt);

  // Fail closed before changing credentials: invalidate JWTs and revoke every
  // server-side session first. If either operation fails, the password remains
  // unchanged. Durable adapters may additionally transact these mutations.
  await Future.sync(() => store.jwtVersions.rotate(normalizedUserId));
  final sessionsRevoked = await Future.sync(
    () =>
        store.sessions.revokeAllForUser(normalizedUserId, revokedAt: changedAt),
  );

  final passwordHash = passwordHasher.hash(newPassword);
  if (passwordHash.trim().isEmpty) {
    throw AuthFlowException('password_change_failed');
  }
  final credentialsUpdated = await Future.sync(
    () => store.credentials.updatePasswordForUser(
      userId: normalizedUserId,
      passwordHash: passwordHash,
      updatedAt: changedAt,
    ),
  );
  if (credentialsUpdated <= 0) {
    throw AuthFlowException('password_change_failed');
  }

  return AuthPasswordChangeResult(
    user: user,
    credentialsUpdated: credentialsUpdated,
    sessionsRevoked: sessionsRevoked,
  );
}

String _normalizeIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.contains('@')) return normalizeAuthEmail(trimmed);
  return trimmed;
}
