import 'dart:async';

import 'authentication_methods.dart';
import 'deletion_transaction.dart';
import 'models.dart';
import 'providers.dart';

/// The WebAuthn ceremony for which a challenge was issued.
enum AuthWebAuthnCeremony { registration, authentication }

/// A persisted, one-time WebAuthn challenge.
///
/// The raw challenge is returned only to the browser. Stores receive its
/// digest through [challengeHash], so a database dump cannot be used as a
/// ready-to-submit ceremony response.
final class AuthWebAuthnChallenge {
  const AuthWebAuthnChallenge({
    required this.id,
    required this.challengeHash,
    required this.ceremony,
    required this.relyingPartyId,
    required this.origin,
    required this.createdAt,
    required this.expiresAt,
    this.userId,
  });

  final String id;
  final String challengeHash;
  final AuthWebAuthnCeremony ceremony;
  final String relyingPartyId;
  final String origin;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? userId;

  bool isActive({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return !current.isBefore(createdAt.toUtc()) &&
        current.isBefore(expiresAt.toUtc());
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'ceremony': ceremony.name,
    'relyingPartyId': relyingPartyId,
    'origin': origin,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'userId': userId,
  };
}

/// Persistence boundary for one-time WebAuthn challenges.
abstract interface class AuthWebAuthnChallengeStore {
  FutureOr<void> save(AuthWebAuthnChallenge challenge);

  /// Removes every pending challenge bound to [userId].
  ///
  /// Durable implementations must include this operation in the same account
  /// deletion transaction as the user's authenticators and core auth data.
  FutureOr<void> deleteForUser(String userId);

  /// Atomically consumes a matching, active challenge.
  ///
  /// Implementations must remove the challenge before returning it. A
  /// challenge bound to a user cannot be consumed without the same [userId].
  FutureOr<AuthWebAuthnChallenge?> consume({
    required String challengeHash,
    required AuthWebAuthnCeremony ceremony,
    required String relyingPartyId,
    required String origin,
    String? userId,
    DateTime? now,
  });
}

/// Persistence boundary for registered passkeys.
abstract interface class AuthWebAuthnAuthenticatorStore {
  FutureOr<WebAuthnAuthenticator?> findByCredentialId(String credentialId);

  FutureOr<List<WebAuthnAuthenticator>> listForUser(String userId);

  /// Creates a credential and rejects duplicate credential IDs.
  FutureOr<WebAuthnAuthenticator> create(WebAuthnAuthenticator authenticator);

  /// Atomically advances the signature counter and last-used timestamp.
  ///
  /// The update must succeed only when the stored counter still equals
  /// [expectedCounter]. This prevents concurrent assertions from racing past
  /// the replay check.
  FutureOr<WebAuthnAuthenticator?> updateUsage({
    required String credentialId,
    required int expectedCounter,
    required int newCounter,
    required DateTime lastUsedAt,
  });

  /// Removes a credential only when it belongs to [userId].
  FutureOr<bool> deleteForUser(String userId, String credentialId);

