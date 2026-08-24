import 'dart:async';

import 'package:server_auth/src/core/exceptions.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/password_hasher.dart';
import 'package:server_auth/src/core/password_policy.dart';
import 'package:server_auth/src/core/store.dart';
import 'package:server_auth/src/core/tokens.dart' show secureRandomToken;
import 'package:server_auth/src/core/users.dart' show normalizeAuthEmail;

/// Delivery payload for an email-change confirmation.
final class AuthEmailChangeRequest<TContext> {
  /// Creates the transient delivery payload for an email-change message.
  ///
  /// [token] is a raw one-time secret and must be delivered without logging or
  /// persistence. [expiresAt] is the UTC expiry deadline.
  const AuthEmailChangeRequest({
    required this.context,
    required this.user,
    required this.newEmail,
    required this.token,
    required this.expiresAt,
  });

  /// Application context for the delivery operation.
  final TContext context;

  /// User requesting the email change.
  final AuthUser user;

  /// Canonical address awaiting confirmation.
  final String newEmail;

  /// Raw one-time confirmation token.
  final String token;

  /// UTC time after which [token] is invalid.
  final DateTime expiresAt;
}

/// Application-owned delivery callback for email-change confirmations.
/// Sends a transient email-change confirmation payload.
typedef AuthEmailChangeSender<TContext> =
    FutureOr<void> Function(AuthEmailChangeRequest<TContext> request);

/// Result returned by the framework-neutral email-change initiation helper.
final class AuthEmailChangeInitiated {
  /// Creates the result of issuing a pending email-change token.
  const AuthEmailChangeInitiated({
    required this.userId,
    required this.oldEmail,
    required this.newEmail,
    required this.verificationToken,
    required this.expiresAt,
  });

  /// User whose email is being changed.
  final String userId;

  /// Previously stored email address.
  final String oldEmail;

  /// Canonical pending email address.
  final String newEmail;

  /// Raw token for application delivery; never log or persist it.
  final String verificationToken;

  /// UTC token expiry deadline.
  final DateTime expiresAt;
}

/// Result returned after a pending email change is confirmed.
final class AuthEmailChangeConfirmed {
  /// Creates the result of confirming an email change.
  const AuthEmailChangeConfirmed({
    required this.userId,
    required this.oldEmail,
    required this.newEmail,
    required this.sessionsRevoked,
  });

  /// User whose email was changed.
  final String userId;

  /// Email address before confirmation.
  final String oldEmail;

  /// Canonical email address after confirmation.
  final String newEmail;

  /// Number of existing sessions revoked by the compatibility flow.
  final int sessionsRevoked;
}

/// Creates a one-time email-change token after checking ownership and
/// normalized email uniqueness.
///
/// The returned raw token is intended only for transient delivery. [ttl] must
/// produce a future expiry; missing users, invalid or unchanged addresses,
/// duplicate addresses, and empty generated tokens throw [AuthFlowException].
Future<String> issueAuthEmailChangeTokenForUser({
  required AuthStore store,
  required String userId,
  required String newEmail,
  required Duration ttl,
  String Function()? generateToken,
  DateTime? now,
}) async {
  final user = await store.users.findById(userId.trim());
  if (user == null) throw AuthFlowException('not_authenticated');
  final normalizedEmail = normalizeAuthEmail(newEmail);
  if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
    throw AuthFlowException('invalid_email');
  }
  if (normalizedEmail == normalizeAuthEmail(user.email ?? '')) {
    throw AuthFlowException('email_unchanged');
  }
  final existing = await store.users.findByEmail(normalizedEmail);
  if (existing != null && existing.id != user.id) {
    throw AuthFlowException('email_already_in_use');
  }
  final token = generateToken?.call() ?? secureRandomToken();
  if (token.trim().isEmpty) throw AuthFlowException('email_change_failed');
  final issuedAt = (now ?? DateTime.now()).toUtc();
  await store.emailChangeTokens.save(
    AuthEmailChangeToken(
      userId: user.id,
      newEmail: normalizedEmail,
      token: token,
      expiresAt: issuedAt.add(ttl),
    ),
  );
  return token;
}

