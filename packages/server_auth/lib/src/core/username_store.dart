import 'dart:async';

import 'authentication_methods.dart';
import 'models.dart';

/// Outcome of a store-owned username registration or change transaction.
enum AuthUsernameMutationStatus {
  created,
  changed,
  unchanged,
  conflict,
  notFound,
  userUnavailable,
}

/// Store-confirmed result of a username transaction.
final class AuthUsernameMutationResult {
  const AuthUsernameMutationResult({
    required this.status,
    this.user,
    this.credential,
  });

  final AuthUsernameMutationStatus status;
  final AuthUser? user;
  final AuthPasswordCredential? credential;

  bool get succeeded =>
      status == AuthUsernameMutationStatus.created ||
      status == AuthUsernameMutationStatus.changed ||
      status == AuthUsernameMutationStatus.unchanged;
}

/// Complete input to an atomic username registration.
final class AuthUsernameRegistrationCommand {
  AuthUsernameRegistrationCommand({
    required this.user,
    required this.credential,
  }) {
    if (credential.userId != user.id ||
        credential.identifier.trim() != credential.identifier ||
        credential.identifier.isEmpty ||
        credential.identifier.contains('@') ||
        user.attributes['username'] != credential.identifier) {
      throw ArgumentError(
        'Username registration requires one canonical owned credential.',
      );
    }
  }

  final AuthUser user;
  final AuthPasswordCredential credential;
}

/// Complete input to an atomic username change.
final class AuthUsernameChangeCommand {
  AuthUsernameChangeCommand({
    required this.userId,
    required this.credentialId,
    required this.expectedUsername,
    required this.username,
    required this.updatedAt,
  }) {
    for (final (name, value) in <(String, String)>[
      ('userId', userId),
      ('credentialId', credentialId),
      ('expectedUsername', expectedUsername),
      ('username', username),
    ]) {
      if (value.isEmpty || value.trim() != value) {
        throw ArgumentError.value(
          value,
          name,
          'must be canonical and non-empty',
        );
      }
    }
    if (expectedUsername.contains('@') || username.contains('@')) {
      throw ArgumentError('Username identifiers must not contain @.');
    }
  }

  final String userId;
  final String credentialId;
  final String expectedUsername;
  final String username;
  final DateTime updatedAt;
}

/// Complete input to an atomic username removal.
final class AuthUsernameRemovalCommand {
  AuthUsernameRemovalCommand({
    required this.userId,
    required this.credentialId,
    required this.loadInventory,
  }) {
    for (final (name, value) in <(String, String)>[
      ('userId', userId),
      ('credentialId', credentialId),
    ]) {
      if (value.isEmpty || value.trim() != value) {
        throw ArgumentError.value(
          value,
          name,
          'must be canonical and non-empty',
        );
      }
    }
  }

  final String userId;
  final String credentialId;

  /// Loads the complete composed topology inside the backend-owned command.
  ///
  /// This is evidence for the command, not a callback transaction. Durable
  /// backends must recheck every supported fallback in their own transaction.
  final AuthAuthenticationMethodInventoryLoader loadInventory;
}

/// Root-store capability required by the opt-in username plugin.
///
/// Implementations own the transaction boundary spanning the canonical
/// username reservation, password credential, and public user projection.
/// Durable adapters must enforce identifier uniqueness with database indexes
/// in the same serializable transaction. They must not emulate this contract
/// with plugin-side find/remove/write sequences.
///
/// Registration conflicts return [AuthUsernameMutationStatus.conflict] without
/// leaving a user or credential behind. A repeated successful change to the
/// same target returns [AuthUsernameMutationStatus.unchanged].
abstract interface class AuthUsernameStore {
  FutureOr<AuthUsernameMutationResult> registerUsername(
    AuthUsernameRegistrationCommand command,
  );

  FutureOr<AuthUsernameMutationResult> changeUsername(
    AuthUsernameChangeCommand command,
  );

  FutureOr<AuthPasswordCredential?> findUsernameForUser(String userId);

  FutureOr<AuthPasswordCredential?> findByUsername(String username);

  /// Removes the exact username credential only when another usable method
  /// remains.
  ///
  /// [AuthUsernameRemovalCommand.loadInventory] supplies a bounded topology
  /// snapshot; it is not authorization to use a callback transaction. Durable
  /// adapters must recheck every supported fallback in their own transaction
  /// and return [AuthAuthenticationMethodMutationResult.atomicityUnavailable]
  /// when the composed topology cannot join that transaction.
  FutureOr<AuthAuthenticationMethodMutationResult> removeUsernameIfSafe(
    AuthUsernameRemovalCommand command,
  );
}

/// Deterministic fault points exposed by the in-memory adapter for conformance.
enum AuthUsernameFaultPoint {
  registrationAfterUserWrite,
  changeAfterCredentialWrite,
  changeAfterUserWrite,
  removalAfterUserWrite,
  removalAfterCredentialWrite,
}

typedef AuthUsernameFaultInjector =
    FutureOr<void> Function(AuthUsernameFaultPoint point);
