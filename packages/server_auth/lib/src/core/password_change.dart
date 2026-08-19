import 'exceptions.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'store.dart';
import 'two_factor.dart';
import 'users.dart' show normalizeAuthEmail;

/// Result of successfully changing a user's password.
class AuthPasswordChangeResult {
  const AuthPasswordChangeResult({
    required this.user,
    required this.credentialsUpdated,
    required this.sessionsRevoked,
  });

  final AuthUser user;
  final int credentialsUpdated;
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

  final changedAt = (now ?? DateTime.now()).toUtc();
  await trustedDeviceStore?.revokeAll(normalizedUserId, now: changedAt);

  // Rotate before changing credentials so an error after this point still
  // invalidates previously issued JWTs. Durable stores should perform this
  // alongside the credential update in their persistence transaction.
  await Future.sync(() => store.jwtVersions.rotate(normalizedUserId));

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

  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) {
    throw AuthFlowException('password_change_failed');
  }
  final sessionsRevoked = await Future.sync(
    () =>
        store.sessions.revokeAllForUser(normalizedUserId, revokedAt: changedAt),
  );
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
