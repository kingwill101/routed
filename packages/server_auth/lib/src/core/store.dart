import 'dart:async';
import 'dart:convert';

import 'package:server_auth/src/core/account_policy.dart';
import 'package:server_auth/src/core/anonymous_store.dart';
import 'package:server_auth/src/core/authentication_methods.dart';
import 'package:server_auth/src/core/deletion_transaction.dart';
import 'package:server_auth/src/core/device_authorization_store.dart';
import 'package:server_auth/src/core/email_auth_backend.dart';
import 'package:server_auth/src/core/email_change_token_store.dart';
import 'package:server_auth/src/core/email_otp_store.dart';
import 'package:server_auth/src/core/jwt_version_store.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/oauth_challenge_store.dart';
import 'package:server_auth/src/core/password_reset_token_store.dart';
import 'package:server_auth/src/core/phone_number_store.dart';
import 'package:server_auth/src/core/tokens.dart'
    show constantTimeStringEquals, hashOpaqueToken;
import 'package:server_auth/src/core/username_store.dart';
import 'package:server_auth/src/core/users.dart';
import 'package:server_auth/src/core/verification_token_store.dart';
import 'package:server_auth/src/core/webauthn_store.dart';

/// Result of an atomic user create-or-find operation.
class AuthUserCreateResult {
  /// Creates the result of an atomic user create-or-find operation.
  const AuthUserCreateResult({required this.user, required this.created});

  /// The canonical user returned by the store.
  final AuthUser user;

  /// Whether this call created the returned user.
  final bool created;
}

/// Validates a user before it crosses a persistence boundary.
void validateAuthUserForPersistence(AuthUser user) {
  if (user.id.trim().isEmpty) {
    throw ArgumentError.value(user.id, 'user.id', 'must be non-empty');
  }
}

/// Validates an external account before it is linked to a local user.
void validateAuthAccountForLink(AuthAccount account) {
  if (account.providerId.trim().isEmpty) {
    throw ArgumentError.value(
      account.providerId,
      'account.providerId',
      'must be non-empty',
    );
  }
  if (account.providerAccountId.trim().isEmpty) {
    throw ArgumentError.value(
      account.providerAccountId,
      'account.providerAccountId',
      'must be non-empty',
    );
  }
  final userId = account.userId;
  if (userId == null || userId.trim().isEmpty) {
    throw ArgumentError.value(
      account.userId,
      'account.userId',
      'must identify the local user being linked',
    );
  }
}

/// Validates a session record before it is persisted.
void validateAuthSessionForPersistence(AuthSessionRecord session) {
  if (session.id.trim().isEmpty) {
    throw ArgumentError.value(session.id, 'session.id', 'must be non-empty');
  }
  if (session.tokenHash.trim().isEmpty) {
    throw ArgumentError.value(
      session.tokenHash,
      'session.tokenHash',
      'must be non-empty',
    );
  }
  if (session.userId.trim().isEmpty) {
    throw ArgumentError.value(
      session.userId,
      'session.userId',
      'must be non-empty',
    );
  }
  if (session.authenticationMethod.trim().isEmpty) {
    throw ArgumentError.value(
      session.authenticationMethod,
      'session.authenticationMethod',
      'must be non-empty',
    );
  }
  if (!session.expiresAt.isAfter(session.createdAt)) {
    throw ArgumentError.value(
      session.expiresAt,
      'session.expiresAt',
      'must be after createdAt',
    );
  }
  if (session.lastUsedAt.isBefore(session.createdAt)) {
    throw ArgumentError.value(
      session.lastUsedAt,
      'session.lastUsedAt',
      'must not be before createdAt',
    );
  }
}

/// Persistence contract for user records.
abstract interface class AuthUserStore {
  /// Finds a user by its stable identifier.
  FutureOr<AuthUser?> findById(String id);

  /// Finds a user by its normalized email address.
  FutureOr<AuthUser?> findByEmail(String email);

  /// Persists [user], whose ID must be non-empty and stable.
  FutureOr<AuthUser> create(AuthUser user);

  /// Atomically finds a user by normalized email or creates one.
  ///
  /// Implementations must enforce email uniqueness at the persistence
  /// boundary. This operation is used for asserted provider email addresses
  /// and email sign-in callbacks, where a read followed by [create] would
  /// permit concurrent requests to create duplicate users.
  FutureOr<AuthUserCreateResult> createOrFindByEmail(AuthUser user);

  /// Updates a user and returns the persisted value, or `null` when absent.
  FutureOr<AuthUser?> update(AuthUser user);

  /// Atomically replaces a user's email while enforcing email uniqueness.
  FutureOr<AuthUser?> updateEmailForUser(String userId, String email);

  /// Deletes a user record by ID and reports whether it existed.
  FutureOr<bool> delete(String userId);
}

/// Persistence contract for credential authentication.
abstract interface class AuthCredentialStore {
  /// Finds a password credential by its normalized login identifier.
  FutureOr<AuthPasswordCredential?> findByIdentifier(String identifier);

  /// Atomically persists a user and its password credential.
  ///
  /// The credential must contain an encoded password hash, never plaintext.
  FutureOr<AuthUser?> register(
    AuthUser user,
    AuthPasswordCredential credential,
  );

  /// Updates an existing password credential, for example after rehashing.
  FutureOr<AuthPasswordCredential?> update(AuthPasswordCredential credential);

  /// Replaces the password hash on every password credential for [userId].
  ///
  /// Implementations must update the records atomically so a password reset
  /// cannot leave one of the user's password credentials on the old hash.
  FutureOr<int> updatePasswordForUser({
    required String userId,
    required String passwordHash,
    required DateTime updatedAt,
  });

  /// Removes a password credential by persistence identifier.
  FutureOr<void> delete(String credentialId);

  /// Removes every password credential owned by [userId].
  FutureOr<void> deleteForUser(String userId);
}

/// Optional credential-store capability for resolving a user's password
/// credential without assuming that their login identifier is an email.
abstract interface class AuthCredentialUserLookupStore {
  /// Finds the password credential owned by [userId].
  FutureOr<AuthPasswordCredential?> findForUser(String userId);
}

/// Resolves the password credential owned by [userId].
///
/// Username-based accounts require an explicit user lookup capability because
/// their credential identifier cannot be derived from the public user record.
/// Email lookup remains as a compatibility fallback for older adapters.
Future<AuthPasswordCredential?> findAuthCredentialForUser(
  AuthStore store,
  String userId,
) async {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) return null;

  final credentialStore = store.credentials;
  if (credentialStore is AuthCredentialUserLookupStore) {
    final lookup = credentialStore as AuthCredentialUserLookupStore;
    final credential = await Future.sync(
      () => lookup.findForUser(normalizedUserId),
    );
    if (credential != null) return credential;
  }
  if (store is AuthAdminStoreCapabilities) {
    final capabilities = store as AuthAdminStoreCapabilities;
    final credential = await Future.sync(
      () => capabilities.findCredentialForUser(normalizedUserId),
    );
    if (credential != null) return credential;
  }

  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  final email = user?.email;
  if (email == null || email.isEmpty) return null;
  return Future.sync(() => credentialStore.findByIdentifier(email));
}

/// Persistence contract for external provider accounts.
abstract interface class AuthAccountStore {
  /// Finds an external account by provider and provider-account identifier.
  FutureOr<AuthAccount?> find(String providerId, String providerAccountId);

  /// Lists external identities linked to [userId].
  FutureOr<List<AuthAccount>> listForUser(String userId);

  /// Atomically creates an identity link or returns the canonical existing link.
  ///
  /// Implementations must enforce uniqueness for the
  /// `(providerId, providerAccountId)` pair and must never overwrite an
  /// existing link belonging to another user.
  /// Links [account], which must contain non-empty provider and user IDs.
  FutureOr<AuthAccount> link(AuthAccount account);

  /// Removes exactly one external identity when it belongs to [userId].
  ///
  /// Account-safety decisions belong to [AuthAuthenticationMethodService].
  /// Callers must invoke this primitive only from the root store's shared
  /// authentication-method mutation transaction.
  FutureOr<bool> unlinkForUser(
    String userId,
    String providerId,
    String providerAccountId,
  );

  /// Removes every external identity owned by [userId].
  FutureOr<void> deleteForUser(String userId);
}

/// Persistence contract for one-time email-change confirmations.
abstract interface class AuthEmailChangeTokenStore {
  /// Persists a pending email-change token.
  FutureOr<void> save(AuthEmailChangeToken token);

  /// Atomically consumes an active token and returns its user/email binding.
  FutureOr<AuthEmailChangeToken?> consume(String token);

  /// Deletes all pending email-change tokens for [userId].
  FutureOr<void> deleteForUser(String userId);
}

/// Optional compare-and-delete capability for failed email-change delivery.
abstract interface class AuthEmailChangeTokenConditionalDeleteStore {
  /// Deletes the token only when it is still the active issuance for [userId].
  FutureOr<bool> deleteTokenForUser(String userId, String token);
}

/// Persistence contract for server-side sessions.
abstract interface class AuthSessionStore {
  /// Finds a session by the digest of its client-held token.
  FutureOr<AuthSessionRecord?> find(String tokenHash);

  /// Persists a newly issued session record with valid identity and lifetime
  /// fields.
  FutureOr<AuthSessionRecord> create(AuthSessionRecord session);

  /// Atomically advances last-used time for an active session.
  FutureOr<AuthSessionRecord?> touch(String tokenHash, DateTime lastUsedAt);

  /// Lists persisted sessions belonging to [userId].
  ///
  /// The adapter may include expired or revoked records; callers decide which
  /// lifecycle states are appropriate for a public session-management view.
  FutureOr<List<AuthSessionRecord>> listForUser(String userId);

  /// Atomically marks a session as revoked.
  FutureOr<AuthSessionRecord?> revoke(String tokenHash, {DateTime? revokedAt});

  /// Atomically revokes a session by its public persistence ID when it belongs
  /// to [userId].
  FutureOr<AuthSessionRecord?> revokeById(
    String userId,
    String sessionId, {
    DateTime? revokedAt,
  });

  /// Atomically revokes every session belonging to [userId].
  FutureOr<int> revokeAllForUser(String userId, {DateTime? revokedAt});

  /// Atomically revokes every session except [currentSessionId].
  FutureOr<int> revokeAllForUserExcept(
    String userId,
    String currentSessionId, {
    DateTime? revokedAt,
  });

  /// Atomically revokes [previousTokenHash] and creates [replacement].
  FutureOr<AuthSessionRecord?> rotate({
    required String previousTokenHash,
    required AuthSessionRecord replacement,
  });
}

/// Authoritative persistence boundary for authentication plugins.
///
/// Implementations expose each auth concern through its own typed store. An
/// application must provide one store to its auth options; there is no implicit
/// adapter, fallback store, or untyped callback surface.
abstract interface class AuthStore {
  /// User persistence operations.
  AuthUserStore get users;

  /// Password credential persistence operations.
  AuthCredentialStore get credentials;

  /// External provider-account persistence operations.
  AuthAccountStore get accounts;

  /// Server-side session persistence operations.
  AuthSessionStore get sessions;

  /// OAuth authorization-challenge persistence operations.
  AuthOAuthChallengeStore get oauthChallenges;

  /// Password-reset token persistence operations.
  AuthPasswordResetTokenStore get passwordResetTokens;

  /// JWT-version persistence operations.
  AuthJwtVersionStore get jwtVersions;

  /// Email-verification token persistence operations.
  AuthVerificationTokenStore get verificationTokens;

  /// Email-change token persistence operations.
  AuthEmailChangeTokenStore get emailChangeTokens;

  /// Device-authorization persistence operations.
  AuthDeviceAuthorizationStore get deviceAuthorizations;

  /// Email one-time-password persistence operations.
  AuthEmailOtpStore get emailOtps;
}

/// Optional data-plane operations required by the Admin plugin.
///
/// Production adapters implement these operations transactionally. Keeping
/// them separate from [AuthStore] preserves source compatibility for stores
/// that do not opt into administrative APIs.
abstract interface class AuthAdminStoreCapabilities {
  /// Lists users for an administrative view.
  FutureOr<List<AuthUser>> listUsersForAdministration();

  /// Updates a user through an administrative operation.
  FutureOr<AuthUser?> updateUserForAdministration(AuthUser user);

  /// Finds a password credential owned by [userId].
  FutureOr<AuthPasswordCredential?> findCredentialForUser(String userId);

  /// Creates or updates a password credential through administration.
  FutureOr<AuthPasswordCredential> upsertCredentialForAdministration(
    AuthPasswordCredential credential,
  );

  /// Deletes all core user-owned records as one transaction.
  FutureOr<bool> deleteUserForAdministration(String userId);

  /// Replaces a user with a minimal unavailable tombstone and removes the
  /// user's core credentials, identities, sessions, and reset tokens.
  ///
  /// Implementations must retain the stable user ID and deletion timestamp so
  /// future authentication attempts cannot recreate or reuse the account
  /// accidentally. Plugin-owned namespaces are handled by their contributors
  /// before this operation.
  FutureOr<bool> tombstoneUserForAdministration(
    String userId, {
    DateTime? deletedAt,
  });