  /// Renames a credential only when it belongs to [userId].
  FutureOr<WebAuthnAuthenticator?> renameForUser(
    String userId,
    String credentialId,
    String name,
  );
}

/// Complete input to an exact passkey-removal transaction.
final class AuthWebAuthnCredentialRemovalCommand {
  AuthWebAuthnCredentialRemovalCommand({
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

  /// Loads the bounded composed topology as evidence for the backend command.
  ///
  /// Durable backends must recheck every supported fallback inside their own
  /// transaction. This callback is not itself a transaction boundary.
  final AuthAuthenticationMethodInventoryLoader loadInventory;
}

/// Optional exact transaction for removing a passkey safely.
///
/// Stores that cannot join the complete authentication-method topology must
/// return [AuthAuthenticationMethodMutationResult.atomicityUnavailable].
abstract interface class AuthWebAuthnAuthenticatorMutationStore {
  FutureOr<AuthAuthenticationMethodMutationResult> removeCredentialIfSafe(
    AuthWebAuthnCredentialRemovalCommand command,
  );
}

/// Optional persistence capability required by the WebAuthn plugin.
///
/// Keeping these stores outside the base auth store lets existing adapters
/// continue to implement core authentication without opting into passkeys.
abstract interface class AuthWebAuthnStoreCapabilities {
  AuthWebAuthnChallengeStore get webAuthnChallenges;

  AuthWebAuthnAuthenticatorStore get webAuthnAuthenticators;
}

/// Optional backend-owned hard-deletion plan for both WebAuthn stores.
///
/// This capability belongs on the object that owns the complete challenge and
/// authenticator persistence domain. It is intentionally separate from each
/// individual store so split or mixed durable storage cannot claim one atomic
/// deletion boundary.
abstract interface class AuthWebAuthnUserDeletionPlanFactory {
  FutureOr<AuthUserDeletionPlan> createWebAuthnDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  });
}

/// In-memory WebAuthn stores for tests and local development.
///
/// Production applications must provide durable implementations with the
/// same atomic consume, unique credential, and compare-and-set guarantees.
final class InMemoryAuthWebAuthnChallengeStore
    implements AuthWebAuthnChallengeStore, AuthInMemoryUserDeletionStore {
  InMemoryAuthWebAuthnChallengeStore({this.maxEntries = 1024})
    : assert(maxEntries > 0);

  final int maxEntries;
  final Map<String, AuthWebAuthnChallenge> _records =
      <String, AuthWebAuthnChallenge>{};

  @override
  Object captureDeletionState() =>
      Map<String, AuthWebAuthnChallenge>.of(_records);

  @override
  void restoreDeletionState(Object checkpoint) {
    final records = checkpoint as Map<String, AuthWebAuthnChallenge>;
    _records
      ..clear()
      ..addAll(records);
  }

  @override
  Future<void> save(AuthWebAuthnChallenge challenge) async {
    _validateChallenge(challenge);
    final now = DateTime.now().toUtc();
    _records.removeWhere((_, value) => !value.isActive(now: now));
    if (_records.containsKey(challenge.challengeHash)) {
      throw StateError('WebAuthn challenge hash already exists');
    }
    while (_records.length >= maxEntries) {
      _records.remove(_records.keys.first);
    }
    _records[challenge.challengeHash] = challenge;
  }

  @override
  Future<AuthWebAuthnChallenge?> consume({
    required String challengeHash,
    required AuthWebAuthnCeremony ceremony,
    required String relyingPartyId,
    required String origin,
    String? userId,
    DateTime? now,
  }) async {
    final record = _records[challengeHash.trim()];
    if (record == null || !record.isActive(now: now)) {
      if (record != null) _records.remove(challengeHash.trim());
      return null;
    }
    if (record.ceremony != ceremony ||
        record.relyingPartyId != relyingPartyId ||
        record.origin != origin ||
        record.userId != userId) {
      return null;
    }
    _records.remove(challengeHash.trim());
    return record;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) return;
    _records.removeWhere((_, record) => record.userId == normalized);
  }

  @override
  Future<void> deleteUserDataForDeletion(String userId) =>
      deleteForUser(userId);
}

