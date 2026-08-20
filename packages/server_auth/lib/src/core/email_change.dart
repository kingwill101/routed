import 'dart:async';

import 'exceptions.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'store.dart';
import 'tokens.dart' show secureRandomToken;
import 'users.dart' show normalizeAuthEmail;

/// Delivery payload for an email-change confirmation.
final class AuthEmailChangeRequest<TContext> {
  const AuthEmailChangeRequest({
    required this.context,
    required this.user,
    required this.newEmail,
    required this.token,
    required this.expiresAt,
  });

  final TContext context;
  final AuthUser user;
  final String newEmail;
  final String token;
  final DateTime expiresAt;
}

/// Application-owned delivery callback for email-change confirmations.
typedef AuthEmailChangeSender<TContext> =
    FutureOr<void> Function(AuthEmailChangeRequest<TContext> request);

/// Creates a one-time email-change token after checking ownership and
/// normalized email uniqueness.
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
  if (normalizedEmail.isEmpty) throw AuthFlowException('invalid_email');
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
Future<AuthUser> confirmAuthEmailChange({
  required AuthStore store,
  required String userId,
  required String token,
}) async {
  final consumed = await store.emailChangeTokens.consume(token);
  if (consumed == null || consumed.userId != userId.trim()) {
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
    attributes: <String, dynamic>{
      ...updated.attributes,
      'emailVerified': true,
    },
  );
  return await store.users.update(verified) ?? verified;
}

/// Reauthenticates a password credential without changing it.
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