  /// Permanently removes a previously tombstoned user during retention purge.
  FutureOr<bool> purgeTombstonedUserForAdministration(String userId);
}

typedef _InMemoryAuthCoreDeletionState = ({
  Map<String, AuthUser> usersById,
  Map<String, AuthUser> usersByEmail,
  Set<String> deletedUserIdHashes,
  Map<String, AuthPasswordCredential> credentialsById,
  Map<String, String> credentialIdsByIdentifier,
  Map<(String, String), AuthAccount> accounts,
  Map<String, AuthSessionRecord> sessions,
  Object passwordResetTokens,
  Object verificationTokens,
  Object emailChangeTokens,
  Object jwtVersions,
  Object accountStates,
  Object webAuthnChallenges,
  Object webAuthnAuthenticators,
  Object deviceAuthorizations,
  Object emailOtps,
  Map<String, _AuthAnonymousMutationReceipt> anonymousReceipts,
  Map<String, AuthMagicLinkRecord> magicLinks,
  Map<String, AuthPhoneNumberVerification> phoneVerifications,
  Map<String, AuthPhoneNumberIdentity> phoneIdentitiesByPhone,
  Map<String, String> phoneByUser,
  Map<String, _AuthPhoneNumberIssueReceipt> phoneIssueReceipts,
});

final class _AuthAnonymousMutationReceipt {
  const _AuthAnonymousMutationReceipt({
    required this.fingerprint,
    this.user,
    this.subjectUserId,
  });

  final String fingerprint;
  final AuthUser? user;
  final String? subjectUserId;
}

String _anonymousCreateFingerprint(AuthAnonymousCreateAccountCommand command) =>
    'create:${hashOpaqueToken(jsonEncode(command.user.toJson()))}';

typedef _InMemoryEmailMutationState = ({
  Map<String, AuthUser> usersById,
  Map<String, AuthUser> usersByEmail,
  Map<String, AuthMagicLinkRecord> magicLinks,
  Object emailOtps,
});

final class _EmailUserResolution {
  const _EmailUserResolution(this.user, {required this.created});

  final AuthUser user;
  final bool created;
}

AuthEmailOtpUserTransitionResult? _emailOtpRejectedTransition(
  AuthEmailOtpVerificationStatus status,
) => switch (status) {
  AuthEmailOtpVerificationStatus.verified => null,
  AuthEmailOtpVerificationStatus.invalid =>
    const AuthEmailOtpUserTransitionResult(
      AuthEmailOtpUserTransitionStatus.invalid,
    ),
  AuthEmailOtpVerificationStatus.expired =>
    const AuthEmailOtpUserTransitionResult(
      AuthEmailOtpUserTransitionStatus.expired,
    ),
  AuthEmailOtpVerificationStatus.tooManyAttempts =>
    const AuthEmailOtpUserTransitionResult(
      AuthEmailOtpUserTransitionStatus.tooManyAttempts,
    ),
};

final class _AuthPhoneNumberIssueReceipt {
  const _AuthPhoneNumberIssueReceipt({
    required this.fingerprint,
    required this.phoneNumber,
    required this.createdAt,
  });

  final String fingerprint;
  final String phoneNumber;
  final DateTime createdAt;
}

String _phoneIssueFingerprint(AuthPhoneNumberIssueCodeCommand command) =>
    hashOpaqueToken(jsonEncode(command.verification.toStorageJson()));

