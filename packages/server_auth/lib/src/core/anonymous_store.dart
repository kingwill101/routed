import 'dart:async';

import 'package:server_auth/src/core/models.dart';

/// Outcome of one backend-owned anonymous-account mutation.
enum AuthAnonymousMutationStatus {
  /// A value representing applied.
  applied,

  /// A value representing replayed.
  replayed,

  /// A value representing not found.
  notFound,

  /// A value representing not anonymous.
  notAnonymous,

  /// A value representing replay mismatch.
  replayMismatch,
}

/// Result returned by an anonymous-account mutation backend.
final class AuthAnonymousMutationResult {
  /// Creates an instance of AuthAnonymousMutationResult.
  const AuthAnonymousMutationResult(this.status, {this.user});

  /// The status associated with this value.
  final AuthAnonymousMutationStatus status;

  /// The user associated with this value.
  final AuthUser? user;

  /// The committed exposed by this component.
  bool get committed =>
      status == AuthAnonymousMutationStatus.applied ||
      status == AuthAnonymousMutationStatus.replayed;
}

/// Creates one anonymous identity.
///
/// Repeating the exact command while the account exists must return
/// [AuthAnonymousMutationStatus.replayed] with the original user. Hard
/// deletion revokes and scrubs that receipt while keeping the user ID
/// unavailable. Reusing [operationId] for another payload must fail with
/// [AuthAnonymousMutationStatus.replayMismatch].
final class AuthAnonymousCreateAccountCommand {
  /// Creates an instance of AuthAnonymousCreateAccountCommand.
  AuthAnonymousCreateAccountCommand({
    required String operationId,
    required this.user,
  }) : operationId = validateAuthAnonymousOperationId(operationId) {
    validateAuthAnonymousUser(user);
  }

  /// The identifier of operation.
  final String operationId;

  /// The user associated with this value.
  final AuthUser user;
}

/// Deletes an authenticated anonymous identity and all user-owned auth data.
final class AuthAnonymousDeleteAccountCommand {
  /// Creates an instance of AuthAnonymousDeleteAccountCommand.
  AuthAnonymousDeleteAccountCommand({
    required String operationId,
    required String userId,
  }) : operationId = validateAuthAnonymousOperationId(operationId),
       userId = validateAuthAnonymousUserId(userId);

  /// The identifier of operation.
  final String operationId;

  /// The identifier of the user.
  final String userId;
}

/// Finalizes an anonymous-to-authenticated account upgrade.
///
/// Session issuance is deliberately absent. The framework host authenticates
/// [targetUserId] and issues its replacement session before submitting this
/// command. The backend atomically validates and removes the anonymous source
/// and its user-owned auth data while binding replay success to the host-
/// authenticated target ID. The target need not be stored by JWT-only hosts.
final class AuthAnonymousCompleteUpgradeCommand {
  /// Creates an instance of AuthAnonymousCompleteUpgradeCommand.
  AuthAnonymousCompleteUpgradeCommand({
    required String operationId,
    required String anonymousUserId,
    required String targetUserId,
  }) : operationId = validateAuthAnonymousOperationId(operationId),
       anonymousUserId = validateAuthAnonymousUserId(anonymousUserId),
       targetUserId = validateAuthAnonymousUserId(targetUserId) {
    if (this.anonymousUserId == this.targetUserId) {
      throw ArgumentError.value(
        targetUserId,
        'targetUserId',
        'must differ from anonymousUserId',
      );
    }
  }

  /// The identifier of operation.
  final String operationId;

  /// The identifier of anonymous user.
  final String anonymousUserId;

  /// The identifier of target user.
  final String targetUserId;
}

/// Optional persistence capability required by `AnonymousPlugin`.
///
/// Durable implementations must execute each method in a real backend
/// transaction and persist operation receipts in the same transaction as the
/// mutation. Deletion and upgrade must scrub creation receipts containing user
/// data; their retained replay receipts may contain only non-reversible
/// operation bindings. Implementations must never fall back to process-local
/// state when the root auth topology is durable.
abstract interface class AuthAnonymousAccountMutationStore {
  /// Creates anonymous account.
  FutureOr<AuthAnonymousMutationResult> createAnonymousAccount(
    AuthAnonymousCreateAccountCommand command,
  );

  /// Deletes anonymous account.
  FutureOr<AuthAnonymousMutationResult> deleteAnonymousAccount(
    AuthAnonymousDeleteAccountCommand command,
  );

  /// Completes anonymous account upgrade.
  FutureOr<AuthAnonymousMutationResult> completeAnonymousAccountUpgrade(
    AuthAnonymousCompleteUpgradeCommand command,
  );
}

/// Fault points exposed by the process-local implementation for rollback tests.
enum AuthAnonymousInMemoryFaultPoint {
  /// A value representing after create write.
  afterCreateWrite,
}

/// Callback that injects auth anonymous in memory fault injector.
typedef AuthAnonymousInMemoryFaultInjector =
    FutureOr<void> Function(AuthAnonymousInMemoryFaultPoint point);

/// Validates auth anonymous operation id.
String validateAuthAnonymousOperationId(String value) =>
    _validateBoundedIdentifier(value, 'operationId');

/// Validates auth anonymous user id.
String validateAuthAnonymousUserId(String value) =>
    _validateBoundedIdentifier(value, 'userId');

/// Normalizes an optional generated display name before persistence.
String? normalizeAuthAnonymousDisplayName(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  if (normalized.length > 128 || _containsControlCharacter(normalized)) {
    throw ArgumentError.value(
      value,
      'name',
      'must contain at most 128 non-control characters',
    );
  }
  return normalized;
}

/// Validates auth anonymous user.
void validateAuthAnonymousUser(AuthUser user) {
  validateAuthAnonymousUserId(user.id);
  if (!user.isAnonymous) {
    throw ArgumentError.value(user, 'user', 'must be anonymous');
  }
  if (user.email != null) {
    throw ArgumentError.value(user.email, 'user.email', 'must be absent');
  }
  if (user.image != null ||
      user.roles.isNotEmpty ||
      user.attributes.isNotEmpty) {
    throw ArgumentError.value(
      user,
      'user',
      'must not carry an image, roles, or arbitrary attributes',
    );
  }
  normalizeAuthAnonymousDisplayName(user.name);
}

String _validateBoundedIdentifier(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized != value ||
      normalized.length > 256 ||
      _containsControlCharacter(normalized)) {
    throw ArgumentError.value(
      value,
      name,
      'must be 1 to 256 trimmed non-control characters',
    );
  }
  return normalized;
}

bool _containsControlCharacter(String value) =>
    value.runes.any((rune) => rune < 0x20 || rune == 0x7f);
