import 'dart:async';

import 'package:server_auth/src/core/deletion_transaction.dart';
import 'package:server_auth/src/core/exceptions.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/password_hasher.dart';
import 'package:server_auth/src/core/store.dart';
import 'package:server_auth/src/core/tokens.dart' show secureRandomToken;

/// Request for initiating account deletion.
class AuthAccountDeletionRequest {
  /// Creates an instance of AuthAccountDeletionRequest.
  const AuthAccountDeletionRequest({
    required this.userId,
    required this.password,
  });

  /// ID of the user requesting deletion.
  final String userId;

  /// Password for reauthentication.
  final String password;
}

/// Result of initiating account deletion.
class AuthAccountDeletionInitiated {
  /// Creates an instance of AuthAccountDeletionInitiated.
  const AuthAccountDeletionInitiated({
    required this.userId,
    required this.email,
    required this.confirmationToken,
    required this.expiresAt,
  });

  /// ID of the user.
  final String userId;

  /// Email address for confirmation delivery.
  final String? email;

  /// Raw confirmation token (for delivery only).
  final String confirmationToken;

  /// When the confirmation token expires.
  final DateTime expiresAt;
}

/// Result of confirming account deletion.
class AuthAccountDeletionConfirmed {
  /// Creates an instance of AuthAccountDeletionConfirmed.
  const AuthAccountDeletionConfirmed({
    required this.userId,
    required this.deleted,
  });

  /// ID of the user that was deleted.
  final String userId;

  /// Whether the deletion was successful.
  final bool deleted;
}

/// Application delivery payload for account-deletion confirmation.
final class AuthAccountDeletionDelivery<TContext> {
  /// Creates an instance of AuthAccountDeletionDelivery.
  const AuthAccountDeletionDelivery({
    required this.context,
    required this.user,
    required this.token,
    required this.expiresAt,
  });

  /// The host context associated with this operation.
  final TContext context;

  /// The user associated with this value.
  final AuthUser user;

  /// The token used for token.
  final String token;

  /// The time at which expires occurred.
  final DateTime expiresAt;
}

/// Callback that sends auth account deletion sender.
typedef AuthAccountDeletionSender<TContext> =
    FutureOr<void> Function(AuthAccountDeletionDelivery<TContext> delivery);

/// Initiates account deletion with reauthentication.
///
/// The user must provide their password. A confirmation token is sent to
/// their email. The account is not deleted until the token is confirmed.
Future<AuthAccountDeletionInitiated> initiateAccountDeletion({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required String userId,
  required String password,
  Duration ttl = const Duration(hours: 24),
  String Function()? generateToken,
  DateTime? now,
}) async {
  final normalizedUserId = userId.trim();

  if (normalizedUserId.isEmpty) {
    throw AuthFlowException('invalid_request');
  }

  // Find the user
  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) {
    throw AuthFlowException('user_not_found');
  }

  // Reauthenticate with password
  final credential = await findAuthCredentialForUser(store, normalizedUserId);
  if (credential == null ||
      !credential.enabled ||
      credential.userId != normalizedUserId ||
      !passwordHasher.verify(password, credential.passwordHash).matches) {
    throw AuthFlowException('invalid_password');
  }

  // Generate confirmation token
  final token = generateToken?.call() ?? secureRandomToken();
  final expiresAt = (now ?? DateTime.now()).toUtc().add(ttl);

  // Store confirmation token
  await Future.sync(
    () => store.verificationTokens.save(
      AuthVerificationToken(
        identifier: 'account_deletion:$normalizedUserId',
        token: token,
        expiresAt: expiresAt,
      ),
    ),
  );

  return AuthAccountDeletionInitiated(
    userId: normalizedUserId,
    email: user.email,
    confirmationToken: token,
    expiresAt: expiresAt,
  );
}

/// Confirms and executes account deletion.
///
/// This deletes the user and all associated data. This operation cannot
/// be undone.
Future<AuthAccountDeletionConfirmed> confirmAccountDeletion({
  required AuthStore store,
  required String userId,
  required String token,
  DateTime? now,
}) async {
  final normalizedUserId = userId.trim();

  if (normalizedUserId.isEmpty) {
    throw AuthFlowException('invalid_request');
  }

  final deletionStore = store is AuthUserDeletionCoordinatorHost
      ? store as AuthUserDeletionCoordinatorHost
      : null;
  if (deletionStore == null) {
    throw AuthFlowException('account_deletion_unavailable');
  }
  final deleted = await deletionStore.userDeletionCoordinator
      .confirmAndDeleteUser(userId: normalizedUserId, token: token, now: now);
  if (!deleted) {
    throw AuthFlowException('invalid_deletion_token');
  }

  return AuthAccountDeletionConfirmed(
    userId: normalizedUserId,
    deleted: deleted,
  );
}