/// In-memory store for tests, examples, and local development.
///
/// This implementation deliberately keeps password hashes outside [AuthUser]
/// attributes. It is not intended for production persistence; production
/// applications should provide an implementation backed by their database and
/// password-hashing policy.
class InMemoryAuthStore
    implements
        AuthStore,
        AuthUsernameStore,
        AuthAnonymousAccountMutationStore,
        AuthMagicLinkBackend,
        AuthEmailOtpBackend,
        AuthPhoneNumberBackend,
        AuthPhoneNumberMutationStore,
        AuthAdminStoreCapabilities,
        AuthWebAuthnStoreCapabilities,
        AuthAccountStateStore,
        AuthAuthenticationMethodMutationStore,
        AuthOAuthAccountMutationStore,
        AuthUserDeletionCoordinatorHost,
        AuthInMemoryUserDeletionBackend {
  /// Creates an in-memory store for tests and local development.
  InMemoryAuthStore({
    this.anonymousFaultInjector,
    this.emailBackendFaultInjector,
    this.phoneNumberFaultInjector,
    this.maxPhoneNumberVerifications = 2048,
    AuthUsernameFaultInjector? usernameFaultInjector,
    AuthUserDeletionFaultInjector? userDeletionFaultInjector,
  }) : users = _InMemoryUserStore(),
       credentials = _InMemoryCredentialStore(),
       accounts = _InMemoryAccountStore(),
       sessions = _InMemorySessionStore(),
       oauthChallenges = InMemoryAuthOAuthChallengeStore(),
       passwordResetTokens = InMemoryAuthPasswordResetTokenStore(),
       jwtVersions = InMemoryAuthJwtVersionStore(),
       verificationTokens = InMemoryAuthVerificationTokenStore(),
       emailChangeTokens = InMemoryAuthEmailChangeTokenStore(),
       webAuthnChallenges = InMemoryAuthWebAuthnChallengeStore(),
       webAuthnAuthenticators = InMemoryAuthWebAuthnAuthenticatorStore(),
       deviceAuthorizations = InMemoryAuthDeviceAuthorizationStore(),
       emailOtps = InMemoryAuthEmailOtpStore(),
       _deletionDomain = AuthInMemoryUserDeletionDomain(),
       _accountStates = InMemoryAuthAccountStateStore(),
       _usernameFaultInjector = usernameFaultInjector {
    if (maxPhoneNumberVerifications <= 0) {
      throw ArgumentError.value(
        maxPhoneNumberVerifications,
        'maxPhoneNumberVerifications',
        'must be greater than zero',
      );
    }
    (credentials as _InMemoryCredentialStore).users = users;
    _deletionCoordinator = AuthInMemoryUserDeletionCoordinator(
      domain: _deletionDomain,
      backend: this,
      faultInjector: userDeletionFaultInjector,
      mutationSerializer: _serializePhoneNumberMutation,
    );
  }

  @override
  final AuthUserStore users;

  @override
  final AuthCredentialStore credentials;

  @override
  final AuthAccountStore accounts;

  @override
  final AuthSessionStore sessions;

  @override
  final AuthOAuthChallengeStore oauthChallenges;

  @override
  final AuthPasswordResetTokenStore passwordResetTokens;

  @override
  final AuthJwtVersionStore jwtVersions;

  @override
  final AuthVerificationTokenStore verificationTokens;

  @override
  final AuthEmailChangeTokenStore emailChangeTokens;

  @override
  final AuthWebAuthnChallengeStore webAuthnChallenges;

  @override
  final AuthWebAuthnAuthenticatorStore webAuthnAuthenticators;

  @override
  final AuthDeviceAuthorizationStore deviceAuthorizations;

  @override
  final AuthEmailOtpStore emailOtps;

  /// Optional deterministic failures for email backend rollback tests.
  final AuthEmailBackendFaultInjector? emailBackendFaultInjector;

  final InMemoryAuthAccountStateStore _accountStates;
  final AuthUsernameFaultInjector? _usernameFaultInjector;

  /// Optional deterministic failures for anonymous-account rollback tests.
  final AuthAnonymousInMemoryFaultInjector? anonymousFaultInjector;

  /// Optional deterministic failures for phone-number rollback tests.
  final AuthPhoneNumberInMemoryFaultInjector? phoneNumberFaultInjector;

  /// Maximum number of phone verifications retained in memory.
  final int maxPhoneNumberVerifications;
  final AuthInMemoryUserDeletionDomain _deletionDomain;
  late final AuthInMemoryUserDeletionCoordinator _deletionCoordinator;
  final Map<String, _AuthAnonymousMutationReceipt> _anonymousReceipts =
      <String, _AuthAnonymousMutationReceipt>{};
  Future<void> _anonymousMutationTail = Future<void>.value();
  Future<void> _phoneNumberMutationTail = Future<void>.value();
  final Map<String, AuthPhoneNumberVerification> _phoneVerifications =
      <String, AuthPhoneNumberVerification>{};
  final Map<String, AuthPhoneNumberIdentity> _phoneIdentitiesByPhone =
      <String, AuthPhoneNumberIdentity>{};
  final Map<String, String> _phoneByUser = <String, String>{};
  final Map<String, _AuthPhoneNumberIssueReceipt> _phoneIssueReceipts =
      <String, _AuthPhoneNumberIssueReceipt>{};
  final Map<String, Future<void>> _authenticationMethodMutationTails =
      <String, Future<void>>{};
  final Map<String, Future<void>> _usernameMutationTails =
      <String, Future<void>>{};

  @override
  Future<AuthUsernameMutationResult> registerUsername(
    AuthUsernameRegistrationCommand command,
  ) async {
    final created = await _credentials._register(
      command.user,
      command.credential,
      username: true,
      afterUserWrite: () => _injectUsernameFault(
        AuthUsernameFaultPoint.registrationAfterUserWrite,
      ),
    );
    return created == null
        ? const AuthUsernameMutationResult(
            status: AuthUsernameMutationStatus.conflict,
          )
        : AuthUsernameMutationResult(
            status: AuthUsernameMutationStatus.created,
            user: created,
            credential: command.credential,
          );
  }

  @override
  Future<AuthPasswordCredential?> findUsernameForUser(String userId) =>
      _credentials.findUsernameForUser(userId);

  @override
  Future<AuthPasswordCredential?> findByUsername(String username) =>
      _credentials.findByIdentifier(username);

  @override
  Future<AuthUsernameMutationResult> changeUsername(
    AuthUsernameChangeCommand command,
  ) => _serializeUsernameMutation(command.userId, () async {
    final user = _users._usersById[command.userId];
    final credential = _credentials._credentialsById[command.credentialId];
    if (user == null ||
        credential == null ||
        credential.userId != command.userId ||
        credential.identifier.contains('@')) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.notFound,
      );
    }
    if (authUserIsDisabled(user)) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.userUnavailable,
      );
    }
    final state = await _accountStates.find(user.id);
    if ((state?.disabled ?? false) || (state?.isLocked() ?? false)) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.userUnavailable,
      );
    }
    if (credential.identifier == command.username &&
        user.attributes['username'] == command.username) {
      return AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.unchanged,
        user: user,
        credential: credential,
      );
    }
    if (credential.identifier != command.expectedUsername ||
        user.attributes['username'] != command.expectedUsername) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.conflict,
      );
    }
    final conflictingId =
        _credentials._credentialIdsByIdentifier[command.username];
    if (conflictingId != null && conflictingId != credential.id) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.conflict,
      );
    }
    if (!_credentials._inFlightIdentifiers.add(command.username)) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.conflict,
      );
    }
    final updatedCredential = AuthPasswordCredential(
      id: credential.id,
      userId: credential.userId,
      identifier: command.username,
      passwordHash: credential.passwordHash,
      createdAt: credential.createdAt,
      updatedAt: command.updatedAt.toUtc(),
      enabled: credential.enabled,
    );
    final updatedUser = _usernameProjection(
      user,
      from: command.expectedUsername,
      to: command.username,
    );
    try {
      _credentials._credentialIdsByIdentifier.remove(credential.identifier);
      _credentials._credentialIdsByIdentifier[command.username] = credential.id;
      _credentials._credentialsById[credential.id] = updatedCredential;
      await _injectUsernameFault(
        AuthUsernameFaultPoint.changeAfterCredentialWrite,
      );
      _users._usersById[user.id] = updatedUser;
      if (user.email != null) _users._usersByEmail[user.email!] = updatedUser;
      await _injectUsernameFault(AuthUsernameFaultPoint.changeAfterUserWrite);
      return AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.changed,
        user: updatedUser,
        credential: updatedCredential,
      );
    } catch (_) {
      _credentials._credentialIdsByIdentifier.remove(command.username);
      _credentials._credentialIdsByIdentifier[credential.identifier] =
          credential.id;
      _credentials._credentialsById[credential.id] = credential;
      _users._usersById[user.id] = user;
      if (user.email != null) _users._usersByEmail[user.email!] = user;
      rethrow;
    } finally {
      _credentials._inFlightIdentifiers.remove(command.username);
    }
  });

  @override
  Future<AuthAuthenticationMethodMutationResult> removeUsernameIfSafe(
    AuthUsernameRemovalCommand command,
  ) => mutateAuthenticationMethodIfSafe(
    userId: command.userId,
    target: AuthAuthenticationMethod.username(command.credentialId),
    loadInventory: command.loadInventory,
    mutate: () async {
      final user = _users._usersById[command.userId];
      final credential = _credentials._credentialsById[command.credentialId];
      if (user == null ||
          credential == null ||
          credential.userId != command.userId ||
          credential.identifier.contains('@')) {
        return false;
      }
      final updatedUser = _usernameProjection(
        user,
        from: credential.identifier,
        to: null,
      );
      try {
        _users._usersById[user.id] = updatedUser;
        if (user.email != null) _users._usersByEmail[user.email!] = updatedUser;
        await _injectUsernameFault(
          AuthUsernameFaultPoint.removalAfterUserWrite,
        );
        _credentials._credentialsById.remove(credential.id);
        _credentials._credentialIdsByIdentifier.remove(credential.identifier);
        await _injectUsernameFault(
          AuthUsernameFaultPoint.removalAfterCredentialWrite,
        );
        return true;
      } catch (_) {
        _users._usersById[user.id] = user;
        if (user.email != null) _users._usersByEmail[user.email!] = user;
        _credentials._credentialsById[credential.id] = credential;
        _credentials._credentialIdsByIdentifier[credential.identifier] =
            credential.id;
        rethrow;
      }
    },
  );

  Future<T> _serializeUsernameMutation<T>(
    String userId,
    Future<T> Function() mutation,
  ) {
    final completer = Completer<T>();
    final previous = _usernameMutationTails[userId] ?? Future<void>.value();
    late final Future<void> current;
    current = previous.then((_) async {
      try {
        completer.complete(await mutation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _usernameMutationTails[userId] = current;
    current.whenComplete(() {
      if (identical(_usernameMutationTails[userId], current)) {
        _usernameMutationTails.remove(userId);
      }
    });
    return completer.future;
  }

  final Map<String, Future<void>> _emailMutationTails =
      <String, Future<void>>{};
  final Map<String, AuthMagicLinkRecord> _magicLinks =
      <String, AuthMagicLinkRecord>{};

  @override
  AuthEmailOtpStore get emailOtpStore => emailOtps;

  @override
  Future<void> issueMagicLink(AuthMagicLinkIssueCommand command) =>
      _atomicEmailMutation(command.record.email, () async {
        _magicLinks[_magicLinkKey(
              command.record.providerId,
              command.record.email,
            )] =
            command.record;
        _emailFault(AuthEmailBackendFaultPoint.afterMagicLinkWrite);
      });

  @override
  Future<AuthMagicLinkConsumeResult> consumeMagicLink(
    AuthMagicLinkConsumeCommand command,
  ) => _atomicEmailMutation(command.email, () async {
    final key = _magicLinkKey(command.providerId, command.email);
    final record = _magicLinks[key];
    if (record == null) {
      return const AuthMagicLinkConsumeResult(
        AuthMagicLinkConsumeStatus.invalid,
      );
    }
    if (record.isExpired(command.now)) {
      _magicLinks.remove(key);
      return const AuthMagicLinkConsumeResult(
        AuthMagicLinkConsumeStatus.expired,
      );
    }
    if (!constantTimeStringEquals(record.tokenHash, command.tokenHash)) {
      return const AuthMagicLinkConsumeResult(
        AuthMagicLinkConsumeStatus.invalid,
      );
    }

    _magicLinks.remove(key);
    _emailFault(AuthEmailBackendFaultPoint.afterMagicLinkConsume);
    final resolution = await _resolveEmailUser(
      command.email,
      command.candidate,
      disableSignUp: false,
    );
    if (resolution == null || authUserIsDisabled(resolution.user)) {
      return const AuthMagicLinkConsumeResult(
        AuthMagicLinkConsumeStatus.userUnavailable,
      );
    }
    final verified = await _persistVerifiedEmail(resolution.user);
    _emailFault(AuthEmailBackendFaultPoint.afterUserWrite);
    return AuthMagicLinkConsumeResult(
      AuthMagicLinkConsumeStatus.consumed,
      user: verified,
      created: resolution.created,
    );
  });

  @override
  Future<void> issueEmailOtp(AuthEmailOtpIssueCommand command) =>
      _atomicEmailMutation(command.otp.email, () async {
        await emailOtps.save(command.otp);
        _emailFault(AuthEmailBackendFaultPoint.afterEmailOtpWrite);
      });

  @override
  Future<AuthEmailOtpVerificationResult> verifyEmailOtp(
    AuthEmailOtpVerifyCommand command,
  ) =>
      _atomicEmailMutation(command.email, () => _verifyEmailOtpDigest(command));

  @override
  Future<AuthEmailOtpUserTransitionResult> signInWithEmailOtp(
    AuthEmailOtpSignInCommand command,
  ) => _atomicEmailMutation(command.email, () async {
    final verification = await _verifyEmailOtpDigest(
      AuthEmailOtpVerifyCommand(
        email: command.email,
        type: AuthEmailOtpType.signIn,
        codeHash: command.codeHash,
        now: command.now,
      ),
    );
    final rejected = _emailOtpRejectedTransition(verification.status);
    if (rejected != null) return rejected;
    _emailFault(AuthEmailBackendFaultPoint.afterEmailOtpConsume);

    final resolution = await _resolveEmailUser(
      command.email,
      command.candidate,
      disableSignUp: command.disableSignUp,
    );
    if (resolution == null) {
      return const AuthEmailOtpUserTransitionResult(
        AuthEmailOtpUserTransitionStatus.userNotFound,
      );
    }
    if (authUserIsDisabled(resolution.user)) {
      return const AuthEmailOtpUserTransitionResult(
        AuthEmailOtpUserTransitionStatus.userUnavailable,
      );
    }
    final verified = await _persistVerifiedEmail(resolution.user);
    _emailFault(AuthEmailBackendFaultPoint.afterUserWrite);
    return AuthEmailOtpUserTransitionResult(
      AuthEmailOtpUserTransitionStatus.applied,
      user: verified,
      created: resolution.created,
    );
  });

  @override
  Future<AuthEmailOtpUserTransitionResult> verifyUserEmailWithOtp(
    AuthEmailOtpVerifyUserCommand command,
  ) => _atomicEmailMutation(command.email, () async {
    final user = await _users.findById(command.userId);
    if (user == null ||
        user.email == null ||
        normalizeAuthOneTimeEmail(user.email!) != command.email) {
      return const AuthEmailOtpUserTransitionResult(
        AuthEmailOtpUserTransitionStatus.userNotFound,
      );
    }
    if (authUserIsDisabled(user)) {
      return const AuthEmailOtpUserTransitionResult(
        AuthEmailOtpUserTransitionStatus.userUnavailable,
      );
    }
    final verification = await _verifyEmailOtpDigest(
      AuthEmailOtpVerifyCommand(
        email: command.email,
        type: AuthEmailOtpType.emailVerification,
        codeHash: command.codeHash,
        now: command.now,
      ),
    );
    final rejected = _emailOtpRejectedTransition(verification.status);
    if (rejected != null) return rejected;
    _emailFault(AuthEmailBackendFaultPoint.afterEmailOtpConsume);
    final verified = await _persistVerifiedEmail(user);
    _emailFault(AuthEmailBackendFaultPoint.afterUserWrite);
    return AuthEmailOtpUserTransitionResult(
      AuthEmailOtpUserTransitionStatus.applied,
      user: verified,
    );
  });

  Future<AuthEmailOtpVerificationResult> _verifyEmailOtpDigest(
    AuthEmailOtpVerifyCommand command,
  ) => Future.sync(
    () => emailOtps.verifyDigest(
      command.email,
      command.type,
      command.codeHash,
      now: command.now,
    ),
  );

  Future<_EmailUserResolution?> _resolveEmailUser(
    String email,
    AuthUser candidate, {
    required bool disableSignUp,
  }) async {
    final existing = await _users.findByEmail(email);
    if (existing != null) {
      return _EmailUserResolution(existing, created: false);
    }
    if (disableSignUp) return null;
    final created = await _users.createOrFindByEmail(candidate);
    final resolvedEmail = created.user.email;
    if (resolvedEmail == null ||
        normalizeAuthOneTimeEmail(resolvedEmail) != email) {
      return null;
    }
    return _EmailUserResolution(created.user, created: created.created);
  }

  static String _magicLinkKey(String providerId, String email) =>
      '$providerId\u0000${normalizeAuthOneTimeEmail(email)}';

  Future<AuthUser> _persistVerifiedEmail(AuthUser user) async {
    if (user.attributes['emailVerified'] == true) return user;
    final verified = AuthUser(
      id: user.id,
      email: user.email,
      name: user.name,
      image: user.image,
      roles: user.roles,
      attributes: <String, dynamic>{...user.attributes, 'emailVerified': true},
    );
    final persisted = await _users.update(verified);
    if (persisted == null) {
      throw StateError('Email backend lost its user during verification.');
    }
    return persisted;
  }

  Future<T> _atomicEmailMutation<T>(
    String email,
    FutureOr<T> Function() operation,
  ) {
    final key = normalizeAuthOneTimeEmail(email);
    final completer = Completer<T>();
    final previous = _emailMutationTails[key] ?? Future<void>.value();
    late final Future<void> current;
    current = previous.then((_) async {
      final checkpoint = _captureEmailMutationState();
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        _restoreEmailMutationState(checkpoint);
        completer.completeError(error, stackTrace);
      }
    });
    _emailMutationTails[key] = current;
    current.whenComplete(() {
      if (identical(_emailMutationTails[key], current)) {
        _emailMutationTails.remove(key);
      }
    });
    return completer.future;
  }

  Future<void> _injectUsernameFault(AuthUsernameFaultPoint point) async {
    final injector = _usernameFaultInjector;
    if (injector != null) await injector(point);
  }

  _InMemoryEmailMutationState _captureEmailMutationState() => (
    usersById: Map<String, AuthUser>.of(_users._usersById),
    usersByEmail: Map<String, AuthUser>.of(_users._usersByEmail),
    magicLinks: Map<String, AuthMagicLinkRecord>.of(_magicLinks),
    emailOtps: (emailOtps as AuthInMemoryDeletionState).captureDeletionState(),
  );

  void _restoreEmailMutationState(_InMemoryEmailMutationState state) {
    _users._usersById
      ..clear()
      ..addAll(state.usersById);
    _users._usersByEmail
      ..clear()
      ..addAll(state.usersByEmail);
    _magicLinks
      ..clear()
      ..addAll(state.magicLinks);
    (emailOtps as AuthInMemoryDeletionState).restoreDeletionState(
      state.emailOtps,
    );
  }

  void _emailFault(AuthEmailBackendFaultPoint point) =>
      emailBackendFaultInjector?.throwIfScheduled(point);

  @override
  Future<AuthAuthenticationMethodMutationResult>
  mutateAuthenticationMethodIfSafe({
    required String userId,
    required AuthAuthenticationMethod target,
    required AuthAuthenticationMethodInventoryLoader loadInventory,
    required AuthAuthenticationMethodMutation mutate,
  }) {
    final completer = Completer<AuthAuthenticationMethodMutationResult>();
    final previous =
        _authenticationMethodMutationTails[userId] ?? Future<void>.value();
    late final Future<void> current;
    current = previous.then((_) async {
      try {
        final snapshot = await loadInventory();
        if (!snapshot.isComplete) {
          completer.complete(
            AuthAuthenticationMethodMutationResult.atomicityUnavailable,
          );
          return;
        }
        if (!snapshot.methods.contains(target)) {
          completer.complete(AuthAuthenticationMethodMutationResult.notFound);
          return;
        }
        if (!snapshot.methods.any(
          (method) => method.canAuthenticate && method != target,
        )) {
          completer.complete(
            AuthAuthenticationMethodMutationResult.lastAuthenticationMethod,
          );
          return;
        }
        completer.complete(
          await mutate()
              ? AuthAuthenticationMethodMutationResult.mutated
              : AuthAuthenticationMethodMutationResult.notFound,
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _authenticationMethodMutationTails[userId] = current;
    current.whenComplete(() {
      if (identical(_authenticationMethodMutationTails[userId], current)) {
        _authenticationMethodMutationTails.remove(userId);
      }
    });
    return completer.future;
  }

  @override
  Future<AuthAuthenticationMethodMutationResult> unlinkOAuthAccountIfSafe({
    required String userId,
    required String providerId,
    required String providerAccountId,
    required AuthAuthenticationMethodInventoryLoader loadInventory,
  }) => mutateAuthenticationMethodIfSafe(
    userId: userId,
    target: AuthAuthenticationMethod.oauthProvider(
      providerId: providerId,
      providerAccountId: providerAccountId,
    ),
    loadInventory: loadInventory,
    mutate: () => accounts.unlinkForUser(userId, providerId, providerAccountId),
  );

  @override
  Future<AuthAuthenticationMethodMutationResult> removePhoneNumberIfSafe(
    AuthPhoneNumberRemovalCommand command,
  ) => _serializePhoneNumberMutation(() async {
    final snapshot = await command.loadInventory();
    if (!snapshot.isComplete) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final target = AuthAuthenticationMethod.phone(command.phoneNumber);
    if (!snapshot.methods.contains(target)) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    if (!snapshot.methods.any(
      (method) => method.canAuthenticate && method != target,
    )) {
      return AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
    }
    final identity = _phoneIdentitiesByPhone[command.phoneNumber];
    if (identity == null || identity.userId != command.userId) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    final user = _users._usersById[command.userId];
    if (user == null) return AuthAuthenticationMethodMutationResult.notFound;
    _phoneIdentitiesByPhone.remove(command.phoneNumber);
    if (_phoneByUser[command.userId] == command.phoneNumber) {
      _phoneByUser.remove(command.userId);
    }
    _phoneVerifications.remove(command.phoneNumber);
    _phoneIssueReceipts.removeWhere(
      (_, receipt) => receipt.phoneNumber == command.phoneNumber,
    );
    final attributes = Map<String, dynamic>.from(user.attributes)
      ..remove('phoneNumber')
      ..remove('phoneNumberVerified');
    final updated = AuthUser(
      id: user.id,
      email: user.email,
      name: user.name,
      image: user.image,
      roles: user.roles,
      isAnonymous: user.isAnonymous,
      attributes: attributes,
    );
    final persisted = await _users.update(updated);
    if (persisted == null) {
      throw StateError('Phone identity owner disappeared during removal.');
    }
    return AuthAuthenticationMethodMutationResult.mutated;
  });

  @override
  AuthUserDeletionCoordinator get userDeletionCoordinator =>
      _deletionCoordinator;

  @override
  Future<AuthPhoneNumberIssueResult> issuePhoneNumberCode(
    AuthPhoneNumberIssueCodeCommand command,
  ) => _serializePhoneNumberMutation(() async {
    final verification = command.verification;
    validateAuthPhoneNumberVerification(verification);
    final fingerprint = _phoneIssueFingerprint(command);
    final receipt = _phoneIssueReceipts[verification.id];
    if (receipt != null) {
      if (receipt.fingerprint != fingerprint ||
          receipt.phoneNumber != verification.phoneNumber) {
        return const AuthPhoneNumberIssueResult(
          AuthPhoneNumberIssueStatus.replayMismatch,
        );
      }
      final active = _phoneVerifications[verification.phoneNumber];
      return active != null &&
              active.id == verification.id &&
              !active.isConsumed
          ? AuthPhoneNumberIssueResult(
              AuthPhoneNumberIssueStatus.replayed,
              verification: active,
            )
          : const AuthPhoneNumberIssueResult(
              AuthPhoneNumberIssueStatus.replayMismatch,
            );
    }

    final previous = _phoneVerifications[verification.phoneNumber];
    _phoneVerifications[verification.phoneNumber] = verification;
    _phoneIssueReceipts[verification.id] = _AuthPhoneNumberIssueReceipt(
      fingerprint: fingerprint,
      phoneNumber: verification.phoneNumber,
      createdAt: verification.createdAt.toUtc(),
    );
    try {
      await phoneNumberFaultInjector?.call(
        AuthPhoneNumberInMemoryFaultPoint.issueAfterChallengeWrite,
      );
      _prunePhoneNumberVerifications(verification.createdAt.toUtc());
      while (_phoneVerifications.length > maxPhoneNumberVerifications) {
        _phoneVerifications.remove(_phoneVerifications.keys.first);
      }
      while (_phoneIssueReceipts.length > maxPhoneNumberVerifications * 2) {
        final oldest = _phoneIssueReceipts.entries.reduce(
          (left, right) => left.value.createdAt.isBefore(right.value.createdAt)
              ? left
              : right,
        );
        _phoneIssueReceipts.remove(oldest.key);
      }
      return AuthPhoneNumberIssueResult(
        AuthPhoneNumberIssueStatus.issued,
        verification: verification,
      );
    } catch (error, stackTrace) {
      if (identical(
        _phoneVerifications[verification.phoneNumber],
        verification,
      )) {
        if (previous == null) {
          _phoneVerifications.remove(verification.phoneNumber);
        } else {
          _phoneVerifications[verification.phoneNumber] = previous;
        }
      }
      final currentReceipt = _phoneIssueReceipts[verification.id];
      if (currentReceipt?.fingerprint == fingerprint) {
        _phoneIssueReceipts.remove(verification.id);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  });

  @override
  Future<AuthPhoneNumberVerifyResult> verifyPhoneNumberCode(
    AuthPhoneNumberVerifyCodeCommand command,
  ) => _serializePhoneNumberMutation(() async {
    final existing = _phoneVerifications[command.phoneNumber];
    if (existing == null || existing.isConsumed) {
      return const AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.invalid,
      );
    }
    if (existing.isExpired(now: command.now)) {
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.expired,
        verification: existing,
      );
    }
    if (existing.isLocked) {
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.tooManyAttempts,
        verification: existing,
      );
    }

    final attempts = existing.attempts + 1;
    if (!constantTimeStringEquals(existing.codeDigest, command.codeDigest)) {
      final updated = existing.copyWith(
        attempts: attempts,
        lockedAt: attempts >= existing.maxAttempts ? command.now : null,
      );
      _phoneVerifications[command.phoneNumber] = updated;
      try {
        await phoneNumberFaultInjector?.call(
          AuthPhoneNumberInMemoryFaultPoint.verifyAfterAttemptWrite,
        );
      } catch (error, stackTrace) {
        if (identical(_phoneVerifications[command.phoneNumber], updated)) {
          _phoneVerifications[command.phoneNumber] = existing;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      return AuthPhoneNumberVerifyResult(
        updated.isLocked
            ? AuthPhoneNumberVerifyStatus.tooManyAttempts
            : AuthPhoneNumberVerifyStatus.invalid,
        verification: updated,
      );
    }

    final consumed = existing.copyWith(
      attempts: attempts,
      consumedAt: command.now,
    );
    _phoneVerifications[command.phoneNumber] = consumed;
    try {
      await phoneNumberFaultInjector?.call(
        AuthPhoneNumberInMemoryFaultPoint.verifyAfterChallengeConsumption,
      );
    } catch (error, stackTrace) {
      if (identical(_phoneVerifications[command.phoneNumber], consumed)) {
        _phoneVerifications[command.phoneNumber] = existing;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    final currentIdentity = _phoneIdentitiesByPhone[command.phoneNumber];
    var identity = currentIdentity;
    AuthUser? previousUser;
    AuthUser? committedUser;
    var createdUser = false;
    var wroteIdentity = false;
    try {
      if (identity != null) {
        previousUser = _users._usersById[identity.userId];
        if (previousUser == null) {
          return AuthPhoneNumberVerifyResult(
            AuthPhoneNumberVerifyStatus.userNotFound,
            verification: consumed,
            identity: identity,
          );
        }
        if (authUserIsDisabled(previousUser)) {
          return AuthPhoneNumberVerifyResult(
            AuthPhoneNumberVerifyStatus.userUnavailable,
            verification: consumed,
            identity: identity,
          );
        }
      } else {
        final candidate = command.candidateUser;
        if (candidate == null) {
          return AuthPhoneNumberVerifyResult(
            AuthPhoneNumberVerifyStatus.userNotFound,
            verification: consumed,
          );
        }
        if (_users.contains(candidate.id) ||
            _users.wasHardDeleted(candidate.id)) {
          return AuthPhoneNumberVerifyResult(
            AuthPhoneNumberVerifyStatus.conflict,
            verification: consumed,
          );
        }
        final email = candidate.email;
        if (email != null && _users._usersByEmail.containsKey(email)) {
          return AuthPhoneNumberVerifyResult(
            AuthPhoneNumberVerifyStatus.conflict,
            verification: consumed,
          );
        }
        committedUser = _phoneVerifiedUser(candidate, command.phoneNumber);
        await _users.create(committedUser);
        createdUser = true;
        await phoneNumberFaultInjector?.call(
          AuthPhoneNumberInMemoryFaultPoint.verifyAfterUserWrite,
        );
        identity = AuthPhoneNumberIdentity(
          phoneNumber: command.phoneNumber,
          userId: committedUser.id,
          createdAt: command.now,
          verifiedAt: command.now,
        );
        _phoneIdentitiesByPhone[command.phoneNumber] = identity;
        _phoneByUser[committedUser.id] = command.phoneNumber;
        wroteIdentity = true;
        await phoneNumberFaultInjector?.call(
          AuthPhoneNumberInMemoryFaultPoint.verifyAfterIdentityWrite,
        );
      }

      previousUser ??= _users._usersById[identity.userId];
      if (previousUser == null || authUserIsDisabled(previousUser)) {
        return AuthPhoneNumberVerifyResult(
          AuthPhoneNumberVerifyStatus.userUnavailable,
          verification: consumed,
          identity: identity,
        );
      }
      committedUser ??= _phoneVerifiedUser(previousUser, command.phoneNumber);
      if (!identical(committedUser, previousUser)) {
        _users._usersById[committedUser.id] = committedUser;
        if (previousUser.email != null) {
          _users._usersByEmail[previousUser.email!] = committedUser;
        }
      }
      await phoneNumberFaultInjector?.call(
        AuthPhoneNumberInMemoryFaultPoint.verifyAfterUserProjection,
      );
      if (!identical(_users._usersById[committedUser.id], committedUser) ||
          !identical(_phoneIdentitiesByPhone[command.phoneNumber], identity)) {
        throw StateError(
          'Phone identity was deleted before verification committed',
        );
      }
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.verified,
        verification: consumed,
        identity: identity,
        user: committedUser,
      );
    } catch (error, stackTrace) {
      if (identical(_phoneVerifications[command.phoneNumber], consumed)) {
        _phoneVerifications[command.phoneNumber] = existing;
      }
      if (wroteIdentity &&
          identical(_phoneIdentitiesByPhone[command.phoneNumber], identity)) {
        _phoneIdentitiesByPhone.remove(command.phoneNumber);
        if (_phoneByUser[identity!.userId] == command.phoneNumber) {
          _phoneByUser.remove(identity.userId);
        }
      }
      if (createdUser &&
          committedUser != null &&
          identical(_users._usersById[committedUser.id], committedUser)) {
        await _users.delete(committedUser.id);
      } else if (previousUser != null &&
          committedUser != null &&
          identical(_users._usersById[committedUser.id], committedUser) &&
          !_users.wasHardDeleted(previousUser.id)) {
        _users._usersById[previousUser.id] = previousUser;
        if (previousUser.email != null) {
          _users._usersByEmail[previousUser.email!] = previousUser;
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  });

  @override
  Future<AuthPhoneNumberIdentity?> findPhoneNumberIdentity(
    String phoneNumber,
  ) async => _phoneIdentitiesByPhone[phoneNumber];

  @override
  Future<AuthPhoneNumberIdentity?> findPhoneNumberIdentityForUser(
    String userId,
  ) async {
    final phoneNumber = _phoneByUser[userId.trim()];
    return phoneNumber == null ? null : _phoneIdentitiesByPhone[phoneNumber];
  }

  Future<T> _serializePhoneNumberMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _phoneNumberMutationTail = _phoneNumberMutationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _prunePhoneNumberVerifications(DateTime now) {
    _phoneVerifications.removeWhere((_, verification) {
      return verification.isExpired(now: now);
    });
  }

  @override
  Future<AuthAnonymousMutationResult> createAnonymousAccount(
    AuthAnonymousCreateAccountCommand command,
  ) => _serializeAnonymousMutation(() async {
    final fingerprint = _anonymousCreateFingerprint(command);
    final replay = _anonymousReplay(command.operationId, fingerprint);
    if (replay != null) return replay;
    var created = false;
    try {
      final user = await users.create(command.user);
      created = true;
      await anonymousFaultInjector?.call(
        AuthAnonymousInMemoryFaultPoint.afterCreateWrite,
      );
      _anonymousReceipts[command.operationId] = _AuthAnonymousMutationReceipt(
        fingerprint: fingerprint,
        user: user,
        subjectUserId: user.id,
      );
      if (!identical(await users.findById(user.id), user)) {
        throw StateError(
          'Anonymous account was deleted before creation committed',
        );
      }
      return AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.applied,
        user: user,
      );
    } catch (error, stackTrace) {
      final receipt = _anonymousReceipts[command.operationId];
      if (receipt?.fingerprint == fingerprint &&
          receipt?.subjectUserId == command.user.id) {
        _anonymousReceipts.remove(command.operationId);
      }
      if (created) {
        final current = await users.findById(command.user.id);
        if (identical(current, command.user)) {
          await users.delete(command.user.id);
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  });

  @override
  Future<AuthAnonymousMutationResult> deleteAnonymousAccount(
    AuthAnonymousDeleteAccountCommand command,
  ) => _serializeAnonymousMutation(() async {
    final fingerprint = hashOpaqueToken('delete:${command.userId}');
    final replay = _anonymousReplay(command.operationId, fingerprint);
    if (replay != null) return replay;
    final existing = await users.findById(command.userId);
    if (existing == null) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notFound,
      );
    }
    if (!existing.isAnonymous) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notAnonymous,
      );
    }
    if (!await _deletionCoordinator.deleteUser(command.userId)) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notFound,
      );
    }
    _replaceAnonymousUserReceipts(
      userId: command.userId,
      operationId: command.operationId,
      fingerprint: fingerprint,
    );
    return const AuthAnonymousMutationResult(
      AuthAnonymousMutationStatus.applied,
    );
  });

  @override
  Future<AuthAnonymousMutationResult> completeAnonymousAccountUpgrade(
    AuthAnonymousCompleteUpgradeCommand command,
  ) => _serializeAnonymousMutation(() async {
    final fingerprint = hashOpaqueToken(
      'upgrade:${command.anonymousUserId}:${command.targetUserId}',
    );
    final replay = _anonymousReplay(command.operationId, fingerprint);
    if (replay != null) return replay;
    final source = await users.findById(command.anonymousUserId);
    if (source == null) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notFound,
      );
    }
    if (!source.isAnonymous) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notAnonymous,
      );
    }
    if (!await _deletionCoordinator.deleteUser(command.anonymousUserId)) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notFound,
      );
    }
    _replaceAnonymousUserReceipts(
      userId: command.anonymousUserId,
      operationId: command.operationId,
      fingerprint: fingerprint,
    );
    return const AuthAnonymousMutationResult(
      AuthAnonymousMutationStatus.applied,
    );
  });

  AuthAnonymousMutationResult? _anonymousReplay(
    String operationId,
    String fingerprint,
  ) {
    final receipt = _anonymousReceipts[operationId];
    if (receipt == null) return null;
    if (receipt.fingerprint != fingerprint) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.replayMismatch,
      );
    }
    return AuthAnonymousMutationResult(
      AuthAnonymousMutationStatus.replayed,
      user: receipt.user,
    );
  }

  void _replaceAnonymousUserReceipts({
    required String userId,
    required String operationId,
    required String fingerprint,
  }) {
    _anonymousReceipts.removeWhere(
      (_, receipt) => receipt.subjectUserId == userId,
    );
    _anonymousReceipts[operationId] = _AuthAnonymousMutationReceipt(
      fingerprint: fingerprint,
    );
  }

  Future<T> _serializeAnonymousMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _anonymousMutationTail = _anonymousMutationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  void bindUserDeletionPlanContributors(
    Iterable<AuthUserDeletionPlanContributor> contributors,
  ) => _deletionCoordinator.bind(contributors);

  @override
  Future<AuthAccountState?> find(String userId) => _accountStates.find(userId);

  @override
  Future<void> delete(String userId) => _accountStates.delete(userId);

  @override
  Future<AuthAccountState> upsert(AuthAccountState state) =>
      _accountStates.upsert(state);

  @override
  Future<AuthAccountState> recordLogin(String userId, {DateTime? now}) =>
      _accountStates.recordLogin(userId, now: now);

  @override
  Future<AuthAccountState> recordFailedLogin(
    String userId, {
    required AuthAccountPolicy policy,
    DateTime? now,
  }) => _accountStates.recordFailedLogin(userId, policy: policy, now: now);

  @override
  Future<AuthAccountState> resetFailedAttempts(
    String userId, {
    DateTime? now,
  }) => _accountStates.resetFailedAttempts(userId, now: now);

  @override
  Future<AuthAccountState> markEmailVerified(String userId, {DateTime? now}) =>
      _accountStates.markEmailVerified(userId, now: now);

  @override
  Future<AuthAccountState> disable(
    String userId, {
    String? reason,
    DateTime? now,
  }) => _accountStates.disable(userId, reason: reason, now: now);

  @override
  Future<AuthAccountState> enable(String userId, {DateTime? now}) =>
      _accountStates.enable(userId, now: now);

  @override
  Future<AuthAccountState> unlock(String userId, {DateTime? now}) =>
      _accountStates.unlock(userId, now: now);

  @override
  Future<AuthAccountState> recordEmailVerificationSent(
    String userId, {
    DateTime? now,
  }) => _accountStates.recordEmailVerificationSent(userId, now: now);

  @override
  Future<List<AuthAccountState>> findInactiveAccounts({
    required int inactiveDays,
    DateTime? now,
  }) =>
      _accountStates.findInactiveAccounts(inactiveDays: inactiveDays, now: now);

  @override
  Future<List<AuthUser>> listUsersForAdministration() async =>
      List<AuthUser>.unmodifiable(
        _users.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      );

  _InMemoryUserStore get _users => users as _InMemoryUserStore;
  _InMemoryCredentialStore get _credentials =>
      credentials as _InMemoryCredentialStore;
  _InMemoryAccountStore get _accounts => accounts as _InMemoryAccountStore;
  _InMemorySessionStore get _sessions => sessions as _InMemorySessionStore;

  @override
  Future<AuthUser?> updateUserForAdministration(AuthUser user) =>
      _users.update(user);

  @override
  Future<AuthPasswordCredential?> findCredentialForUser(String userId) async =>
      _credentials.values
          .where((credential) => credential.userId == userId.trim())
          .firstOrNull;

  @override
  Future<AuthPasswordCredential> upsertCredentialForAdministration(
    AuthPasswordCredential credential,
  ) async {
    _credentials.upsertForAdministration(credential);
    return credential;
  }

  @override
  Future<bool> deleteUserForAdministration(String userId) =>
      _deletionCoordinator.deleteUser(userId);

  @override
  Future<AuthUser?> findUserForDeletion(String userId) async =>
      users.findById(userId);

  @override
  Future<void> validateUserDeletion(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must be non-empty');
    }
  }

  @override
  Future<bool> consumeUserDeletionToken(String userId, String token) async =>
      await verificationTokens.consume('account_deletion:$userId', token) !=
      null;

  @override
  Future<bool> deleteCoreUserData(String userId) async {
    final id = userId.trim();
    final user = await users.findById(id);
    if (user == null) return false;
    _credentials.deleteForUser(id);
    _accounts.deleteForUser(id);
    _sessions.deleteForUser(id);
    await passwordResetTokens.deleteForUser(id);
    await verificationTokens.delete(id);
    await emailChangeTokens.deleteForUser(id);
    await webAuthnChallenges.deleteForUser(id);
    await (webAuthnAuthenticators as AuthInMemoryUserDeletionStore)
        .deleteUserDataForDeletion(id);
    await deviceAuthorizations.deleteForUser(id);
    await _accountStates.delete(id);
    final phoneNumber = _phoneByUser.remove(id);
    if (phoneNumber != null) {
      _phoneIdentitiesByPhone.remove(phoneNumber);
      final verification = _phoneVerifications.remove(phoneNumber);
      if (verification != null) {
        _phoneIssueReceipts.remove(verification.id);
      }
      _phoneIssueReceipts.removeWhere(
        (_, receipt) => receipt.phoneNumber == phoneNumber,
      );
    }
    if (user.email != null) {
      await emailOtps.deleteForEmail(user.email!);
      await verificationTokens.delete(user.email!);
      final email = normalizeAuthEmail(user.email!);
      _magicLinks.removeWhere((_, record) => record.email == email);
    }
    await jwtVersions.rotate(id);
    _anonymousReceipts.removeWhere((_, receipt) => receipt.subjectUserId == id);
    _users.recordHardDeletion(id);
    _users.delete(id);
    return true;
  }

  @override
  Object captureDeletionState() => (
    usersById: Map<String, AuthUser>.of(_users._usersById),
    usersByEmail: Map<String, AuthUser>.of(_users._usersByEmail),
    deletedUserIdHashes: Set<String>.of(_users._deletedUserIdHashes),
    credentialsById: Map<String, AuthPasswordCredential>.of(
      _credentials._credentialsById,
    ),
    credentialIdsByIdentifier: Map<String, String>.of(
      _credentials._credentialIdsByIdentifier,
    ),
    accounts: Map<(String, String), AuthAccount>.of(_accounts._accounts),
    sessions: Map<String, AuthSessionRecord>.of(_sessions._sessions),
    passwordResetTokens: (passwordResetTokens as AuthInMemoryDeletionState)
        .captureDeletionState(),
    verificationTokens: (verificationTokens as AuthInMemoryDeletionState)
        .captureDeletionState(),
    emailChangeTokens: (emailChangeTokens as AuthInMemoryDeletionState)
        .captureDeletionState(),
    jwtVersions: (jwtVersions as AuthInMemoryDeletionState)
        .captureDeletionState(),
    accountStates: _accountStates.captureDeletionState(),
    webAuthnChallenges: (webAuthnChallenges as AuthInMemoryDeletionState)
        .captureDeletionState(),
    webAuthnAuthenticators:
        (webAuthnAuthenticators as AuthInMemoryDeletionState)
            .captureDeletionState(),
    deviceAuthorizations: (deviceAuthorizations as AuthInMemoryDeletionState)
        .captureDeletionState(),
    emailOtps: (emailOtps as AuthInMemoryDeletionState).captureDeletionState(),
    anonymousReceipts: Map<String, _AuthAnonymousMutationReceipt>.of(
      _anonymousReceipts,
    ),
    magicLinks: Map<String, AuthMagicLinkRecord>.of(_magicLinks),
    phoneVerifications: Map<String, AuthPhoneNumberVerification>.of(
      _phoneVerifications,
    ),
    phoneIdentitiesByPhone: Map<String, AuthPhoneNumberIdentity>.of(
      _phoneIdentitiesByPhone,
    ),
    phoneByUser: Map<String, String>.of(_phoneByUser),
    phoneIssueReceipts: Map<String, _AuthPhoneNumberIssueReceipt>.of(
      _phoneIssueReceipts,
    ),
  );

  @override
  void restoreDeletionState(Object state) {
    final value = state as _InMemoryAuthCoreDeletionState;
    _users._usersById
      ..clear()
      ..addAll(value.usersById);
    _users._usersByEmail
      ..clear()
      ..addAll(value.usersByEmail);
    _users._deletedUserIdHashes
      ..clear()
      ..addAll(value.deletedUserIdHashes);
    _credentials._credentialsById
      ..clear()
      ..addAll(value.credentialsById);
    _credentials._credentialIdsByIdentifier
      ..clear()
      ..addAll(value.credentialIdsByIdentifier);
    _accounts._accounts
      ..clear()
      ..addAll(value.accounts);
    _sessions._sessions
      ..clear()
      ..addAll(value.sessions);
    (passwordResetTokens as AuthInMemoryDeletionState).restoreDeletionState(
      value.passwordResetTokens,
    );
    (verificationTokens as AuthInMemoryDeletionState).restoreDeletionState(
      value.verificationTokens,
    );
    (emailChangeTokens as AuthInMemoryDeletionState).restoreDeletionState(
      value.emailChangeTokens,
    );
    (jwtVersions as AuthInMemoryDeletionState).restoreDeletionState(
      value.jwtVersions,
    );
    _accountStates.restoreDeletionState(value.accountStates);
    (webAuthnChallenges as AuthInMemoryDeletionState).restoreDeletionState(
      value.webAuthnChallenges,
    );
    (webAuthnAuthenticators as AuthInMemoryDeletionState).restoreDeletionState(
      value.webAuthnAuthenticators,
    );
    (deviceAuthorizations as AuthInMemoryDeletionState).restoreDeletionState(
      value.deviceAuthorizations,
    );
    (emailOtps as AuthInMemoryDeletionState).restoreDeletionState(
      value.emailOtps,
    );
    _anonymousReceipts
      ..clear()
      ..addAll(value.anonymousReceipts);
    _magicLinks
      ..clear()
      ..addAll(value.magicLinks);
    _phoneVerifications
      ..clear()
      ..addAll(value.phoneVerifications);
    _phoneIdentitiesByPhone
      ..clear()
      ..addAll(value.phoneIdentitiesByPhone);
    _phoneByUser
      ..clear()
      ..addAll(value.phoneByUser);
    _phoneIssueReceipts
      ..clear()
      ..addAll(value.phoneIssueReceipts);
  }

  @override
  Future<bool> tombstoneUserForAdministration(
    String userId, {
    DateTime? deletedAt,
  }) async {
    final id = userId.trim();
    final user = await users.findById(id);
    if (user == null || authUserIsDisabled(user)) return false;
    final timestamp = (deletedAt ?? DateTime.now()).toUtc();
    _credentials.deleteForUser(id);
    _accounts.deleteForUser(id);
    _sessions.deleteForUser(id);
    await passwordResetTokens.deleteForUser(id);
    await verificationTokens.delete(id);
    await emailChangeTokens.deleteForUser(id);
    await deviceAuthorizations.deleteForUser(id);
    if (user.email != null) await emailOtps.deleteForEmail(user.email!);
    if (user.email != null) {
      await verificationTokens.delete(user.email!);
      final email = normalizeAuthEmail(user.email!);
      _magicLinks.removeWhere((_, record) => record.email == email);
    }
    final phoneNumber = _phoneByUser.remove(id);
    if (phoneNumber != null) {
      _phoneIdentitiesByPhone.remove(phoneNumber);
      _phoneVerifications.remove(phoneNumber);
      _phoneIssueReceipts.removeWhere(
        (_, receipt) => receipt.phoneNumber == phoneNumber,
      );
    }
    _users.replaceWithTombstone(id, timestamp);
    return true;
  }

  @override
  Future<bool> purgeTombstonedUserForAdministration(String userId) async {
    final id = userId.trim();
    final user = await users.findById(id);
    if (user == null || user.attributes['deletedAt'] is! String) return false;
    _users.recordHardDeletion(id);
    _users.delete(id);
    await _accountStates.delete(id);
    return true;
  }
}

