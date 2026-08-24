import 'dart:async';

import 'authentication_methods.dart';
import 'models.dart';

/// Outcome of a store-owned username registration or change transaction.
enum AuthUsernameMutationStatus {
  /// A username credential was created.
  created,

  /// An existing username credential was changed.
  changed,

  /// The requested change already matched the stored username.
  unchanged,

  /// The requested username is already owned by another account.
  conflict,

  /// The referenced user or credential was not found.
  notFound,

  /// The user cannot accept another username credential.
  userUnavailable,
}

/// Store-confirmed result of a username transaction.
final class AuthUsernameMutationResult {
  /// Creates the outcome of a username store transaction.
  const AuthUsernameMutationResult({
    required this.status,
    this.user,
    this.credential,
  });

  /// Transaction outcome.
  final AuthUsernameMutationStatus status;

  /// User projection returned by the store, when available.
  final AuthUser? user;

  /// Username credential returned by the store, when available.
  final AuthPasswordCredential? credential;

  /// Whether the transaction created, changed, or preserved a credential.
  bool get succeeded =>
      status == AuthUsernameMutationStatus.created ||
      status == AuthUsernameMutationStatus.changed ||
      status == AuthUsernameMutationStatus.unchanged;
}

/// Complete input to an atomic username registration.
final class AuthUsernameRegistrationCommand {
  /// Creates a validated atomic username-registration command.
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

  /// User projection to create alongside the credential.
  final AuthUser user;

  /// Canonical username credential owned by [user].
  final AuthPasswordCredential credential;
}

/// Complete input to an atomic username change.
final class AuthUsernameChangeCommand {
  /// Creates a validated atomic username-change command.
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

  /// Identifier of the user changing the username.
  final String userId;

  /// Identifier of the username credential being changed.
  final String credentialId;

  /// Username that must still be stored when the transaction begins.
  final String expectedUsername;

  /// New canonical username.
  final String username;

  /// Timestamp written to changed records.
  final DateTime updatedAt;
}

/// Complete input to an atomic username removal.
final class AuthUsernameRemovalCommand {
  /// Creates a validated atomic username-removal command.
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

  /// Identifier of the user removing the username.
  final String userId;

  /// Identifier of the username credential being removed.
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
  /// Registers a username and its password credential atomically.
  FutureOr<AuthUsernameMutationResult> registerUsername(
    AuthUsernameRegistrationCommand command,
  );

  /// Changes a username while preserving uniqueness atomically.
  FutureOr<AuthUsernameMutationResult> changeUsername(
    AuthUsernameChangeCommand command,
  );

  /// Finds the username credential owned by [userId].
  FutureOr<AuthPasswordCredential?> findUsernameForUser(String userId);

  /// Finds a username credential by its canonical username.
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
  /// Fault after a registration user write.
  registrationAfterUserWrite,

  /// Fault after a change credential write.
  changeAfterCredentialWrite,

  /// Fault after a change user write.
  changeAfterUserWrite,

  /// Fault after a removal user write.
  removalAfterUserWrite,

  /// Fault after a removal credential write.
  removalAfterCredentialWrite,
}

/// Callback used by the in-memory username store to inject failures.
typedef AuthUsernameFaultInjector =
    FutureOr<void> Function(AuthUsernameFaultPoint point);