/// Confirms a one-time email change and returns the updated user.
///
/// Consumption occurs before user binding and optional [expectedNewEmail]
/// checks, so an invalid or raced confirmation cannot be retried. A reused,
/// expired, mismatched, or unavailable token throws [AuthFlowException].
Future<AuthUser> confirmAuthEmailChange({
  required AuthStore store,
  required String userId,
  required String token,
  String? expectedNewEmail,
}) async {
  final consumed = await store.emailChangeTokens.consume(token);
  if (consumed == null || consumed.userId != userId.trim()) {
    throw AuthFlowException('invalid_email_change_token');
  }
  if (expectedNewEmail != null &&
      consumed.newEmail != normalizeAuthEmail(expectedNewEmail)) {
    throw AuthFlowException('invalid_email_change_token');
  }
  final updated = await store.users.updateEmailForUser(
    consumed.userId,
    consumed.newEmail,
  );
  if (updated == null) throw AuthFlowException('email_already_in_use');
  final verified = AuthUser(
    id: updated.id,
    email: updated.email,
    name: updated.name,
    image: updated.image,
    roles: updated.roles,
    attributes: <String, dynamic>{...updated.attributes, 'emailVerified': true},
  );
  return await store.users.update(verified) ?? verified;
}

/// Reauthenticates a password credential without changing it.
///
/// Throws [AuthFlowException] with `reauthentication_required` when the
/// password policy rejects the input or the credential does not match [userId].
Future<void> requireAuthPasswordForUser({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required PasswordPolicy passwordPolicy,
  required String userId,
  required String identifier,
  required String password,
}) async {
  if (password.isEmpty || !passwordPolicy.allowsAuthentication(password)) {
    throw AuthFlowException('reauthentication_required');
  }
  final credential = await store.credentials.findByIdentifier(
    normalizeAuthEmail(identifier),
  );
  if (credential == null ||
      !credential.enabled ||
      credential.userId != userId.trim() ||
      !passwordHasher.verify(password, credential.passwordHash).matches) {
    throw AuthFlowException('reauthentication_required');
  }
}

/// Compatibility flow that reauthenticates and creates a bound pending-email
/// token.
///
/// Applications should deliver
/// [AuthEmailChangeInitiated.verificationToken] through their configured sender
/// and never persist or log the raw value. Invalid credentials, unavailable
/// users, and email conflicts throw [AuthFlowException].
Future<AuthEmailChangeInitiated> initiateEmailChange({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required String userId,
  required String currentPassword,
  required String newEmail,
  Duration ttl = const Duration(hours: 24),
  String Function()? generateToken,
  DateTime? now,
}) async {
  final normalizedUserId = userId.trim();
  final user = await store.users.findById(normalizedUserId);
  if (user == null) throw AuthFlowException('user_not_found');
  final credential = await store.credentials.findByIdentifier(
    normalizeAuthEmail(user.email ?? normalizedUserId),
  );
  if (credential == null ||
      !credential.enabled ||
      credential.userId != normalizedUserId ||
      !passwordHasher
          .verify(currentPassword, credential.passwordHash)
          .matches) {
    throw AuthFlowException('invalid_current_password');
  }
  final issuedAt = (now ?? DateTime.now()).toUtc();
  final token = await issueAuthEmailChangeTokenForUser(
    store: store,
    userId: normalizedUserId,
    newEmail: newEmail,
    ttl: ttl,
    generateToken: generateToken,
    now: issuedAt,
  );
  return AuthEmailChangeInitiated(
    userId: normalizedUserId,
    oldEmail: user.email ?? '',
    newEmail: normalizeAuthEmail(newEmail),
    verificationToken: token,
    expiresAt: issuedAt.add(ttl),
  );
}

/// Confirms a bound pending-email token and revokes existing access.
///
/// [tokenIdentifier] must use the `email_change:<userId>` form. Successful
/// confirmation marks the email verified, revokes all user sessions, and
/// rotates the user's JWT version. Invalid bindings and tokens throw
/// [AuthFlowException].
Future<AuthEmailChangeConfirmed> confirmEmailChange({
  required AuthStore store,
  required String tokenIdentifier,
  required String token,
  required String newEmail,
  DateTime? now,
}) async {
  const prefix = 'email_change:';
  if (!tokenIdentifier.startsWith(prefix)) {
    throw AuthFlowException('invalid_email_change_token');
  }
  final userId = tokenIdentifier.substring(prefix.length).trim();
  final before = await store.users.findById(userId);
  if (before == null) throw AuthFlowException('user_not_found');
  final updated = await confirmAuthEmailChange(
    store: store,
    userId: userId,
    token: token,
    expectedNewEmail: newEmail,
  );
  final changedAt = (now ?? DateTime.now()).toUtc();
  final revoked = await store.sessions.revokeAllForUser(
    userId,
    revokedAt: changedAt,
  );
  await store.jwtVersions.rotate(userId);
  return AuthEmailChangeConfirmed(
    userId: userId,
    oldEmail: before.email ?? '',
    newEmail: updated.email ?? '',
    sessionsRevoked: revoked,
  );
}