/// Callback-backed typed store useful for focused unit tests.
///
/// Each callback belongs to one typed domain store. This is intentionally a
/// store implementation rather than an adapter compatibility layer.
AuthUser _usernameProjection(
  AuthUser user, {
  required String from,
  required String? to,
}) {
  final attributes = Map<String, dynamic>.from(user.attributes);
  if (to == null) {
    attributes.remove('username');
  } else {
    attributes['username'] = to;
  }
  return AuthUser(
    id: user.id,
    email: user.email,
    name: user.name == from ? to : user.name,
    image: user.image,
    roles: user.roles,
    isAnonymous: user.isAnonymous,
    attributes: attributes,
  );
}

AuthUser _phoneVerifiedUser(AuthUser user, String phoneNumber) {
  if (user.attributes['phoneNumber'] == phoneNumber &&
      user.attributes['phoneNumberVerified'] == true) {
    return user;
  }
  return AuthUser(
    id: user.id,
    email: user.email,
    name: user.name,
    image: user.image,
    roles: user.roles,
    isAnonymous: user.isAnonymous,
    attributes: <String, dynamic>{
      ...user.attributes,
      'phoneNumber': phoneNumber,
      'phoneNumberVerified': true,
    },
  );
}

/// Callback-backed auth store for focused tests and compatibility adapters.
class CallbackAuthStore implements AuthStore, AuthWebAuthnStoreCapabilities {
  /// Creates a store from callbacks for the supported persistence operations.
  CallbackAuthStore({
    FutureOr<AuthUser?> Function(String id)? onFindUserById,
    FutureOr<AuthUser?> Function(String email)? onFindUserByEmail,
    FutureOr<AuthUser> Function(AuthUser user)? onCreateUser,
    FutureOr<AuthUserCreateResult> Function(AuthUser user)?
    onCreateOrFindUserByEmail,
    FutureOr<AuthUser?> Function(AuthUser user)? onUpdateUser,
    FutureOr<AuthUser?> Function(String userId, String email)?
    onUpdateUserEmail,
    FutureOr<bool> Function(String userId)? onDeleteUser,
    FutureOr<AuthPasswordCredential?> Function(String identifier)?
    onFindCredential,
    FutureOr<AuthPasswordCredential?> Function(String userId)?
    onFindCredentialForUser,
    FutureOr<AuthUser?> Function(
      AuthUser user,
      AuthPasswordCredential credential,
    )?
    onRegisterCredential,
    FutureOr<AuthPasswordCredential?> Function(
      AuthPasswordCredential credential,
    )?
    onUpdateCredential,
    FutureOr<int> Function({
      required String userId,
      required String passwordHash,
      required DateTime updatedAt,
    })?
    onUpdatePasswordForUser,
    FutureOr<void> Function(String credentialId)? onDeleteCredential,
    FutureOr<void> Function(String userId)? onDeleteCredentialsForUser,
    FutureOr<AuthAccount?> Function(
      String providerId,
      String providerAccountId,
    )?
    onFindAccount,
    FutureOr<List<AuthAccount>> Function(String userId)? onListAccountsForUser,
    FutureOr<AuthAccount> Function(AuthAccount account)? onLinkAccount,
    FutureOr<bool> Function(
      String userId,
      String providerId,
      String providerAccountId,
    )?
    onUnlinkAccountForUser,
    FutureOr<void> Function(String userId)? onDeleteAccountsForUser,
    FutureOr<AuthSessionRecord?> Function(String tokenHash)? onFindSession,
    FutureOr<AuthSessionRecord> Function(AuthSessionRecord session)?
    onCreateSession,
    FutureOr<AuthSessionRecord?> Function(
      String tokenHash,
      DateTime lastUsedAt,
    )?
    onTouchSession,
    FutureOr<List<AuthSessionRecord>> Function(String userId)?
    onListSessionsForUser,
    FutureOr<AuthSessionRecord?> Function(
      String tokenHash, {
      DateTime? revokedAt,
    })?
    onRevokeSession,
    FutureOr<AuthSessionRecord?> Function(
      String userId,
      String sessionId, {
      DateTime? revokedAt,
    })?
    onRevokeSessionById,
    FutureOr<int> Function(String userId, {DateTime? revokedAt})?
    onRevokeAllSessionsForUser,
    FutureOr<int> Function(
      String userId,
      String currentSessionId, {
      DateTime? revokedAt,
    })?
    onRevokeAllSessionsForUserExcept,
    FutureOr<AuthSessionRecord?> Function({
      required String previousTokenHash,
      required AuthSessionRecord replacement,
    })?
    onRotateSession,
    FutureOr<void> Function(AuthOAuthChallenge challenge)? onSaveOAuthChallenge,
    FutureOr<AuthOAuthChallenge?> Function(String providerId, String state)?
    onConsumeOAuthChallenge,
    AuthOAuthChallengeStore? oauthChallenges,
    FutureOr<void> Function(AuthPasswordResetToken token)?
    onSavePasswordResetToken,
    FutureOr<AuthPasswordResetToken?> Function(String token)?
    onConsumePasswordResetToken,
    FutureOr<AuthPasswordResetToken?> Function(String token)?
    onFindPasswordResetToken,
    FutureOr<void> Function(String userId)? onDeletePasswordResetTokens,
    AuthPasswordResetTokenStore? passwordResetTokens,
    FutureOr<int> Function(String userId)? onCurrentJwtVersion,
    FutureOr<int> Function(String userId)? onRotateJwtVersion,
    AuthJwtVersionStore? jwtVersions,
    FutureOr<void> Function(AuthVerificationToken token)?
    onSaveVerificationToken,
    FutureOr<AuthVerificationToken?> Function(String identifier, String token)?
    onConsumeVerificationToken,
    FutureOr<bool> Function(String identifier, String token)?
    onDeleteVerificationToken,
    FutureOr<void> Function(String identifier)? onDeleteVerificationTokens,
    AuthVerificationTokenStore? verificationTokens,
    FutureOr<void> Function(AuthEmailChangeToken token)? onSaveEmailChangeToken,
    FutureOr<AuthEmailChangeToken?> Function(String token)?
    onConsumeEmailChangeToken,
    FutureOr<bool> Function(String userId, String token)?
    onDeleteEmailChangeToken,
    FutureOr<void> Function(String userId)? onDeleteEmailChangeTokens,
    AuthEmailChangeTokenStore? emailChangeTokens,
    AuthWebAuthnChallengeStore? webAuthnChallenges,
    AuthWebAuthnAuthenticatorStore? webAuthnAuthenticators,
    AuthDeviceAuthorizationStore? deviceAuthorizations,
    AuthEmailOtpStore? emailOtps,
  }) : users = _CallbackUserStore(
         onFindById: onFindUserById,
         onFindByEmail: onFindUserByEmail,
         onCreate: onCreateUser,
         onCreateOrFindByEmail: onCreateOrFindUserByEmail,
         onUpdate: onUpdateUser,
         onUpdateEmail: onUpdateUserEmail,
         onDelete: onDeleteUser,
       ),
       credentials = _CallbackCredentialStore(
         onFind: onFindCredential,
         onFindForUser: onFindCredentialForUser,
         onRegister: onRegisterCredential,
         onUpdate: onUpdateCredential,
         onUpdatePasswordForUser: onUpdatePasswordForUser,
         onDelete: onDeleteCredential,
         onDeleteForUser: onDeleteCredentialsForUser,
       ),
       accounts = _CallbackAccountStore(
         onFind: onFindAccount,
         onListForUser: onListAccountsForUser,
         onLink: onLinkAccount,
         onUnlinkForUser: onUnlinkAccountForUser,
         onDeleteForUser: onDeleteAccountsForUser,
       ),
       sessions = _CallbackSessionStore(
         onFind: onFindSession,
         onCreate: onCreateSession,
         onTouch: onTouchSession,
         onListForUser: onListSessionsForUser,
         onRevoke: onRevokeSession,
         onRevokeById: onRevokeSessionById,
         onRevokeAllForUser: onRevokeAllSessionsForUser,
         onRevokeAllForUserExcept: onRevokeAllSessionsForUserExcept,
         onRotate: onRotateSession,
       ),
       oauthChallenges =
           oauthChallenges ??
           _CallbackOAuthChallengeStore(
             onSave: onSaveOAuthChallenge,
             onConsume: onConsumeOAuthChallenge,
           ),
       passwordResetTokens =
           passwordResetTokens ??
           _CallbackPasswordResetTokenStore(
             onSave: onSavePasswordResetToken,
             onConsume: onConsumePasswordResetToken,
             onFindActive: onFindPasswordResetToken,
             onDeleteForUser: onDeletePasswordResetTokens,
           ),
       jwtVersions =
           jwtVersions ??
           _CallbackJwtVersionStore(
             onCurrent: onCurrentJwtVersion,
             onRotate: onRotateJwtVersion,
           ),
       verificationTokens =
           verificationTokens ??
           _CallbackVerificationTokenStore(
             onSave: onSaveVerificationToken,
             onConsume: onConsumeVerificationToken,
             onDeleteToken: onDeleteVerificationToken,
             onDelete: onDeleteVerificationTokens,
           ),
       emailChangeTokens =
           emailChangeTokens ??
           _CallbackEmailChangeTokenStore(
             onSave: onSaveEmailChangeToken,
             onConsume: onConsumeEmailChangeToken,
             onDeleteTokenForUser: onDeleteEmailChangeToken,
             onDeleteForUser: onDeleteEmailChangeTokens,
           ),
       webAuthnChallenges =
           webAuthnChallenges ?? InMemoryAuthWebAuthnChallengeStore(),
       webAuthnAuthenticators =
           webAuthnAuthenticators ?? InMemoryAuthWebAuthnAuthenticatorStore(),
       deviceAuthorizations =
           deviceAuthorizations ?? InMemoryAuthDeviceAuthorizationStore(),
       emailOtps = emailOtps ?? InMemoryAuthEmailOtpStore();

