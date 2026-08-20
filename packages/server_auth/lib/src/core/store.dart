import 'dart:async';

import 'account_policy.dart';
import 'email_change_token_store.dart';
import 'models.dart';
import 'oauth_challenge_store.dart';
import 'password_reset_token_store.dart';
import 'verification_token_store.dart';
import 'jwt_version_store.dart';
import 'webauthn_store.dart';
import 'users.dart';
import 'device_authorization_store.dart';
import 'email_otp_store.dart';

/// Result of an atomic user create-or-find operation.
class AuthUserCreateResult {
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
  FutureOr<AuthUser?> findById(String id);

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

  /// Removes one external identity only when it belongs to [userId].
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
  FutureOr<void> save(AuthEmailChangeToken token);

  /// Atomically consumes an active token and returns its user/email binding.
  FutureOr<AuthEmailChangeToken?> consume(String token);

  FutureOr<void> deleteForUser(String userId);
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
/// application must provide one store to [AuthOptions]; there is no implicit
/// adapter, fallback store, or untyped callback surface.
abstract interface class AuthStore {
  AuthUserStore get users;

  AuthCredentialStore get credentials;

  AuthAccountStore get accounts;

  AuthSessionStore get sessions;

  AuthOAuthChallengeStore get oauthChallenges;

  AuthPasswordResetTokenStore get passwordResetTokens;

  AuthJwtVersionStore get jwtVersions;

  AuthVerificationTokenStore get verificationTokens;

  AuthEmailChangeTokenStore get emailChangeTokens;

  AuthWebAuthnChallengeStore get webAuthnChallenges;

  AuthWebAuthnAuthenticatorStore get webAuthnAuthenticators;

  AuthDeviceAuthorizationStore get deviceAuthorizations;

  AuthEmailOtpStore get emailOtps;
}

/// Transactional boundary for confirmation-token account deletion.
///
/// Durable adapters must consume the token and remove the user-owned core data
/// in one transaction. Returning `false` leaves both the token and account
/// unchanged so callers can safely retry.
abstract interface class AuthAccountDeletionStore {
  FutureOr<bool> confirmAndDeleteUser({
    required String userId,
    required String token,
    DateTime? now,
  });
}

/// Optional data-plane operations required by the Admin plugin.
///
/// Production adapters implement these operations transactionally. Keeping
/// them separate from [AuthStore] preserves source compatibility for stores
/// that do not opt into administrative APIs.
abstract interface class AuthAdminStoreCapabilities {
  FutureOr<List<AuthUser>> listUsersForAdministration();

  FutureOr<AuthUser?> updateUserForAdministration(AuthUser user);