/// In-memory registered-passkey store for tests and local development.
final class InMemoryAuthWebAuthnAuthenticatorStore
    implements AuthWebAuthnAuthenticatorStore, AuthInMemoryUserDeletionStore {
  final Map<String, WebAuthnAuthenticator> _records =
      <String, WebAuthnAuthenticator>{};

  @override
  Object captureDeletionState() =>
      Map<String, WebAuthnAuthenticator>.of(_records);

  @override
  void restoreDeletionState(Object checkpoint) {
    final records = checkpoint as Map<String, WebAuthnAuthenticator>;
    _records
      ..clear()
      ..addAll(records);
  }

  @override
  Future<WebAuthnAuthenticator?> findByCredentialId(String credentialId) async {
    final normalized = credentialId.trim();
    if (normalized.isEmpty) return null;
    return _records[normalized];
  }

  @override
  Future<List<WebAuthnAuthenticator>> listForUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) return const <WebAuthnAuthenticator>[];
    return _records.values
        .where((record) => record.userId == normalized)
        .toList(growable: false);
  }

  @override
  Future<WebAuthnAuthenticator> create(
    WebAuthnAuthenticator authenticator,
  ) async {
    _validateAuthenticator(authenticator);
    if (_records.containsKey(authenticator.credentialId)) {
      throw StateError('WebAuthn credential already exists');
    }
    _records[authenticator.credentialId] = authenticator;
    return authenticator;
  }

  @override
  Future<WebAuthnAuthenticator?> updateUsage({
    required String credentialId,
    required int expectedCounter,
    required int newCounter,
    required DateTime lastUsedAt,
  }) async {
    if (credentialId.trim().isEmpty ||
        expectedCounter < 0 ||
        newCounter < expectedCounter) {
      return null;
    }
    final current = _records[credentialId];
    if (current == null || current.counter != expectedCounter) return null;
    if (current.createdAt case final createdAt?
        when lastUsedAt.toUtc().isBefore(createdAt.toUtc())) {
      return null;
    }
    final previousLastUsed = current.lastUsedAt;
    final updated = WebAuthnAuthenticator(
      credentialId: current.credentialId,
      publicKey: current.publicKey,
      counter: newCounter,
      userId: current.userId,
      transports: current.transports,
      createdAt: current.createdAt,
      lastUsedAt:
          previousLastUsed == null || lastUsedAt.isAfter(previousLastUsed)
          ? lastUsedAt.toUtc()
          : previousLastUsed,
      name: current.name,
    );
    _records[credentialId] = updated;
    return updated;
  }

  @override
  Future<bool> deleteForUser(String userId, String credentialId) async {
    final normalizedUserId = userId.trim();
    final normalizedCredentialId = credentialId.trim();
    final current = _records[normalizedCredentialId];
    if (normalizedUserId.isEmpty || current?.userId != normalizedUserId) {
      return false;
    }
    _records.remove(normalizedCredentialId);
    return true;
  }

  @override
  Future<void> deleteUserDataForDeletion(String userId) async {
    final records = await listForUser(userId);
    for (final record in records) {
      await deleteForUser(userId, record.credentialId);
    }
  }

  @override
  Future<WebAuthnAuthenticator?> renameForUser(
    String userId,
    String credentialId,
    String name,
  ) async {
    final normalizedUserId = userId.trim();
    final normalizedCredentialId = credentialId.trim();
    final normalizedName = name.trim();
    final current = _records[normalizedCredentialId];
    if (normalizedUserId.isEmpty ||
        normalizedCredentialId.isEmpty ||
        normalizedName.isEmpty ||
        current?.userId != normalizedUserId) {
      return null;
    }
    final updated = WebAuthnAuthenticator(
      credentialId: current!.credentialId,
      publicKey: current.publicKey,
      counter: current.counter,
      userId: current.userId,
      transports: current.transports,
      createdAt: current.createdAt,
      lastUsedAt: current.lastUsedAt,
      name: normalizedName,
    );
    _records[normalizedCredentialId] = updated;
    return updated;
  }
}

void _validateChallenge(AuthWebAuthnChallenge challenge) {
  if (challenge.id.trim().isEmpty ||
      challenge.challengeHash.trim().isEmpty ||
      challenge.relyingPartyId.trim().isEmpty ||
      challenge.origin.trim().isEmpty) {
    throw ArgumentError('WebAuthn challenge fields must not be empty');
  }
  if (challenge.userId?.trim().isEmpty == true) {
    throw ArgumentError('WebAuthn challenge userId must not be empty');
  }
  if (!challenge.expiresAt.toUtc().isAfter(challenge.createdAt.toUtc())) {
    throw ArgumentError('WebAuthn challenge must expire after creation');
  }
}

void _validateAuthenticator(WebAuthnAuthenticator authenticator) {
  if (authenticator.credentialId.trim().isEmpty ||
      authenticator.publicKey.trim().isEmpty ||
      authenticator.userId?.trim().isEmpty == true ||
      authenticator.userId == null ||
      authenticator.createdAt == null ||
      authenticator.counter < 0) {
    throw ArgumentError('Invalid WebAuthn authenticator');
  }
}