  @override
  final AuthUserStore users;

  @override
  final AuthCredentialStore credentials;

  @override
  final AuthAccountStore accounts;

  @override
  final AuthSessionStore sessions;

  @override
  final AuthOAuthChallengeStore oauthChallenges;

  @override
  final AuthPasswordResetTokenStore passwordResetTokens;

  @override
  final AuthJwtVersionStore jwtVersions;

  @override
  final AuthVerificationTokenStore verificationTokens;

  @override
  final AuthEmailChangeTokenStore emailChangeTokens;

  @override
  final AuthWebAuthnChallengeStore webAuthnChallenges;

  @override
  final AuthWebAuthnAuthenticatorStore webAuthnAuthenticators;

  @override
  final AuthDeviceAuthorizationStore deviceAuthorizations;

  @override
  final AuthEmailOtpStore emailOtps;
}

class _CallbackPasswordResetTokenStore implements AuthPasswordResetTokenStore {
  const _CallbackPasswordResetTokenStore({
    this.onSave,
    this.onConsume,
    this.onFindActive,
    this.onDeleteForUser,
  });

  final FutureOr<void> Function(AuthPasswordResetToken token)? onSave;
  final FutureOr<AuthPasswordResetToken?> Function(String token)? onConsume;
  final FutureOr<AuthPasswordResetToken?> Function(String token)? onFindActive;
  final FutureOr<void> Function(String userId)? onDeleteForUser;