  FutureOr<AuthPasswordCredential?> findCredentialForUser(String userId);

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

/// In-memory store for tests, examples, and local development.
///
/// This implementation deliberately keeps password hashes outside [AuthUser]
/// attributes. It is not intended for production persistence; production
/// applications should provide an implementation backed by their database and
/// password-hashing policy.
class InMemoryAuthStore
    implements
        AuthStore,
        AuthAdminStoreCapabilities,
        AuthAccountDeletionStore,
        AuthAccountStateStore {
  InMemoryAuthStore()
    : users = _InMemoryUserStore(),
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
      _accountStates = InMemoryAuthAccountStateStore() {
    (credentials as _InMemoryCredentialStore).users = users;
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

  final InMemoryAuthAccountStateStore _accountStates;

  @override
  Future<AuthAccountState?> find(String userId) => _accountStates.find(userId);

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
  Future<bool> confirmAndDeleteUser({
    required String userId,
    required String token,
    DateTime? now,
  }) async {
    final id = userId.trim();
    if (id.isEmpty || token.trim().isEmpty) return false;
    final user = await users.findById(id);
    if (user == null) return false;
    final consumed = await verificationTokens.consume(
      'account_deletion:$id',
      token,
    );
    if (consumed == null) return false;

    // All following mutations are in-memory and non-failing. Durable stores
    // implement this interface with their database transaction primitive.
    await _credentials.deleteForUser(id);
    await _accounts.deleteForUser(id);
    _sessions.deleteForUser(id);
    await passwordResetTokens.deleteForUser(id);
    await emailChangeTokens.deleteForUser(id);
    await deviceAuthorizations.deleteForUser(id);
    if (user.email != null) {
      await emailOtps.deleteForEmail(user.email!);
      await verificationTokens.delete(user.email!);
    }
    await jwtVersions.rotate(id);
    return _users.delete(id);
  }

  @override
  Future<List<AuthUser>> listUsersForAdministration() async =>
      List<AuthUser>.unmodifiable(
        (_users).values.toList()..sort((a, b) => a.id.compareTo(b.id)),
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
  Future<bool> deleteUserForAdministration(String userId) async {
    final id = userId.trim();
    final user = await users.findById(id);
    if (user == null) return false;
    _credentials.deleteForUser(id);
    _accounts.deleteForUser(id);
    _sessions.deleteForUser(id);
    await passwordResetTokens.deleteForUser(id);
    await verificationTokens.delete(id);
    await emailChangeTokens.deleteForUser(id);
    await deviceAuthorizations.deleteForUser(id);
    if (user.email != null) await emailOtps.deleteForEmail(user.email!);
    if (user.email != null) await verificationTokens.delete(user.email!);
    _users.delete(id);
    return true;
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
    if (user.email != null) await verificationTokens.delete(user.email!);
    _users.replaceWithTombstone(id, timestamp);
    return true;
  }

  @override
  Future<bool> purgeTombstonedUserForAdministration(String userId) async {
    final id = userId.trim();
    final user = await users.findById(id);
    if (user == null || !authUserIsDisabled(user)) return false;
    _users.delete(id);
    return true;
  }
}

/// Callback-backed typed store useful for focused unit tests.
///
/// Each callback belongs to one typed domain store. This is intentionally a
/// store implementation rather than an adapter compatibility layer.
class CallbackAuthStore implements AuthStore {
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
    FutureOr<void> Function(String userId)? onDeletePasswordResetTokens,
    AuthPasswordResetTokenStore? passwordResetTokens,
    FutureOr<int> Function(String userId)? onCurrentJwtVersion,
    FutureOr<int> Function(String userId)? onRotateJwtVersion,
    AuthJwtVersionStore? jwtVersions,
    FutureOr<void> Function(AuthVerificationToken token)?
    onSaveVerificationToken,
    FutureOr<AuthVerificationToken?> Function(String identifier, String token)?
    onConsumeVerificationToken,
    FutureOr<void> Function(String identifier)? onDeleteVerificationTokens,
    AuthVerificationTokenStore? verificationTokens,
    FutureOr<void> Function(AuthEmailChangeToken token)? onSaveEmailChangeToken,
    FutureOr<AuthEmailChangeToken?> Function(String token)?
    onConsumeEmailChangeToken,
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
             onDelete: onDeleteVerificationTokens,
           ),
       emailChangeTokens =
           emailChangeTokens ??
           _CallbackEmailChangeTokenStore(
             onSave: onSaveEmailChangeToken,
             onConsume: onConsumeEmailChangeToken,
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
    this.onDeleteForUser,
  });

  final FutureOr<void> Function(AuthPasswordResetToken token)? onSave;
  final FutureOr<AuthPasswordResetToken?> Function(String token)? onConsume;
  final FutureOr<void> Function(String userId)? onDeleteForUser;

  @override
  FutureOr<void> save(AuthPasswordResetToken token) => onSave?.call(token);

  @override
  FutureOr<AuthPasswordResetToken?> consume(String token) =>
      onConsume?.call(token);

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

  Iterable<AuthUser> get values => _usersById.values;
  bool contains(String id) => _usersById.containsKey(id);

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

  Iterable<AuthPasswordCredential> get values => _credentialsById.values;

  void upsertForAdministration(AuthPasswordCredential credential) {
    final previous = _credentialsById[credential.id];
    if (previous != null && previous.identifier != credential.identifier) {
      _credentialIdsByIdentifier.remove(previous.identifier);
    }
    final conflictingId = _credentialIdsByIdentifier[credential.identifier];
    if (conflictingId != null && conflictingId != credential.id) {
      throw StateError('Auth user email already exists');
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

  @override
  Future<AuthUser?> register(
    AuthUser user,
    AuthPasswordCredential credential,
  ) async {
    if (credential.id.trim().isEmpty ||
        credential.userId.trim().isEmpty ||
        credential.identifier.trim().isEmpty ||
        credential.passwordHash.isEmpty ||
        credential.userId != user.id ||
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
    try {
      final userStore = users;
      if (userStore == null) {
        return null;
      }
      final existing = await userStore.findById(user.id);
      if (existing != null ||
          _credentialIdsByIdentifier.containsKey(credential.identifier) ||
          _credentialsById.containsKey(credential.id)) {
        return null;
      }
      final created = await userStore.create(user);
      _credentialsById[credential.id] = credential;
      _credentialIdsByIdentifier[credential.identifier] = credential.id;
      return created;
    } finally {
      _inFlightIdentifiers.remove(credential.identifier);
      _inFlightCredentialIds.remove(credential.id);
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
    if (account?.userId != userId.trim()) return false;
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
      return await Future.sync(() => callback(user));
    }
    final AuthUser? existing = await Future.sync(
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

class _CallbackVerificationTokenStore implements AuthVerificationTokenStore {
  const _CallbackVerificationTokenStore({
    this.onSave,
    this.onConsume,
    this.onDelete,
  });

  final FutureOr<void> Function(AuthVerificationToken token)? onSave;
  final FutureOr<AuthVerificationToken?> Function(
    String identifier,
    String token,
  )?
  onConsume;
  final FutureOr<void> Function(String identifier)? onDelete;

  @override
  FutureOr<void> save(AuthVerificationToken token) => onSave?.call(token);

  @override
  FutureOr<AuthVerificationToken?> consume(String identifier, String token) =>
      onConsume?.call(identifier, token);

  @override
  FutureOr<void> delete(String identifier) => onDelete?.call(identifier);
}

class _CallbackEmailChangeTokenStore implements AuthEmailChangeTokenStore {
  const _CallbackEmailChangeTokenStore({
    this.onSave,
    this.onConsume,
    this.onDeleteForUser,
  });

  final FutureOr<void> Function(AuthEmailChangeToken token)? onSave;
  final FutureOr<AuthEmailChangeToken?> Function(String token)? onConsume;
  final FutureOr<void> Function(String userId)? onDeleteForUser;

  @override
  FutureOr<void> save(AuthEmailChangeToken token) => onSave?.call(token);

  @override
  FutureOr<AuthEmailChangeToken?> consume(String token) =>
      onConsume?.call(token);

  @override
  FutureOr<void> deleteForUser(String userId) => onDeleteForUser?.call(userId);
}