  @override
  FutureOr<void> save(AuthPasswordResetToken token) => onSave?.call(token);

  @override
  FutureOr<AuthPasswordResetToken?> consume(String token) =>
      onConsume?.call(token);

  @override
  FutureOr<AuthPasswordResetToken?> findActive(String token) =>
      onFindActive?.call(token);

  @override
  FutureOr<void> deleteForUser(String userId) => onDeleteForUser?.call(userId);
}

class _CallbackJwtVersionStore implements AuthJwtVersionStore {
  _CallbackJwtVersionStore({this.onCurrent, this.onRotate});

  final FutureOr<int> Function(String userId)? onCurrent;
  final FutureOr<int> Function(String userId)? onRotate;
  final Map<String, int> _versions = <String, int>{};

  @override
  FutureOr<int> current(String userId) {
    _validateUserId(userId);
    return onCurrent?.call(userId) ?? _versions[userId] ?? 0;
  }

  @override
  FutureOr<int> rotate(String userId) {
    _validateUserId(userId);
    if (onRotate != null) {
      return onRotate!(userId);
    }
    final next = (_versions[userId] ?? 0) + 1;
    _versions[userId] = next;
    return next;
  }

  void _validateUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must be non-empty');
    }
  }
}

class _CallbackOAuthChallengeStore implements AuthOAuthChallengeStore {
  const _CallbackOAuthChallengeStore({this.onSave, this.onConsume});

  final FutureOr<void> Function(AuthOAuthChallenge challenge)? onSave;
  final FutureOr<AuthOAuthChallenge?> Function(String providerId, String state)?
  onConsume;

  @override
  FutureOr<void> save(AuthOAuthChallenge challenge) => onSave?.call(challenge);

  @override
  FutureOr<AuthOAuthChallenge?> consume(String providerId, String state) =>
      onConsume?.call(providerId, state);
}

class _InMemoryUserStore implements AuthUserStore {
  final Map<String, AuthUser> _usersById = <String, AuthUser>{};
  final Map<String, AuthUser> _usersByEmail = <String, AuthUser>{};
  final Set<String> _deletedUserIdHashes = <String>{};

  Iterable<AuthUser> get values => _usersById.values;
  bool contains(String id) => _usersById.containsKey(id);

  bool wasHardDeleted(String id) =>
      _deletedUserIdHashes.contains(hashOpaqueToken(id.trim()));

  void recordHardDeletion(String id) {
    _deletedUserIdHashes.add(hashOpaqueToken(id.trim()));
  }

  @override
  Future<bool> delete(String id) async {
    final removed = _usersById.remove(id);
    if (removed?.email != null) _usersByEmail.remove(removed!.email);
    return removed != null;
  }

  void replaceWithTombstone(String id, DateTime deletedAt) {
    final previous = _usersById[id];
    if (previous?.email != null) _usersByEmail.remove(previous!.email);
    _usersById[id] = AuthUser(
      id: id,
      attributes: <String, dynamic>{
        'deletedAt': deletedAt.toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<AuthUser?> findById(String id) async => _usersById[id];

  @override
  Future<AuthUser?> findByEmail(String email) async => _usersByEmail[email];

  @override
  Future<AuthUser> create(AuthUser user) async {
    validateAuthUserForPersistence(user);
    if (wasHardDeleted(user.id)) {
      throw StateError('Auth user ID is permanently unavailable');
    }
    if (_usersById.containsKey(user.id)) {
      throw StateError('Auth user ID already exists');
    }
    final email = user.email;
    if (email != null && _usersByEmail.containsKey(email)) {
      throw StateError('Auth user email already exists');
    }
    _usersById[user.id] = user;
    if (email != null) {
      _usersByEmail[email] = user;
    }
    return user;
  }

  @override
  Future<AuthUserCreateResult> createOrFindByEmail(AuthUser user) async {
    validateAuthUserForPersistence(user);
    if (wasHardDeleted(user.id)) {
      throw StateError('Auth user ID is permanently unavailable');
    }
    final existingById = _usersById[user.id];
    if (existingById != null) {
      return AuthUserCreateResult(user: existingById, created: false);
    }
    final email = user.email;
    if (email != null) {
      final existingByEmail = _usersByEmail[email];
      if (existingByEmail != null) {
        return AuthUserCreateResult(user: existingByEmail, created: false);
      }
    }
    _usersById[user.id] = user;
    if (email != null) {
      _usersByEmail[email] = user;
    }
    return AuthUserCreateResult(user: user, created: true);
  }

  @override
  Future<AuthUser?> update(AuthUser user) async {
    validateAuthUserForPersistence(user);
    final previous = _usersById[user.id];
    if (previous == null) {
      return null;
    }
    final email = user.email;
    final existingByEmail = email == null ? null : _usersByEmail[email];
    if (existingByEmail != null && existingByEmail.id != user.id) {
      return null;
    }
    if (previous.email != null && previous.email != email) {
      _usersByEmail.remove(previous.email);
    }
    _usersById[user.id] = user;
    if (email != null) {
      _usersByEmail[email] = user;
    }
    return user;
  }

  @override
  Future<AuthUser?> updateEmailForUser(String userId, String email) async {
    final normalizedUserId = userId.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedUserId.isEmpty || normalizedEmail.isEmpty) return null;
    final current = _usersById[normalizedUserId];
    if (current == null) return null;
    final existing = _usersByEmail[normalizedEmail];
    if (existing != null && existing.id != normalizedUserId) return null;
    final updated = AuthUser(
      id: current.id,
      email: normalizedEmail,
      name: current.name,
      image: current.image,
      roles: current.roles,
      attributes: current.attributes,
    );
    if (current.email != null) _usersByEmail.remove(current.email);
    _usersById[normalizedUserId] = updated;
    _usersByEmail[normalizedEmail] = updated;
    return updated;
  }
}

class _InMemoryCredentialStore
    implements AuthCredentialStore, AuthCredentialUserLookupStore {
  AuthUserStore? users;
  final Map<String, AuthPasswordCredential> _credentialsById =
      <String, AuthPasswordCredential>{};
  final Map<String, String> _credentialIdsByIdentifier = <String, String>{};
  final Set<String> _inFlightIdentifiers = <String>{};
  final Set<String> _inFlightCredentialIds = <String>{};
  final Set<String> _inFlightEmails = <String>{};

  Iterable<AuthPasswordCredential> get values => _credentialsById.values;

  void upsertForAdministration(AuthPasswordCredential credential) {
    final previous = _credentialsById[credential.id];
    final conflictingId = _credentialIdsByIdentifier[credential.identifier];
    if (conflictingId != null && conflictingId != credential.id) {
      throw StateError('Auth user email already exists');
    }
    if (previous != null && previous.identifier != credential.identifier) {
      _credentialIdsByIdentifier.remove(previous.identifier);
    }
    _credentialsById[credential.id] = credential;
    _credentialIdsByIdentifier[credential.identifier] = credential.id;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    final ids = _credentialsById.values
        .where((credential) => credential.userId == userId)
        .map((credential) => credential.id)
        .toList(growable: false);
    for (final id in ids) {
      final removed = _credentialsById.remove(id);
      if (removed != null) {
        _credentialIdsByIdentifier.remove(removed.identifier);
      }
    }
  }

  @override
  Future<AuthPasswordCredential?> findByIdentifier(String identifier) async {
    if (identifier.trim().isEmpty) {
      return null;
    }
    final credentialId = _credentialIdsByIdentifier[identifier];
    return credentialId == null ? null : _credentialsById[credentialId];
  }

  @override
  Future<AuthPasswordCredential?> findForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return null;
    for (final credential in _credentialsById.values) {
      if (credential.userId == normalizedUserId) return credential;
    }
    return null;
  }

  Future<AuthPasswordCredential?> findUsernameForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return null;
    for (final credential in _credentialsById.values) {
      if (credential.userId == normalizedUserId &&
          !credential.identifier.contains('@')) {
        return credential;
      }
    }
    return null;
  }

  @override
  Future<AuthUser?> register(
    AuthUser user,
    AuthPasswordCredential credential,
  ) => _register(user, credential, username: false);

  Future<AuthUser?> _register(
    AuthUser user,
    AuthPasswordCredential credential, {
    required bool username,
    FutureOr<void> Function()? afterUserWrite,
  }) async {
    if (credential.id.trim().isEmpty ||
        credential.userId.trim().isEmpty ||
        credential.identifier.trim().isEmpty ||
        credential.passwordHash.isEmpty ||
        credential.userId != user.id ||
        (username && credential.identifier.contains('@')) ||
        _credentialIdsByIdentifier.containsKey(credential.identifier) ||
        _credentialsById.containsKey(credential.id)) {
      return null;
    }
    final reservedIdentifier = _inFlightIdentifiers.add(credential.identifier);
    if (!reservedIdentifier) {
      return null;
    }
    final reservedCredentialId = _inFlightCredentialIds.add(credential.id);
    if (!reservedCredentialId) {
      _inFlightIdentifiers.remove(credential.identifier);
      return null;
    }
    final email = user.email;
    final reservedEmail = email == null || _inFlightEmails.add(email);
    if (!reservedEmail) {
      _inFlightIdentifiers.remove(credential.identifier);
      _inFlightCredentialIds.remove(credential.id);
      return null;
    }
    try {
      final userStore = users;
      if (userStore == null) {
        return null;
      }
      final existing = await userStore.findById(user.id);
      final existingEmail = email == null
          ? null
          : await userStore.findByEmail(email);
      if (existing != null ||
          existingEmail != null ||
          _credentialIdsByIdentifier.containsKey(credential.identifier) ||
          _credentialsById.containsKey(credential.id)) {
        return null;
      }
      AuthUser? created;
      try {
        created = await userStore.create(user);
        await afterUserWrite?.call();
        _credentialsById[credential.id] = credential;
        _credentialIdsByIdentifier[credential.identifier] = credential.id;
        return created;
      } catch (_) {
        if (created != null) await userStore.delete(user.id);
        _credentialsById.remove(credential.id);
        _credentialIdsByIdentifier.remove(credential.identifier);
        rethrow;
      }
    } finally {
      _inFlightIdentifiers.remove(credential.identifier);
      _inFlightCredentialIds.remove(credential.id);
      if (email != null) _inFlightEmails.remove(email);
    }
  }

  @override
  Future<AuthPasswordCredential?> update(
    AuthPasswordCredential credential,
  ) async {
    if (credential.id.trim().isEmpty ||
        credential.userId.trim().isEmpty ||
        credential.identifier.trim().isEmpty ||
        credential.passwordHash.isEmpty ||
        !_credentialsById.containsKey(credential.id) ||
        _credentialIdsByIdentifier[credential.identifier] != credential.id) {
      return null;
    }
    _credentialsById[credential.id] = credential;
    return credential;
  }

  @override
  Future<int> updatePasswordForUser({
    required String userId,
    required String passwordHash,
    required DateTime updatedAt,
  }) async {
    if (userId.trim().isEmpty || passwordHash.trim().isEmpty) {
      return 0;
    }
    final credentials = _credentialsById.values
        .where((credential) => credential.userId == userId)
        .toList(growable: false);
    for (final credential in credentials) {
      _credentialsById[credential.id] = credential.copyWith(
        passwordHash: passwordHash,
        updatedAt: updatedAt,
      );
    }
    return credentials.length;
  }

  @override
  Future<void> delete(String credentialId) async {
    final removed = _credentialsById.remove(credentialId);
    if (removed != null) {
      _credentialIdsByIdentifier.remove(removed.identifier);
    }
  }
}

class _InMemoryAccountStore implements AuthAccountStore {
  final Map<(String, String), AuthAccount> _accounts =
      <(String, String), AuthAccount>{};

  @override
  Future<void> deleteForUser(String userId) async =>
      _accounts.removeWhere((_, account) => account.userId == userId);

  @override
  Future<AuthAccount?> find(String providerId, String providerAccountId) async {
    return _accounts[(providerId, providerAccountId)];
  }

  @override
  Future<List<AuthAccount>> listForUser(String userId) async {
    final normalizedUserId = userId.trim();
    return _accounts.values
        .where((account) => account.userId == normalizedUserId)
        .map((account) => account.redacted())
        .toList(growable: false);
  }

  @override
  Future<AuthAccount> link(AuthAccount account) async {
    validateAuthAccountForLink(account);
    final key = (account.providerId, account.providerAccountId);
    return _accounts.putIfAbsent(key, () => account);
  }

  @override
  Future<bool> unlinkForUser(
    String userId,
    String providerId,
    String providerAccountId,
  ) async {
    final key = (providerId.trim(), providerAccountId.trim());
    final account = _accounts[key];
    final normalizedUserId = userId.trim();
    if (account?.userId != normalizedUserId) {
      return false;
    }
    _accounts.remove(key);
    return true;
  }
}

class _InMemorySessionStore implements AuthSessionStore {
  final Map<String, AuthSessionRecord> _sessions =
      <String, AuthSessionRecord>{};

  void deleteForUser(String userId) =>
      _sessions.removeWhere((_, session) => session.userId == userId);

  @override
  Future<AuthSessionRecord?> find(String tokenHash) async =>
      tokenHash.trim().isEmpty ? null : _sessions[tokenHash];

  @override
  Future<AuthSessionRecord> create(AuthSessionRecord session) async {
    validateAuthSessionForPersistence(session);
    if (_sessions.containsKey(session.tokenHash)) {
      throw StateError('Auth session token hash already exists');
    }
    _sessions[session.tokenHash] = session;
    return session;
  }

  @override
  Future<AuthSessionRecord?> touch(
    String tokenHash,
    DateTime lastUsedAt,
  ) async {
    final session = _sessions[tokenHash];
    if (tokenHash.trim().isEmpty || session == null || !session.isActive()) {
      return null;
    }
    final updated = session.copyWith(
      lastUsedAt: lastUsedAt.isAfter(session.lastUsedAt)
          ? lastUsedAt
          : session.lastUsedAt,
    );
    _sessions[tokenHash] = updated;
    return updated;
  }

  @override
  Future<List<AuthSessionRecord>> listForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return const <AuthSessionRecord>[];
    return _sessions.values
        .where((session) => session.userId == normalizedUserId)
        .toList(growable: false);
  }

  @override
  Future<AuthSessionRecord?> revoke(
    String tokenHash, {
    DateTime? revokedAt,
  }) async {
    if (tokenHash.trim().isEmpty) {
      return null;
    }
    final session = _sessions[tokenHash];
    if (session == null) {
      return null;
    }
    if (session.revokedAt != null) {
      return session;
    }
    final updated = session.copyWith(
      revokedAt: (revokedAt ?? DateTime.now()).toUtc(),
    );
    _sessions[tokenHash] = updated;
    return updated;
  }

  @override
  Future<AuthSessionRecord?> revokeById(
    String userId,
    String sessionId, {
    DateTime? revokedAt,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedSessionId = sessionId.trim();
    if (normalizedUserId.isEmpty || normalizedSessionId.isEmpty) return null;
    final entry = _sessions.entries
        .cast<MapEntry<String, AuthSessionRecord>?>()
        .firstWhere(
          (candidate) =>
              candidate!.value.id == normalizedSessionId &&
              candidate.value.userId == normalizedUserId,
          orElse: () => null,
        );
    final session = entry?.value;
    if (session == null) return null;
    if (session.revokedAt != null) return session;
    final updated = session.copyWith(
      revokedAt: (revokedAt ?? DateTime.now()).toUtc(),
    );
    _sessions[entry!.key] = updated;
    return updated;
  }

  @override
  Future<int> revokeAllForUser(String userId, {DateTime? revokedAt}) async {
    if (userId.trim().isEmpty) {
      return 0;
    }
    final timestamp = (revokedAt ?? DateTime.now()).toUtc();
    var revokedCount = 0;
    for (final entry in _sessions.entries.toList(growable: false)) {
      final session = entry.value;
      if (session.userId != userId || session.revokedAt != null) {
        continue;
      }
      _sessions[entry.key] = session.copyWith(revokedAt: timestamp);
      revokedCount += 1;
    }
    return revokedCount;
  }

  @override
  Future<int> revokeAllForUserExcept(
    String userId,
    String currentSessionId, {
    DateTime? revokedAt,
  }) async {
    if (userId.trim().isEmpty) return 0;
    final timestamp = (revokedAt ?? DateTime.now()).toUtc();
    var revokedCount = 0;
    for (final entry in _sessions.entries.toList(growable: false)) {
      final session = entry.value;
      if (session.userId != userId ||
          session.id == currentSessionId ||
          session.revokedAt != null) {
        continue;
      }
      _sessions[entry.key] = session.copyWith(revokedAt: timestamp);
      revokedCount += 1;
    }
    return revokedCount;
  }

  @override
  Future<AuthSessionRecord?> rotate({
    required String previousTokenHash,
    required AuthSessionRecord replacement,
  }) async {
    validateAuthSessionForPersistence(replacement);
    if (previousTokenHash.trim().isEmpty) {
      return null;
    }
    final previous = _sessions[previousTokenHash];
    if (previous == null || !previous.isActive()) {
      return null;
    }
    if (_sessions.containsKey(replacement.tokenHash)) {
      throw StateError('Auth session token hash already exists');
    }
    _sessions[previousTokenHash] = previous.copyWith(
      revokedAt: DateTime.now().toUtc(),
    );
    _sessions[replacement.tokenHash] = replacement;
    return replacement;
  }
}

class _CallbackUserStore implements AuthUserStore {
  const _CallbackUserStore({
    this.onFindById,
    this.onFindByEmail,
    this.onCreate,
    this.onCreateOrFindByEmail,
    this.onUpdate,
    this.onUpdateEmail,
    this.onDelete,
  });

  final FutureOr<AuthUser?> Function(String id)? onFindById;
  final FutureOr<AuthUser?> Function(String email)? onFindByEmail;
  final FutureOr<AuthUser> Function(AuthUser user)? onCreate;
  final FutureOr<AuthUserCreateResult> Function(AuthUser user)?
  onCreateOrFindByEmail;
  final FutureOr<AuthUser?> Function(AuthUser user)? onUpdate;
  final FutureOr<AuthUser?> Function(String userId, String email)?
  onUpdateEmail;
  final FutureOr<bool> Function(String userId)? onDelete;

  @override
  FutureOr<AuthUser?> findById(String id) => onFindById?.call(id);

  @override
  FutureOr<AuthUser?> findByEmail(String email) => onFindByEmail?.call(email);

  @override
  FutureOr<AuthUser> create(AuthUser user) => onCreate?.call(user) ?? user;

  @override
  Future<AuthUserCreateResult> createOrFindByEmail(AuthUser user) async {
    final callback = onCreateOrFindByEmail;
    if (callback != null) {
      return Future.sync(() => callback(user));
    }
    final existing = await Future<AuthUser?>.sync(
      () => onFindByEmail?.call(user.email ?? ''),
    );
    if (existing != null) {
      return AuthUserCreateResult(user: existing, created: false);
    }
    final created = await Future.sync(() => onCreate?.call(user) ?? user);
    return AuthUserCreateResult(user: created, created: true);
  }

  @override
  FutureOr<AuthUser?> update(AuthUser user) => onUpdate?.call(user) ?? user;

  @override
  FutureOr<AuthUser?> updateEmailForUser(String userId, String email) =>
      onUpdateEmail?.call(userId, email);

  @override
  FutureOr<bool> delete(String userId) => onDelete?.call(userId) ?? false;
}

class _CallbackCredentialStore
    implements AuthCredentialStore, AuthCredentialUserLookupStore {
  const _CallbackCredentialStore({
    this.onFind,
    this.onFindForUser,
    this.onRegister,
    this.onUpdate,
    this.onUpdatePasswordForUser,
    this.onDelete,
    this.onDeleteForUser,
  });

  final FutureOr<AuthPasswordCredential?> Function(String identifier)? onFind;
  final FutureOr<AuthPasswordCredential?> Function(String userId)?
  onFindForUser;
  final FutureOr<AuthUser?> Function(
    AuthUser user,
    AuthPasswordCredential credential,
  )?
  onRegister;
  final FutureOr<AuthPasswordCredential?> Function(
    AuthPasswordCredential credential,
  )?
  onUpdate;
  final FutureOr<int> Function({
    required String userId,
    required String passwordHash,
    required DateTime updatedAt,
  })?
  onUpdatePasswordForUser;
  final FutureOr<void> Function(String credentialId)? onDelete;
  final FutureOr<void> Function(String userId)? onDeleteForUser;

  @override
  FutureOr<AuthPasswordCredential?> findByIdentifier(String identifier) =>
      onFind?.call(identifier);

  @override
  FutureOr<AuthPasswordCredential?> findForUser(String userId) =>
      onFindForUser?.call(userId);

  @override
  FutureOr<AuthUser?> register(
    AuthUser user,
    AuthPasswordCredential credential,
  ) => onRegister?.call(user, credential);

  @override
  FutureOr<AuthPasswordCredential?> update(AuthPasswordCredential credential) =>
      onUpdate?.call(credential);

  @override
  FutureOr<int> updatePasswordForUser({
    required String userId,
    required String passwordHash,
    required DateTime updatedAt,
  }) =>
      onUpdatePasswordForUser?.call(
        userId: userId,
        passwordHash: passwordHash,
        updatedAt: updatedAt,
      ) ??
      0;

  @override
  FutureOr<void> delete(String credentialId) => onDelete?.call(credentialId);

  @override
  FutureOr<void> deleteForUser(String userId) => onDeleteForUser?.call(userId);
}

class _CallbackAccountStore implements AuthAccountStore {
  const _CallbackAccountStore({
    this.onFind,
    this.onListForUser,
    this.onLink,
    this.onUnlinkForUser,
    this.onDeleteForUser,
  });

  final FutureOr<AuthAccount?> Function(
    String providerId,
    String providerAccountId,
  )?
  onFind;
  final FutureOr<List<AuthAccount>> Function(String userId)? onListForUser;
  final FutureOr<AuthAccount> Function(AuthAccount account)? onLink;
  final FutureOr<bool> Function(
    String userId,
    String providerId,
    String providerAccountId,
  )?
  onUnlinkForUser;
  final FutureOr<void> Function(String userId)? onDeleteForUser;

  @override
  FutureOr<AuthAccount?> find(String providerId, String providerAccountId) =>
      onFind?.call(providerId, providerAccountId);

  @override
  FutureOr<List<AuthAccount>> listForUser(String userId) =>
      onListForUser?.call(userId) ?? const <AuthAccount>[];

  @override
  FutureOr<AuthAccount> link(AuthAccount account) =>
      onLink?.call(account) ?? account;

  @override
  FutureOr<bool> unlinkForUser(
    String userId,
    String providerId,
    String providerAccountId,
  ) => onUnlinkForUser?.call(userId, providerId, providerAccountId) ?? false;

  @override
  FutureOr<void> deleteForUser(String userId) => onDeleteForUser?.call(userId);
}

class _CallbackSessionStore implements AuthSessionStore {
  const _CallbackSessionStore({
    this.onFind,
    this.onCreate,
    this.onTouch,
    this.onListForUser,
    this.onRevoke,
    this.onRevokeById,
    this.onRevokeAllForUser,
    this.onRevokeAllForUserExcept,
    this.onRotate,
  });

  final FutureOr<AuthSessionRecord?> Function(String tokenHash)? onFind;
  final FutureOr<AuthSessionRecord> Function(AuthSessionRecord session)?
  onCreate;
  final FutureOr<AuthSessionRecord?> Function(
    String tokenHash,
    DateTime lastUsedAt,
  )?
  onTouch;
  final FutureOr<List<AuthSessionRecord>> Function(String userId)?
  onListForUser;
  final FutureOr<AuthSessionRecord?> Function(
    String tokenHash, {
    DateTime? revokedAt,
  })?
  onRevoke;
  final FutureOr<AuthSessionRecord?> Function(
    String userId,
    String sessionId, {
    DateTime? revokedAt,
  })?
  onRevokeById;
  final FutureOr<int> Function(String userId, {DateTime? revokedAt})?
  onRevokeAllForUser;
  final FutureOr<int> Function(
    String userId,
    String currentSessionId, {
    DateTime? revokedAt,
  })?
  onRevokeAllForUserExcept;
  final FutureOr<AuthSessionRecord?> Function({
    required String previousTokenHash,
    required AuthSessionRecord replacement,
  })?
  onRotate;

  @override
  FutureOr<AuthSessionRecord?> find(String tokenHash) =>
      onFind?.call(tokenHash);

  @override
  FutureOr<AuthSessionRecord> create(AuthSessionRecord session) =>
      onCreate?.call(session) ?? session;

  @override
  FutureOr<AuthSessionRecord?> touch(String tokenHash, DateTime lastUsedAt) =>
      onTouch?.call(tokenHash, lastUsedAt);

  @override
  FutureOr<List<AuthSessionRecord>> listForUser(String userId) =>
      onListForUser?.call(userId) ?? const <AuthSessionRecord>[];

  @override
  FutureOr<AuthSessionRecord?> revoke(
    String tokenHash, {
    DateTime? revokedAt,
  }) => onRevoke?.call(tokenHash, revokedAt: revokedAt);

  @override
  FutureOr<AuthSessionRecord?> revokeById(
    String userId,
    String sessionId, {
    DateTime? revokedAt,
  }) => onRevokeById?.call(userId, sessionId, revokedAt: revokedAt);

  @override
  FutureOr<int> revokeAllForUser(String userId, {DateTime? revokedAt}) =>
      onRevokeAllForUser?.call(userId, revokedAt: revokedAt) ?? 0;

  @override
  FutureOr<int> revokeAllForUserExcept(
    String userId,
    String currentSessionId, {
    DateTime? revokedAt,
  }) =>
      onRevokeAllForUserExcept?.call(
        userId,
        currentSessionId,
        revokedAt: revokedAt,
      ) ??
      0;

  @override
  FutureOr<AuthSessionRecord?> rotate({
    required String previousTokenHash,
    required AuthSessionRecord replacement,
  }) => onRotate?.call(
    previousTokenHash: previousTokenHash,
    replacement: replacement,
  );
}

class _CallbackVerificationTokenStore
    implements
        AuthVerificationTokenStore,
        AuthVerificationTokenConditionalDeleteStore {
  const _CallbackVerificationTokenStore({
    this.onSave,
    this.onConsume,
    this.onDeleteToken,
    this.onDelete,
  });

  final FutureOr<void> Function(AuthVerificationToken token)? onSave;
  final FutureOr<AuthVerificationToken?> Function(
    String identifier,
    String token,
  )?
  onConsume;
  final FutureOr<bool> Function(String identifier, String token)? onDeleteToken;
  final FutureOr<void> Function(String identifier)? onDelete;

  @override
  FutureOr<void> save(AuthVerificationToken token) => onSave?.call(token);

  @override
  FutureOr<AuthVerificationToken?> consume(String identifier, String token) =>
      onConsume?.call(identifier, token);

  @override
  FutureOr<bool> deleteToken(String identifier, String token) =>
      onDeleteToken?.call(identifier, token) ?? false;

  @override
  FutureOr<void> delete(String identifier) => onDelete?.call(identifier);
}

class _CallbackEmailChangeTokenStore
    implements
        AuthEmailChangeTokenStore,
        AuthEmailChangeTokenConditionalDeleteStore {
  const _CallbackEmailChangeTokenStore({
    this.onSave,
    this.onConsume,
    this.onDeleteTokenForUser,
    this.onDeleteForUser,
  });

  final FutureOr<void> Function(AuthEmailChangeToken token)? onSave;
  final FutureOr<AuthEmailChangeToken?> Function(String token)? onConsume;
  final FutureOr<bool> Function(String userId, String token)?
  onDeleteTokenForUser;
  final FutureOr<void> Function(String userId)? onDeleteForUser;

  @override
  FutureOr<void> save(AuthEmailChangeToken token) => onSave?.call(token);

  @override
  FutureOr<AuthEmailChangeToken?> consume(String token) =>
      onConsume?.call(token);

  @override
  FutureOr<bool> deleteTokenForUser(String userId, String token) =>
      onDeleteTokenForUser?.call(userId, token) ?? false;

  @override
  FutureOr<void> deleteForUser(String userId) => onDeleteForUser?.call(userId);
}
