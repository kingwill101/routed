import 'dart:async';
import 'dart:convert';

import 'package:routed_node/cloudflare.dart';
import 'package:server_auth/server_auth.dart';

import 'cloudflare_d1_auth_schema.dart';

/// A durable [AuthStore] backed by a Cloudflare D1 binding.
///
/// Construct the adapter from the host-neutral binding exported by
/// `package:routed_node/cloudflare.dart`; callers never handle JavaScript or
/// `package:web` values.
final class CloudflareD1AuthStore
    implements
        AuthStore,
        AuthUsernameStore,
        AuthUserDeletionCoordinatorHost,
        AuthOAuthAccountMutationStore,
        AuthAuthenticationMethodTopologyStore {
  CloudflareD1AuthStore(
    CloudflareD1Database database, {
    this.schema = const CloudflareD1AuthSchema(),
    this.scimReplayTtl = const Duration(days: 1),
    DateTime Function()? clock,
  }) : _database = database,
       _clock = clock ?? DateTime.now {
    final sql = _D1(database);
    _sql = sql;
    users = _D1Users(sql, schema);
    credentials = _D1Credentials(sql, schema);
    accounts = _D1Accounts(sql, schema);
    sessions = _D1Sessions(sql, schema, _clock);
    oauthChallenges = _D1OAuthChallenges(sql, schema, _clock);
    passwordResetTokens = _D1PasswordResetTokens(sql, schema, _clock);
    jwtVersions = _D1JwtVersions(sql, schema);
    verificationTokens = _D1VerificationTokens(sql, schema, _clock);
    emailChangeTokens = _D1EmailChangeTokens(sql, schema, _clock);
    deviceAuthorizations = _D1DeviceAuthorizations(sql, schema, _clock);
    emailOtps = _D1EmailOtps(sql, schema, _clock);
    final deletionCoordinator = CloudflareD1UserDeletionCoordinator._(
      database: database,
      sql: sql,
      schema: schema,
      clock: _clock,
    );
    _deletionCoordinator = deletionCoordinator;
    scimConnectionStore = CloudflareD1ScimConnectionStore._(
      sql,
      schema,
      deletionCoordinator.domain,
      replayTtl: scimReplayTtl,
    );
    oauthClientStore = CloudflareD1OAuthClientStore._(
      sql,
      schema,
      deletionCoordinator.domain,
    );
    oauthAuthorizationCodeStore = CloudflareD1OAuthAuthorizationCodeStore._(
      sql,
      schema,
      deletionCoordinator.domain,
      _clock,
    );
    oauthAccessTokenStore = CloudflareD1OAuthAccessTokenStore._(
      sql,
      schema,
      deletionCoordinator.domain,
      _clock,
    );
    oauthAuthorizationCodeExchangeStore =
        CloudflareD1OAuthAuthorizationCodeExchangeStore._(
          sql,
          schema,
          deletionCoordinator.domain,
          oauthAuthorizationCodeStore,
          oauthAccessTokenStore,
        );
  }

  /// Creates an adapter and applies all pending typed migrations.
  static Future<CloudflareD1AuthStore> open(
    CloudflareD1Database database, {
    CloudflareD1AuthSchema schema = const CloudflareD1AuthSchema(),
    Duration scimReplayTtl = const Duration(days: 1),
    DateTime Function()? clock,
  }) async {
    await schema.migrate(database);
    return CloudflareD1AuthStore(
      database,
      schema: schema,
      scimReplayTtl: scimReplayTtl,
      clock: clock,
    );
  }

  final CloudflareD1Database _database;
  late final _D1 _sql;
  final DateTime Function() _clock;
  final CloudflareD1AuthSchema schema;
  final Duration scimReplayTtl;
  late final CloudflareD1UserDeletionCoordinator _deletionCoordinator;
  bool _authenticationMethodTopologyBound = false;
  bool _authenticationMethodInventoryAuthoritative = false;

  @override
  AuthUserDeletionCoordinator get userDeletionCoordinator =>
      _deletionCoordinator;

  @override
  void bindUserDeletionPlanContributors(
    Iterable<AuthUserDeletionPlanContributor> contributors,
  ) => _deletionCoordinator.bind(contributors);

  @override
  void bindAuthenticationMethodInventory(
    Iterable<AuthAuthenticationMethodInventoryContributor> contributors,
  ) {
    if (_authenticationMethodTopologyBound) {
      throw StateError('Authentication method inventory is already bound.');
    }
    var authoritative = true;
    for (final contributor in contributors) {
      final binding = switch (contributor) {
        AuthAuthenticationMethodInventoryBinding binding => binding,
        _ => null,
      };
      if (binding == null) {
        authoritative = false;
        continue;
      }
      final allowedKinds = identical(binding.authenticationMethodStore, this)
          ? const {AuthAuthenticationMethodKind.username}
          : identical(binding.authenticationMethodStore, users)
          ? const {AuthAuthenticationMethodKind.emailLink}
          : identical(binding.authenticationMethodStore, credentials)
          ? const {
              AuthAuthenticationMethodKind.password,
              AuthAuthenticationMethodKind.username,
            }
          : identical(binding.authenticationMethodStore, accounts)
          ? const {AuthAuthenticationMethodKind.oauthProvider}
          : identical(binding.authenticationMethodStore, emailOtps)
          ? const {AuthAuthenticationMethodKind.emailOtp}
          : const <AuthAuthenticationMethodKind>{};
      if (binding.authenticationMethodKinds.isEmpty ||
          binding.authenticationMethodKinds.any(
            (kind) => !allowedKinds.contains(kind),
          )) {
        authoritative = false;
      }
    }
    _authenticationMethodInventoryAuthoritative = authoritative;
    _authenticationMethodTopologyBound = true;
  }

  @override
  Future<AuthAuthenticationMethodMutationResult> unlinkOAuthAccountIfSafe({
    required String userId,
    required String providerId,
    required String providerAccountId,
    required AuthAuthenticationMethodInventoryLoader loadInventory,
  }) async {
    if (!_authenticationMethodTopologyBound ||
        !_authenticationMethodInventoryAuthoritative) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final snapshot = await loadInventory();
    if (!snapshot.isComplete) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final target = AuthAuthenticationMethod.oauthProvider(
      providerId: providerId,
      providerAccountId: providerAccountId,
    );
    if (!snapshot.methods.contains(target)) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    final fallbacks = snapshot.methods
        .where((method) => method.canAuthenticate && method != target)
        .toList(growable: false);
    if (fallbacks.isEmpty) {
      return AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
    }

    var hasCredentialFallback = false;
    var hasEmailFallback = false;
    final oauthProviderIds = <String>{};
    for (final method in fallbacks) {
      switch (method.kind) {
        case AuthAuthenticationMethodKind.password:
        case AuthAuthenticationMethodKind.username:
          hasCredentialFallback = true;
        case AuthAuthenticationMethodKind.oauthProvider:
          final id = method.providerId;
          if (id == null || method.providerAccountId == null) {
            return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
          }
          oauthProviderIds.add(id);
        case AuthAuthenticationMethodKind.emailOtp:
        case AuthAuthenticationMethodKind.emailLink:
          hasEmailFallback = true;
        case AuthAuthenticationMethodKind.passkey:
        case AuthAuthenticationMethodKind.phone:
        case AuthAuthenticationMethodKind.apiKey:
        case AuthAuthenticationMethodKind.plugin:
          return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
      }
    }

    final clauses = <String>[];
    final fallbackValues = <Object?>[];
    if (hasCredentialFallback) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('credentials')}
           WHERE user_id = ? AND enabled = 1)''');
      fallbackValues.add(userId);
    }
    if (oauthProviderIds.isNotEmpty) {
      final providerParameters = List.filled(
        oauthProviderIds.length,
        '?',
      ).join(', ');
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('accounts')}
           WHERE user_id = ?
             AND NOT (provider_id = ? AND provider_account_id = ?)
             AND provider_id IN ($providerParameters))''');
      fallbackValues.addAll([
        userId,
        providerId,
        providerAccountId,
        ...oauthProviderIds,
      ]);
    }
    if (hasEmailFallback) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('users')}
           WHERE id = ? AND email IS NOT NULL AND email <> ''
             AND COALESCE(json_extract(payload, '\$.attributes.disabled'), 0) <> 1
             AND COALESCE(json_extract(payload, '\$.attributes.accountDisabled'), 0) <> 1
             AND json_extract(payload, '\$.attributes.deletedAt') IS NULL)''');
      fallbackValues.add(userId);
    }
    if (clauses.isEmpty) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }

    final result = await _sql.run(
      '''DELETE FROM ${schema.table('accounts')}
         WHERE user_id = ? AND provider_id = ? AND provider_account_id = ?
           AND (${clauses.join(' OR ')})''',
      [userId, providerId, providerAccountId, ...fallbackValues],
    );
    if ((result.meta?.changes ?? 0) == 1) {
      return AuthAuthenticationMethodMutationResult.mutated;
    }
    final existing = await accounts.find(providerId, providerAccountId);
    return existing?.userId == userId
        ? AuthAuthenticationMethodMutationResult.lastAuthenticationMethod
        : AuthAuthenticationMethodMutationResult.notFound;
  }

  _D1Credentials get _usernameCredentials => credentials as _D1Credentials;
  String get _usernameMutationGuards =>
      schema.table('username_mutation_guards');

  String _usernameMutationKey(String operation, Iterable<String> values) =>
      '$operation:${hashOpaqueToken(values.join('\u0000'))}';

  @override
  Future<AuthPasswordCredential?> findByUsername(String username) =>
      _usernameCredentials.findByUsername(username);

  @override
  Future<AuthPasswordCredential?> findUsernameForUser(String userId) =>
      _usernameCredentials.findUsernameForUser(userId);

  @override
  Future<AuthUsernameMutationResult> registerUsername(
    AuthUsernameRegistrationCommand command,
  ) async {
    final user = command.user;
    final credential = command.credential;
    validateAuthUserForPersistence(user);
    final userId = user.id.trim();
    final email = _nullableEmail(user.email);
    final usersTable = schema.table('users');
    final credentialsTable = schema.table('credentials');
    final deletionReceipts = schema.table('deletion_receipts');
    final operationKey = _usernameMutationKey('register', [
      userId,
      credential.id,
      credential.identifier,
    ]);
    try {
      final results = await _sql.batch([
        _database
            .prepare('''INSERT INTO $_usernameMutationGuards
                 (operation_key, operation, user_id, credential_id,
                  expected_username, target_username, created_at)
                 SELECT ?, 'register', ?, ?, NULL, ?, ?
                 WHERE NOT EXISTS (SELECT 1 FROM $usersTable WHERE id = ?)
                   AND (? IS NULL OR NOT EXISTS (
                     SELECT 1 FROM $usersTable WHERE email = ?
                   ))
                   AND NOT EXISTS (
                     SELECT 1 FROM $credentialsTable WHERE id = ?
                   )
                   AND NOT EXISTS (
                     SELECT 1 FROM $credentialsTable WHERE identifier = ?
                   )
                   AND NOT EXISTS (
                     SELECT 1 FROM $deletionReceipts WHERE user_id_hash = ?
                   )''')
            .bind([
              operationKey,
              userId,
              credential.id,
              credential.identifier,
              _date(_clock()),
              userId,
              email,
              email,
              credential.id,
              credential.identifier,
              hashOpaqueToken(userId),
            ]),
        _database
            .prepare('''INSERT INTO $usersTable (id, email, payload)
                 SELECT ?, ?, ?
                 WHERE EXISTS (
                   SELECT 1 FROM $_usernameMutationGuards
                   WHERE operation_key = ?
                 )''')
            .bind([userId, email, _encodeUser(user), operationKey]),
        _database
            .prepare('''INSERT INTO $credentialsTable
                 (id, user_id, identifier, password_hash, created_at, updated_at, enabled)
                 SELECT ?, ?, ?, ?, ?, ?, ?
                 WHERE EXISTS (
                   SELECT 1 FROM $_usernameMutationGuards
                   WHERE operation_key = ?
                 )''')
            .bind([..._credentialValues(credential), operationKey]),
        _database
            .prepare(
              'DELETE FROM $_usernameMutationGuards WHERE operation_key = ?',
            )
            .bind([operationKey]),
      ]);
      if ((results.first.meta?.changes ?? 0) == 1 &&
          (results[1].meta?.changes ?? 0) == 1 &&
          (results[2].meta?.changes ?? 0) == 1 &&
          (results.last.meta?.changes ?? 0) == 1) {
        return AuthUsernameMutationResult(
          status: AuthUsernameMutationStatus.created,
          user: user,
          credential: credential,
        );
      }
    } catch (_) {
      if (!await _hasUsernameRegistrationConflict(command)) rethrow;
    }
    return const AuthUsernameMutationResult(
      status: AuthUsernameMutationStatus.conflict,
    );
  }

  Future<bool> _hasUsernameRegistrationConflict(
    AuthUsernameRegistrationCommand command,
  ) async {
    final user = command.user;
    final credential = command.credential;
    return await users.findById(user.id) != null ||
        (user.email != null && await users.findByEmail(user.email!) != null) ||
        await _usernameCredentials.findById(credential.id) != null ||
        await findByUsername(credential.identifier) != null;
  }

  @override
  Future<AuthUsernameMutationResult> changeUsername(
    AuthUsernameChangeCommand command,
  ) async {
    final existing = await _readUsernameChangeResult(
      command,
      AuthUsernameMutationStatus.unchanged,
    );
    if (existing.succeeded) return existing;
    final usersTable = schema.table('users');
    final credentialsTable = schema.table('credentials');
    final operationKey = _usernameMutationKey('change', [
      command.userId,
      command.credentialId,
      command.expectedUsername,
      command.username,
    ]);
    const available = '''
      COALESCE(json_extract(payload, '\$.attributes.disabled'), 0) <> 1
      AND COALESCE(json_extract(payload, '\$.attributes.accountDisabled'), 0) <> 1
      AND json_extract(payload, '\$.attributes.deletedAt') IS NULL''';
    try {
      final results = await _sql.batch([
        _database
            .prepare('''INSERT INTO $_usernameMutationGuards
                 (operation_key, operation, user_id, credential_id,
                  expected_username, target_username, created_at)
                 SELECT ?, 'change', ?, ?, ?, ?, ?
                 WHERE EXISTS (
                   SELECT 1 FROM $usersTable
                   WHERE id = ? AND $available
                     AND json_extract(payload, '\$.attributes.username') = ?
                 )
                   AND EXISTS (
                     SELECT 1 FROM $credentialsTable
                     WHERE id = ? AND user_id = ? AND identifier = ?
                       AND instr(identifier, '@') = 0
                   )
                   AND NOT EXISTS (
                     SELECT 1 FROM $credentialsTable
                     WHERE identifier = ? AND id <> ?
                   )''')
            .bind([
              operationKey,
              command.userId,
              command.credentialId,
              command.expectedUsername,
              command.username,
              _date(_clock()),
              command.userId,
              command.expectedUsername,
              command.credentialId,
              command.userId,
              command.expectedUsername,
              command.username,
              command.credentialId,
            ]),
        _database
            .prepare('''UPDATE $credentialsTable
                 SET identifier = ?, updated_at = ?
                 WHERE id = ? AND user_id = ? AND identifier = ?
                   AND EXISTS (
                     SELECT 1 FROM $_usernameMutationGuards
                     WHERE operation_key = ?
                   )''')
            .bind([
              command.username,
              _date(command.updatedAt),
              command.credentialId,
              command.userId,
              command.expectedUsername,
              operationKey,
            ]),
        _database
            .prepare('''UPDATE $usersTable
                 SET payload = json_set(
                   payload,
                   '\$.attributes.username', ?,
                   '\$.name', CASE
                     WHEN json_extract(payload, '\$.name') = ? THEN ?
                     ELSE json_extract(payload, '\$.name')
                   END
                 )
                 WHERE id = ? AND $available
                   AND json_extract(payload, '\$.attributes.username') = ?
                   AND EXISTS (
                     SELECT 1 FROM $_usernameMutationGuards
                     WHERE operation_key = ?
                   )''')
            .bind([
              command.username,
              command.expectedUsername,
              command.username,
              command.userId,
              command.expectedUsername,
              operationKey,
            ]),
        _database
            .prepare(
              'DELETE FROM $_usernameMutationGuards WHERE operation_key = ?',
            )
            .bind([operationKey]),
      ]);
      if ((results.first.meta?.changes ?? 0) == 1 &&
          (results[1].meta?.changes ?? 0) == 1 &&
          (results[2].meta?.changes ?? 0) == 1 &&
          (results.last.meta?.changes ?? 0) == 1) {
        return await _readUsernameChangeResult(
          command,
          AuthUsernameMutationStatus.changed,
        );
      }
    } catch (_) {
      final replay = await _readUsernameChangeResult(
        command,
        AuthUsernameMutationStatus.unchanged,
      );
      if (replay.succeeded) return replay;
      if (await findByUsername(command.username) == null) rethrow;
    }
    final replay = await _readUsernameChangeResult(
      command,
      AuthUsernameMutationStatus.unchanged,
    );
    if (replay.succeeded) return replay;
    final user = await users.findById(command.userId);
    if (user == null) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.notFound,
      );
    }
    if (authUserIsDisabled(user)) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.userUnavailable,
      );
    }
    return const AuthUsernameMutationResult(
      status: AuthUsernameMutationStatus.conflict,
    );
  }

  Future<AuthUsernameMutationResult> _readUsernameChangeResult(
    AuthUsernameChangeCommand command,
    AuthUsernameMutationStatus status,
  ) async {
    final user = await users.findById(command.userId);
    final credential = await _usernameCredentials.findById(
      command.credentialId,
    );
    if (user?.attributes['username'] != command.username ||
        credential?.userId != command.userId ||
        credential?.identifier != command.username) {
      return const AuthUsernameMutationResult(
        status: AuthUsernameMutationStatus.conflict,
      );
    }
    return AuthUsernameMutationResult(
      status: status,
      user: user,
      credential: credential,
    );
  }

  @override
  Future<AuthAuthenticationMethodMutationResult> removeUsernameIfSafe(
    AuthUsernameRemovalCommand command,
  ) async {
    final userId = command.userId;
    final credentialId = command.credentialId;
    if (!_authenticationMethodTopologyBound ||
        !_authenticationMethodInventoryAuthoritative) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final snapshot = await command.loadInventory();
    if (!snapshot.isComplete) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final target = AuthAuthenticationMethod.username(credentialId);
    if (!snapshot.methods.contains(target)) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    final fallbacks = snapshot.methods
        .where((method) => method.canAuthenticate && method != target)
        .toList(growable: false);
    if (fallbacks.isEmpty) {
      return AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
    }

    var hasCredentialFallback = false;
    var hasEmailFallback = false;
    final oauthProviderIds = <String>{};
    for (final method in fallbacks) {
      switch (method.kind) {
        case AuthAuthenticationMethodKind.password:
        case AuthAuthenticationMethodKind.username:
          hasCredentialFallback = true;
        case AuthAuthenticationMethodKind.oauthProvider:
          final id = method.providerId;
          if (id == null || method.providerAccountId == null) {
            return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
          }
          oauthProviderIds.add(id);
        case AuthAuthenticationMethodKind.emailOtp:
        case AuthAuthenticationMethodKind.emailLink:
          hasEmailFallback = true;
        case AuthAuthenticationMethodKind.passkey:
        case AuthAuthenticationMethodKind.phone:
        case AuthAuthenticationMethodKind.apiKey:
        case AuthAuthenticationMethodKind.plugin:
          return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
      }
    }

    final clauses = <String>[];
    final fallbackValues = <Object?>[];
    if (hasCredentialFallback) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('credentials')}
           WHERE user_id = ? AND id <> ? AND enabled = 1)''');
      fallbackValues.addAll([userId, credentialId]);
    }
    if (oauthProviderIds.isNotEmpty) {
      final parameters = List.filled(oauthProviderIds.length, '?').join(', ');
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('accounts')}
           WHERE user_id = ? AND provider_id IN ($parameters))''');
      fallbackValues.addAll([userId, ...oauthProviderIds]);
    }
    if (hasEmailFallback) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('users')}
           WHERE id = ? AND email IS NOT NULL AND email <> '')''');
      fallbackValues.add(userId);
    }
    if (clauses.isEmpty) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }

    final credential = await _usernameCredentials.findById(credentialId);
    if (credential == null || credential.userId != userId) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    final usersTable = schema.table('users');
    final credentialsTable = schema.table('credentials');
    final operationKey = _usernameMutationKey('remove', [
      userId,
      credentialId,
      credential.identifier,
    ]);
    const available = '''
      COALESCE(json_extract(payload, '\$.attributes.disabled'), 0) <> 1
      AND COALESCE(json_extract(payload, '\$.attributes.accountDisabled'), 0) <> 1
      AND json_extract(payload, '\$.attributes.deletedAt') IS NULL''';
    final guard = clauses.join(' OR ');
    final results = await _sql.batch([
      _database
          .prepare('''INSERT INTO $_usernameMutationGuards
               (operation_key, operation, user_id, credential_id,
                expected_username, target_username, created_at)
               SELECT ?, 'remove', ?, ?, ?, NULL, ?
               WHERE EXISTS (
                 SELECT 1 FROM $usersTable
                 WHERE id = ? AND $available
                   AND json_extract(payload, '\$.attributes.username') = ?
               )
                 AND EXISTS (
                   SELECT 1 FROM $credentialsTable
                   WHERE id = ? AND user_id = ? AND identifier = ?
                     AND instr(identifier, '@') = 0
                 )
                 AND ($guard)''')
          .bind([
            operationKey,
            userId,
            credentialId,
            credential.identifier,
            _date(_clock()),
            userId,
            credential.identifier,
            credentialId,
            userId,
            credential.identifier,
            ...fallbackValues,
          ]),
      _database
          .prepare('''UPDATE $usersTable
               SET payload = json_set(
                 json_remove(payload, '\$.attributes.username'),
                 '\$.name', CASE
                   WHEN json_extract(payload, '\$.name') = ? THEN NULL
                   ELSE json_extract(payload, '\$.name')
                 END
               )
               WHERE id = ?
                 AND EXISTS (
                   SELECT 1 FROM $_usernameMutationGuards
                   WHERE operation_key = ?
                 )''')
          .bind([credential.identifier, userId, operationKey]),
      _database
          .prepare('''DELETE FROM $credentialsTable
               WHERE id = ? AND user_id = ?
                 AND EXISTS (
                   SELECT 1 FROM $_usernameMutationGuards
                   WHERE operation_key = ?
                 )''')
          .bind([credentialId, userId, operationKey]),
      _database
          .prepare(
            'DELETE FROM $_usernameMutationGuards WHERE operation_key = ?',
          )
          .bind([operationKey]),
    ]);
    if ((results.first.meta?.changes ?? 0) == 1 &&
        (results[1].meta?.changes ?? 0) == 1 &&
        (results[2].meta?.changes ?? 0) == 1 &&
        (results.last.meta?.changes ?? 0) == 1) {
      return AuthAuthenticationMethodMutationResult.mutated;
    }
    final existing = await _usernameCredentials.findById(credentialId);
    if (existing == null) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    final user = await users.findById(userId);
    return user == null || authUserIsDisabled(user)
        ? AuthAuthenticationMethodMutationResult.atomicityUnavailable
        : AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
  }

  @override
  late final AuthUserStore users;
  @override
  late final AuthCredentialStore credentials;
  @override
  late final AuthAccountStore accounts;
  @override
  late final AuthSessionStore sessions;
  @override
  late final AuthOAuthChallengeStore oauthChallenges;
  @override
  late final AuthPasswordResetTokenStore passwordResetTokens;
  @override
  late final AuthJwtVersionStore jwtVersions;
  @override
  late final AuthVerificationTokenStore verificationTokens;
  @override
  late final AuthEmailChangeTokenStore emailChangeTokens;
  @override
  late final AuthDeviceAuthorizationStore deviceAuthorizations;
  @override
  late final AuthEmailOtpStore emailOtps;

  /// Prefix-isolated D1 OAuth provider client registry.
  late final CloudflareD1OAuthClientStore oauthClientStore;

  /// Digest-only D1 authorization-code store.
  late final CloudflareD1OAuthAuthorizationCodeStore
  oauthAuthorizationCodeStore;

  /// Digest-only D1 access/refresh-token store.
  late final CloudflareD1OAuthAccessTokenStore oauthAccessTokenStore;

  /// Authoritative D1 authorization-code exchange boundary.
  late final CloudflareD1OAuthAuthorizationCodeExchangeStore
  oauthAuthorizationCodeExchangeStore;

  /// Digest-only managed-SCIM connection persistence in this D1 domain.
  late final CloudflareD1ScimConnectionStore scimConnectionStore;

  /// Applies all pending schema migrations.
  Future<void> migrate() => schema.migrate(_database);
}

/// Exact D1 database and schema identity accepted by a deletion coordinator.
final class CloudflareD1UserDeletionDomain implements AuthUserDeletionDomain {
  CloudflareD1UserDeletionDomain._(this.database, this.schema);

  final CloudflareD1Database database;
  final CloudflareD1AuthSchema schema;
}

/// One immutable D1 mutation containing a mandatory coordinator guard.
///
/// [sql] must contain exactly one `{{guard}}` marker after all statement-local
/// placeholders. The coordinator replaces it with its token/user guard and
/// appends the guard parameters before preparing the batch.
final class CloudflareD1UserDeletionStatement {
  CloudflareD1UserDeletionStatement({
    required String sql,
    Iterable<Object?> parameters = const [],
  }) : sql = _validateGuardedSql(sql),
       parameters = List<Object?>.unmodifiable(parameters);

  final String sql;
  final List<Object?> parameters;
}

/// Immutable plugin-owned D1 deletion plan.
final class CloudflareD1UserDeletionPlan implements AuthUserDeletionPlan {
  CloudflareD1UserDeletionPlan({
    required this.domain,
    required String userId,
    required String namespace,
    required Iterable<CloudflareD1UserDeletionStatement> statements,
  }) : userId = _required(userId, 'userId'),
       namespace = _required(namespace, 'namespace').toLowerCase(),
       statements = List<CloudflareD1UserDeletionStatement>.unmodifiable(
         statements,
       );

  @override
  final CloudflareD1UserDeletionDomain domain;

  @override
  final String userId;

  @override
  final String namespace;

  final List<CloudflareD1UserDeletionStatement> statements;
}

/// D1-owned coordinator for atomic core and plugin user deletion.
///
/// The coordinator submits one `D1Database.batch`; Cloudflare documents a D1
/// batch as a SQL transaction whose complete sequence is rolled back when one
/// statement fails. The adapter always cleans its device-authorization and
/// email-OTP tables and retains a user-ID digest receipt. A removed external
/// plugin's private D1 tables remain undiscoverable unless its adapter keeps a
/// historical namespace inventory and contributes cleanup independently.
final class CloudflareD1UserDeletionCoordinator
    implements AuthUserDeletionCoordinator {
  CloudflareD1UserDeletionCoordinator._({
    required CloudflareD1Database database,
    required _D1 sql,
    required this.schema,
    required DateTime Function() clock,
  }) : domain = CloudflareD1UserDeletionDomain._(database, schema),
       _sql = sql,
       _clock = clock;

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() _clock;
  List<AuthUserDeletionPlanContributor> _contributors = const [];
  bool _bound = false;

  @override
  final CloudflareD1UserDeletionDomain domain;

  void bind(Iterable<AuthUserDeletionPlanContributor> contributors) {
    if (_bound) {
      throw StateError('Auth deletion contributors are already bound.');
    }
    final values = contributors.toList(growable: false);
    final namespaces = <String>{};
    for (final contributor in values) {
      final namespace = _required(
        contributor.userDataNamespace,
        'userDataNamespace',
      ).toLowerCase();
      if (namespace != contributor.userDataNamespace ||
          !namespaces.add(namespace)) {
        throw StateError(
          'Auth deletion contributor namespaces must be unique and normalized.',
        );
      }
    }
    _contributors = List<AuthUserDeletionPlanContributor>.unmodifiable(values);
    _bound = true;
  }

  @override
  Set<String> get requiredUserDeletionNamespaces => Set<String>.unmodifiable({
    for (final contributor in _contributors) contributor.userDataNamespace,
  });

  @override
  Future<List<AuthUserDeletionPlan>> plansForUser(AuthUser user) async =>
      _plansForBoundUser(user);

  Future<List<AuthUserDeletionPlan>> _plansForBoundUser(AuthUser user) async {
    _ensureBound();
    return List<AuthUserDeletionPlan>.unmodifiable([
      for (final contributor in _contributors)
        await contributor.createUserDeletionPlan(user),
    ]);
  }

  @override
  Future<bool> deleteUser(
    String userId, {
    Iterable<AuthUserDeletionPlan>? plans,
  }) => _delete(userId: userId, plans: plans, confirmationToken: null);

  @override
  Future<bool> confirmAndDeleteUser({
    required String userId,
    required String token,
    Iterable<AuthUserDeletionPlan>? plans,
    DateTime? now,
  }) {
    if (token.trim().isEmpty) return Future<bool>.value(false);
    return _delete(
      userId: userId,
      plans: plans,
      confirmationToken: token,
      now: now,
    );
  }

  Future<bool> _delete({
    required String userId,
    required Iterable<AuthUserDeletionPlan>? plans,
    required String? confirmationToken,
    DateTime? now,
  }) async {
    final id = _required(userId, 'userId');
    _ensureBound();
    final user = await _sql.first(
      'SELECT payload FROM ${schema.table('users')} WHERE id = ?',
      [id],
      _decodeUser,
    );
    if (user == null) return false;
    final validated = AuthUserDeletionPreflight.validate(
      userId: id,
      plans: plans ?? await plansForUser(user),
      requiredNamespaces: requiredUserDeletionNamespaces,
      domain: domain,
      isSupported: (plan) =>
          plan is CloudflareD1UserDeletionPlan ||
          plan is AuthNoopUserDeletionPlan,
    );

    final statements = <CloudflareD1UserDeletionStatement>[
      for (final plan in validated.whereType<CloudflareD1UserDeletionPlan>())
        ...plan.statements,
    ];
    final users = schema.table('users');
    final verification = schema.table('verification_tokens');
    final current = (now ?? _clock()).toUtc();
    final marker = secureRandomToken(length: 24);
    late final String guard;
    late final List<Object?> guardValues;
    final batch = <CloudflareD1PreparedStatement>[];

    if (confirmationToken == null) {
      guard = 'EXISTS (SELECT 1 FROM $users WHERE id = ?)';
      guardValues = [id];
    } else {
      final identifier = 'account_deletion:$id';
      final tokenHash = hashOpaqueToken(confirmationToken);
      final timestamp = _date(current);
      batch.add(
        _sql.database
            .prepare('''UPDATE $verification
                 SET metadata = json_set(metadata, '\$.__deletion_marker', ?)
                 WHERE identifier = ? AND token_hash = ? AND expires_at > ?
                   AND json_extract(metadata, '\$.__deletion_marker') IS NULL
                   AND EXISTS (SELECT 1 FROM $users WHERE id = ?)''')
            .bind([marker, identifier, tokenHash, timestamp, id]),
      );
      guard = '''EXISTS (SELECT 1 FROM $verification
          WHERE identifier = ? AND token_hash = ? AND expires_at > ?
            AND json_extract(metadata, '\$.__deletion_marker') = ?)''';
      guardValues = [identifier, tokenHash, timestamp, marker];
    }

    for (final statement in statements) {
      batch.add(_prepareGuarded(statement, guard, guardValues));
    }
    batch.addAll(_coreDeletionStatements(user, guard, guardValues, current));
    final userDeleteIndex = batch.length;
    batch.add(
      _sql.database.prepare('DELETE FROM $users WHERE id = ? AND $guard').bind([
        id,
        ...guardValues,
      ]),
    );
    if (confirmationToken != null) {
      batch.add(
        _sql.database
            .prepare('DELETE FROM $verification WHERE $guard')
            .bind(guardValues),
      );
    }
    final results = await _sql.batch(batch);
    return (results[userDeleteIndex].meta?.changes ?? 0) == 1;
  }

  void _ensureBound() {
    if (!_bound) {
      throw StateError('Auth deletion contributor topology is not bound.');
    }
  }

  Iterable<CloudflareD1PreparedStatement> _coreDeletionStatements(
    AuthUser user,
    String guard,
    List<Object?> guardValues,
    DateTime deletedAt,
  ) sync* {
    final id = user.id;
    for (final entry in <(String, String)>[
      (schema.table('credentials'), 'user_id'),
      (schema.table('accounts'), 'user_id'),
      (schema.table('sessions'), 'user_id'),
      (schema.table('password_reset_tokens'), 'user_id'),
      (schema.table('email_change_tokens'), 'user_id'),
      (schema.table('device_authorizations'), 'user_id'),
      (schema.table('oauth_authorization_codes'), 'user_id'),
      (schema.table('oauth_access_tokens'), 'user_id'),
    ]) {
      yield _sql.database
          .prepare('DELETE FROM ${entry.$1} WHERE ${entry.$2} = ? AND $guard')
          .bind([id, ...guardValues]);
    }
    final verification = schema.table('verification_tokens');
    yield _sql.database
        .prepare('DELETE FROM $verification WHERE identifier = ? AND $guard')
        .bind([id, ...guardValues]);
    if (user.email case final email?) {
      yield _sql.database
          .prepare('DELETE FROM $verification WHERE identifier = ? AND $guard')
          .bind([email, ...guardValues]);
      yield _sql.database
          .prepare(
            'DELETE FROM ${schema.table('email_otps')} '
            'WHERE email = ? AND $guard',
          )
          .bind([email, ...guardValues]);
    }
    final jwtVersions = schema.table('jwt_versions');
    yield _sql.database
        .prepare('''INSERT INTO $jwtVersions (user_id, version)
             SELECT ?, 1 WHERE $guard
             ON CONFLICT(user_id) DO UPDATE SET version = version + 1''')
        .bind([id, ...guardValues]);
    final deletionReceipts = schema.table('deletion_receipts');
    yield _sql.database
        .prepare('''INSERT INTO $deletionReceipts (user_id_hash, deleted_at)
             SELECT ?, ? WHERE $guard
             ON CONFLICT(user_id_hash) DO NOTHING''')
        .bind([hashOpaqueToken(id), _date(deletedAt), ...guardValues]);
  }

  CloudflareD1PreparedStatement _prepareGuarded(
    CloudflareD1UserDeletionStatement statement,
    String guard,
    List<Object?> guardValues,
  ) => _sql.database
      .prepare(statement.sql.replaceFirst('{{guard}}', guard))
      .bind([...statement.parameters, ...guardValues]);
}

String _validateGuardedSql(String value) {
  final sql = value.trim();
  final guardIndex = sql.indexOf('{{guard}}');
  if (sql.isEmpty ||
      guardIndex < 0 ||
      guardIndex != sql.lastIndexOf('{{guard}}') ||
      sql.lastIndexOf('?') > guardIndex ||
      sql.contains(';')) {
    throw ArgumentError.value(
      value,
      'sql',
      'must contain exactly one trailing {{guard}} marker after local '
          'placeholders and no semicolon',
    );
  }
  return sql;
}

final class _D1 {
  const _D1(this.database);
  final CloudflareD1Database database;

  Future<List<T>> all<T>(
    String query,
    Iterable<Object?> values,
    T Function(Map<String, Object?>) decode,
  ) async {
    final result = await database
        .prepare(query)
        .bind(values)
        .all<T>(decode: decode);
    _check(result);
    return result.results;
  }

  Future<T?> first<T>(
    String query,
    Iterable<Object?> values,
    T Function(Map<String, Object?>) decode,
  ) async {
    final result = await all(query, values, decode);
    return result.firstOrNull;
  }

  Future<CloudflareD1Result<Map<String, Object?>>> run(
    String query, [
    Iterable<Object?> values = const [],
  ]) async {
    final result = await database
        .prepare(query)
        .bind(values)
        .run<Map<String, Object?>>(decode: (row) => row);
    _check(result);
    return result;
  }

  Future<List<CloudflareD1Result<Object?>>> batch(
    Iterable<CloudflareD1PreparedStatement> statements,
  ) async {
    final results = await database.batch<Object?>(statements);
    for (final result in results) {
      _check(result);
    }
    return results;
  }

  Future<List<CloudflareD1Result<Map<String, Object?>>>> batchRows(
    Iterable<CloudflareD1PreparedStatement> statements,
  ) async {
    final results = await database.batch<Map<String, Object?>>(
      statements,
      decode: (row) => row,
    );
    for (final result in results) {
      _check(result);
    }
    return results;
  }

  static void _check(CloudflareD1Result<Object?> result) {
    if (!result.success) {
      throw StateError('D1 statement failed: ${result.error}');
    }
  }
}

/// Prefix-isolated OAuth client registry backed by Cloudflare D1.
final class CloudflareD1OAuthClientStore
    implements OAuthClientStore, OAuthProviderPersistenceTopology {
  CloudflareD1OAuthClientStore._(this._sql, this.schema, this.domain);

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final CloudflareD1UserDeletionDomain domain;

  String get table => schema.table('oauth_clients');

  @override
  AuthUserDeletionDomain get oauthProviderPersistenceDomain => domain;

  @override
  Future<OAuthClient?> findById(String clientId) => _sql.first(
    'SELECT * FROM $table WHERE client_id = ?',
    [clientId.trim()],
    _decodeOAuthClient,
  );

  @override
  Future<List<OAuthClient>> listAll() => _sql.all(
    'SELECT * FROM $table ORDER BY client_id',
    const [],
    _decodeOAuthClient,
  );

  @override
  Future<OAuthClient> create(OAuthClient client) async {
    _validateOAuthClient(client);
    try {
      await _sql.run(
        '''INSERT INTO $table
           (client_id, client_secret_hash, name, description, redirect_uris,
            grant_types, scopes, token_endpoint_auth_method, created_at,
            updated_at, enabled)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        _oauthClientValues(client),
      );
    } catch (_) {
      throw StateError('D1 OAuth client creation failed.');
    }
    return client;
  }

  @override
  Future<OAuthClient> update(OAuthClient client) async {
    _validateOAuthClient(client);
    final values = _oauthClientValues(client);
    final result = await _sql.run(
      '''UPDATE $table SET client_secret_hash = ?, name = ?, description = ?,
         redirect_uris = ?, grant_types = ?, scopes = ?,
         token_endpoint_auth_method = ?, created_at = ?, updated_at = ?,
         enabled = ? WHERE client_id = ?''',
      [...values.skip(1), values.first],
    );
    if (_oauthChanges(result) != 1) {
      throw StateError('D1 OAuth client was not found.');
    }
    return client;
  }

  @override
  Future<void> delete(String clientId) async {
    final id = clientId.trim();
    await _sql.batch([
      _sql.database
          .prepare(
            'DELETE FROM ${schema.table('oauth_authorization_codes')} '
            'WHERE client_id = ?',
          )
          .bind([id]),
      _sql.database
          .prepare(
            'DELETE FROM ${schema.table('oauth_access_tokens')} '
            'WHERE client_id = ?',
          )
          .bind([id]),
      _sql.database.prepare('DELETE FROM $table WHERE client_id = ?').bind([
        id,
      ]),
    ]);
  }

  @override
  Future<bool> validateSecret(String clientId, String secret) async {
    if (secret.isEmpty) return false;
    final client = await findById(clientId);
    if (client == null) return false;
    return constantTimeStringEquals(
      hashOpaqueToken(secret),
      client.clientSecretHash,
    );
  }
}

/// Digest-only OAuth authorization-code persistence backed by Cloudflare D1.
final class CloudflareD1OAuthAuthorizationCodeStore
    implements OAuthAuthorizationCodeStore {
  CloudflareD1OAuthAuthorizationCodeStore._(
    this._sql,
    this.schema,
    this.domain,
    this.clock,
  );

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final CloudflareD1UserDeletionDomain domain;
  final DateTime Function() clock;

  String get table => schema.table('oauth_authorization_codes');

  @override
  Future<OAuthAuthorizationCode> create(OAuthAuthorizationCode code) async {
    _validateD1OAuthAuthorizationCode(code);
    try {
      await _sql.run(
        '''INSERT INTO $table
           (code_hash, authorization_id, client_id, user_id, redirect_uri,
            scope, expires_at, code_challenge, code_challenge_method, nonce,
            created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        _oauthAuthorizationCodeValues(code),
      );
    } catch (_) {
      throw StateError('D1 OAuth authorization code creation failed.');
    }
    return code;
  }

  @override
  Future<OAuthAuthorizationCode?> consume({
    required String codeHash,
    required String clientId,
    required String redirectUri,
    required String? codeVerifier,
    DateTime? now,
  }) async {
    final digest = codeHash.trim();
    final results = await _sql.batchRows([
      _sql.database.prepare('SELECT * FROM $table WHERE code_hash = ?').bind([
        digest,
      ]),
      _sql.database.prepare('DELETE FROM $table WHERE code_hash = ?').bind([
        digest,
      ]),
    ]);
    if (_oauthChanges(results.last) != 1 || results.first.results.length != 1) {
      return null;
    }
    final code = _decodeOAuthAuthorizationCode(results.first.results.single);
    final request = OAuthAuthorizationCodeExchangeRequest(
      codeHash: digest,
      clientId: clientId,
      redirectUri: redirectUri,
      codeVerifier: codeVerifier,
      now: (now ?? clock()).toUtc(),
    );
    return code.isValid(now: request.now) &&
            _d1OAuthBindingsMatch(code, request)
        ? code
        : null;
  }

  @override
  Future<int> deleteExpired({DateTime? now}) async => _oauthChanges(
    await _sql.run('DELETE FROM $table WHERE expires_at <= ?', [
      _date((now ?? clock()).toUtc()),
    ]),
  );

  @override
  Future<void> deleteForUser(String userId) async {
    await _sql.run('DELETE FROM $table WHERE user_id = ?', [userId.trim()]);
  }
}

/// Digest-only OAuth access and refresh-token persistence backed by D1.
final class CloudflareD1OAuthAccessTokenStore implements OAuthAccessTokenStore {
  CloudflareD1OAuthAccessTokenStore._(
    this._sql,
    this.schema,
    this.domain,
    this.clock,
  );

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final CloudflareD1UserDeletionDomain domain;
  final DateTime Function() clock;

  String get table => schema.table('oauth_access_tokens');

  @override
  Future<void> save(OAuthAccessToken token) async {
    _validateD1OAuthAccessToken(token);
    try {
      await _sql.run(
        '''INSERT INTO $table
           (token_hash, authorization_id, client_id, user_id, scope,
            expires_at, refresh_token_hash, refresh_token_expires_at,
            refresh_token_uses, issued_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        _oauthAccessTokenValues(token),
      );
    } catch (_) {
      throw StateError('D1 OAuth access token creation failed.');
    }
  }

  @override
  Future<OAuthAccessToken?> findByToken(String token) {
    if (token.trim().isEmpty) return Future.value(null);
    return _findByDigest('token_hash', hashOpaqueToken(token));
  }

  @override
  Future<OAuthAccessToken?> findByRefreshToken(String refreshToken) {
    if (refreshToken.trim().isEmpty) return Future.value(null);
    return _findByDigest('refresh_token_hash', hashOpaqueToken(refreshToken));
  }

  Future<OAuthAccessToken?> _findByDigest(String column, String digest) =>
      _sql.first('SELECT * FROM $table WHERE $column = ?', [
        digest,
      ], _decodeOAuthAccessToken);

  @override
  Future<OAuthAccessToken?> rotateRefreshToken({
    required String refreshToken,
    required String expectedTokenHash,
    required OAuthAccessToken replacement,
    int? maxUses,
  }) async {
    if (refreshToken.trim().isEmpty || expectedTokenHash.trim().isEmpty) {
      return null;
    }
    _validateD1OAuthAccessToken(replacement);
    if (replacement.refreshTokenUses <= 0) {
      throw ArgumentError('Refresh-token replacement use count is invalid.');
    }
    final now = _date(clock().toUtc());
    final expectedUses = replacement.refreshTokenUses - 1;
    final predicate = '''token_hash = ? AND refresh_token_hash = ?
      AND (refresh_token_expires_at IS NULL OR refresh_token_expires_at > ?)
      AND refresh_token_uses = ? AND client_id = ? AND user_id = ?
      AND (? IS NULL OR (? > 0 AND refresh_token_uses < ?))''';
    final predicateValues = <Object?>[
      expectedTokenHash.trim(),
      hashOpaqueToken(refreshToken),
      now,
      expectedUses,
      replacement.clientId,
      replacement.userId,
      maxUses,
      maxUses,
      maxUses,
    ];
    try {
      final results = await _sql.batchRows([
        _sql.database
            .prepare('SELECT * FROM $table WHERE $predicate')
            .bind(predicateValues),
        _sql.database
            .prepare('''UPDATE $table SET token_hash = ?,
                 authorization_id = COALESCE(?, authorization_id),
                 client_id = ?, user_id = ?, scope = ?, expires_at = ?,
                 refresh_token_hash = ?, refresh_token_expires_at = ?,
                 refresh_token_uses = ?, issued_at = ? WHERE $predicate''')
            .bind([
              ..._oauthAccessTokenValues(replacement),
              ...predicateValues,
            ]),
      ]);
      if (_oauthChanges(results.last) != 1 ||
          results.first.results.length != 1) {
        return null;
      }
      return _decodeOAuthAccessToken(results.first.results.single);
    } catch (_) {
      throw StateError('D1 OAuth refresh-token rotation failed atomically.');
    }
  }

  @override
  Future<void> revoke(String token) async {
    if (token.trim().isEmpty) return;
    await _sql.run('DELETE FROM $table WHERE token_hash = ?', [
      hashOpaqueToken(token),
    ]);
  }

  @override
  Future<int> revokeAllForUser(String userId) async => _oauthChanges(
    await _sql.run('DELETE FROM $table WHERE user_id = ?', [userId.trim()]),
  );

  @override
  Future<int> revokeAllForClient(String clientId) async => _oauthChanges(
    await _sql.run('DELETE FROM $table WHERE client_id = ?', [clientId.trim()]),
  );

  @override
  Future<int> deleteExpired({DateTime? now}) async {
    final current = _date((now ?? clock()).toUtc());
    return _oauthChanges(
      await _sql.run(
        '''DELETE FROM $table WHERE expires_at <= ? AND
           (refresh_token_hash IS NULL OR
             (refresh_token_expires_at IS NOT NULL AND
              refresh_token_expires_at <= ?))''',
        [current, current],
      ),
    );
  }
}

/// Authoritative D1 transaction boundary for OAuth authorization-code grants.
///
/// Cloudflare documents `D1Database.batch` as a sequential SQL transaction
/// that rolls back the complete sequence when a statement fails. The insert
/// and delete below use the same complete authorization predicate. D1 does not
/// expose an interactive callback transaction and this adapter does not claim
/// one.
final class CloudflareD1OAuthAuthorizationCodeExchangeStore
    implements
        OAuthAuthorizationCodeExchangeStore,
        OAuthProviderPersistenceTopology,
        AuthUserDeletionPlanFactory {
  CloudflareD1OAuthAuthorizationCodeExchangeStore._(
    this._sql,
    this.schema,
    this.domain,
    this.authorizationCodeStore,
    this.accessTokenStore,
  );

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final CloudflareD1UserDeletionDomain domain;

  @override
  final CloudflareD1OAuthAuthorizationCodeStore authorizationCodeStore;

  @override
  final CloudflareD1OAuthAccessTokenStore accessTokenStore;

  @override
  AuthUserDeletionDomain get oauthProviderPersistenceDomain => domain;

  String get codes => schema.table('oauth_authorization_codes');
  String get tokens => schema.table('oauth_access_tokens');

  @override
  AuthUserDeletionPlan createDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  }) {
    if (!identical(domain, this.domain)) {
      throw StateError('OAuth provider received a foreign D1 domain.');
    }
    return CloudflareD1UserDeletionPlan(
      domain: this.domain,
      userId: user.id,
      namespace: namespace,
      statements: [
        CloudflareD1UserDeletionStatement(
          sql: 'DELETE FROM $codes WHERE user_id = ? AND {{guard}}',
          parameters: [user.id],
        ),
        CloudflareD1UserDeletionStatement(
          sql: 'DELETE FROM $tokens WHERE user_id = ? AND {{guard}}',
          parameters: [user.id],
        ),
      ],
    );
  }

  @override
  Future<OAuthAuthorizationCodePreparation> prepare(
    OAuthAuthorizationCodeExchangeRequest request,
  ) async {
    final digest = request.codeHash.trim();
    final binding = _d1OAuthBindingPredicate(request);
    final results = await _sql.batchRows([
      _sql.database.prepare('SELECT * FROM $codes WHERE code_hash = ?').bind([
        digest,
      ]),
      _sql.database
          .prepare(
            'DELETE FROM $codes WHERE code_hash = ? AND NOT (${binding.sql})',
          )
          .bind([digest, ...binding.values]),
    ]);
    final rows = results.first.results;
    if (rows.isEmpty) {
      return const OAuthAuthorizationCodePreparation.invalidGrant();
    }
    if (rows.length != 1) {
      throw StateError('D1 OAuth authorization code lookup was ambiguous.');
    }
    if (_oauthChanges(results.last) == 1) {
      return const OAuthAuthorizationCodePreparation.invalidGrant();
    }
    final code = _decodeOAuthAuthorizationCode(rows.single);
    if (!code.isValid(now: request.now) ||
        !_d1OAuthBindingsMatch(code, request)) {
      throw StateError('D1 OAuth preparation predicate was inconsistent.');
    }
    return OAuthAuthorizationCodePreparation.ready(code);
  }

  @override
  Future<OAuthAuthorizationCodeExchangeResult> commit({
    required OAuthAuthorizationCodeExchangeRequest request,
    required String expectedAuthorizationId,
    required OAuthAccessToken preparedToken,
  }) async {
    final authorizationId = expectedAuthorizationId.trim();
    _validatePreparedD1OAuthToken(request, authorizationId, preparedToken);
    final predicate = _d1OAuthCommitPredicate(
      request,
      authorizationId,
      preparedToken,
    );
    try {
      final results = await _sql.batch([
        _sql.database
            .prepare('''INSERT INTO $tokens
                 (token_hash, authorization_id, client_id, user_id, scope,
                  expires_at, refresh_token_hash, refresh_token_expires_at,
                  refresh_token_uses, issued_at)
                 SELECT ?, authorization_id, client_id, user_id, scope,
                   ?, ?, ?, ?, ? FROM $codes WHERE ${predicate.sql}''')
            .bind([
              preparedToken.tokenHash,
              _date(preparedToken.expiresAt),
              preparedToken.refreshTokenHash,
              _nullableDate(preparedToken.refreshTokenExpiresAt),
              preparedToken.refreshTokenUses,
              _nullableDate(preparedToken.issuedAt),
              ...predicate.values,
            ]),
        _sql.database
            .prepare('DELETE FROM $codes WHERE ${predicate.sql}')
            .bind(predicate.values),
      ]);
      final inserted = _oauthChanges(results.first);
      final deleted = _oauthChanges(results.last);
      if (inserted == 1 && deleted == 1) {
        return const OAuthAuthorizationCodeExchangeResult(
          OAuthAuthorizationCodeExchangeStatus.committed,
        );
      }
      if (inserted != 0 || deleted != 0) {
        throw StateError('D1 OAuth exchange affected inconsistent rows.');
      }
    } catch (error) {
      if (error is StateError &&
          error.message == 'D1 OAuth exchange affected inconsistent rows.') {
        rethrow;
      }
      throw StateError(
        'D1 OAuth authorization-code exchange failed atomically.',
      );
    }

    final existing = await _sql.first<OAuthAccessToken>(
      'SELECT * FROM $tokens WHERE authorization_id = ?',
      [authorizationId],
      _decodeOAuthAccessToken,
    );
    return OAuthAuthorizationCodeExchangeResult(
      existing == null
          ? OAuthAuthorizationCodeExchangeStatus.invalidGrant
          : OAuthAuthorizationCodeExchangeStatus.alreadyCommitted,
    );
  }
}

/// Durable managed-SCIM connection and bearer-credential persistence.
///
/// Only non-reversible bearer digests cross this boundary. Issuance replay
/// identity is constrained by D1 and every multi-row mutation is submitted as
/// one atomic D1 batch. The adapter has no in-memory or split-database mode.
final class CloudflareD1ScimConnectionStore
    implements AuthScimConnectionStore, AuthUserDeletionPlanFactory {
  CloudflareD1ScimConnectionStore._(
    this._sql,
    this.schema,
    this.domain, {
    this.replayTtl = const Duration(days: 1),
  }) {
    if (replayTtl <= Duration.zero) {
      throw ArgumentError.value(replayTtl, 'replayTtl', 'must be positive');
    }
  }

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final CloudflareD1UserDeletionDomain domain;
  final Duration replayTtl;

  String get _connections => schema.table('scim_connections');
  String get _credentials => schema.table('scim_credentials');
  String get _replays => schema.table('scim_replays');

  @override
  AuthUserDeletionPlan createDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  }) {
    if (!identical(domain, this.domain)) {
      throw StateError('Managed SCIM received a foreign D1 domain.');
    }
    return CloudflareD1UserDeletionPlan(
      domain: this.domain,
      userId: user.id,
      namespace: namespace,
      statements: [
        CloudflareD1UserDeletionStatement(
          sql:
              'DELETE FROM $_connections '
              'WHERE subject_id = ? AND {{guard}}',
          parameters: [user.id],
        ),
      ],
    );
  }

  @override
  Future<AuthScimStoredConnectionCreation> createConnection(
    AuthScimCreateConnectionTransaction transaction,
  ) async {
    final connection = transaction.connection;
    final credential = transaction.credential;
    _validateScimCredential(connection, credential);
    const operation = 'create';
    final replay = await _readReplay(
      connection.binding,
      operation,
      transaction.idempotency,
      connection.createdAt,
    );
    if (replay != null) {
      return AuthScimStoredConnectionCreation(
        connection: replay.connection,
        credential: replay.credential,
        replayed: true,
      );
    }

    try {
      await _sql.batch([
        _sql.database
            .prepare('''INSERT INTO $_connections
              (id, tenant_id, organization_id, provisioning_domain_id,
               subject_id, name, scopes, scope_mask, created_at, updated_at,
               disabled_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''')
            .bind(_scimConnectionValues(connection)),
        _sql.database
            .prepare('''INSERT INTO $_credentials
              (id, connection_id, tenant_id, organization_id, name,
               key_prefix, secret_digest, scopes, scope_mask, created_at,
               updated_at, expires_at, last_used_at, revoked_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''')
            .bind(_scimCredentialValues(credential)),
        _replayInsert(
          connection.binding,
          operation,
          transaction.idempotency,
          connection.id,
          credential.id,
          connection.createdAt,
        ),
      ]);
    } catch (_) {
      final committed = await _readReplay(
        connection.binding,
        operation,
        transaction.idempotency,
        connection.createdAt,
      );
      if (committed != null) {
        return AuthScimStoredConnectionCreation(
          connection: committed.connection,
          credential: committed.credential,
          replayed: true,
        );
      }
      if (await _hasScimConflict(connection, credential)) {
        throw const AuthScimConnectionStoreException(
          AuthScimConnectionStoreFailure.conflict,
        );
      }
      throw StateError('D1 managed SCIM creation failed atomically.');
    }
    return AuthScimStoredConnectionCreation(
      connection: connection,
      credential: credential,
      replayed: false,
    );
  }

  @override
  Future<AuthScimConnectionPage> listConnections(
    AuthScimConnectionCatalogQuery query,
  ) async {
    final predicate = 'tenant_id = ? AND organization_id = ?';
    final values = [query.binding.tenantId, query.binding.organizationId];
    final results = await _sql.batchRows([
      _sql.database
          .prepare(
            'SELECT COUNT(*) AS total FROM $_connections '
            'WHERE $predicate',
          )
          .bind(values),
      _sql.database
          .prepare(
            'SELECT * FROM $_connections WHERE $predicate '
            'ORDER BY created_at DESC LIMIT ? OFFSET ?',
          )
          .bind([...values, query.limit, query.offset]),
    ]);
    final total = (results.first.results.single['total'] as num).toInt();
    return AuthScimConnectionPage(
      items: results.last.results
          .map(_decodeScimConnection)
          .toList(growable: false),
      total: total,
      limit: query.limit,
      offset: query.offset,
    );
  }

  @override
  Future<AuthScimManagedConnection?> findConnection(
    AuthScimConnectionBinding binding,
    String connectionId,
  ) => _sql.first(
    'SELECT * FROM $_connections WHERE id = ? AND tenant_id = ? '
    'AND organization_id = ?',
    [connectionId.trim(), binding.tenantId, binding.organizationId],
    _decodeScimConnection,
  );

  @override
  Future<AuthScimManagedConnection?> updateConnection(
    AuthScimUpdateConnectionTransaction transaction,
  ) async {
    final next = transaction.connection;
    final binding = transaction.binding;
    if (next.tenantId != binding.tenantId ||
        next.organizationId != binding.organizationId ||
        !next.isActive) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.conflict,
      );
    }
    final allowedMask = _scimGrantedMask(next.scopes);
    final results = await _sql.batch([
      _sql.database
          .prepare('''UPDATE $_connections SET
              provisioning_domain_id = ?, name = ?, scopes = ?,
              scope_mask = ?, updated_at = ?
            WHERE id = ? AND tenant_id = ? AND organization_id = ?
              AND subject_id = ? AND created_at = ? AND updated_at = ?
              AND disabled_at IS NULL''')
          .bind([
            next.provisioningDomainId,
            next.name,
            _encodeScimScopes(next.scopes),
            allowedMask,
            _date(next.updatedAt),
            next.id,
            binding.tenantId,
            binding.organizationId,
            next.subjectId,
            _date(next.createdAt),
            _date(transaction.expectedUpdatedAt),
          ]),
      _sql.database
          .prepare('''UPDATE $_credentials SET
              updated_at = ?, revoked_at = ?
            WHERE connection_id = ? AND revoked_at IS NULL
              AND (scope_mask & ~$allowedMask) != 0
              AND EXISTS (
                SELECT 1 FROM $_connections
                WHERE id = ? AND tenant_id = ? AND organization_id = ?
                  AND updated_at = ? AND scope_mask = ?
              )''')
          .bind([
            _date(next.updatedAt),
            _date(next.updatedAt),
            next.id,
            next.id,
            binding.tenantId,
            binding.organizationId,
            _date(next.updatedAt),
            allowedMask,
          ]),
    ]);
    if ((results.first.meta?.changes ?? 0) != 1) {
      final existing = await findConnection(binding, next.id);
      if (existing == null) return null;
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.conflict,
      );
    }
    return findConnection(binding, next.id);
  }

  @override
  Future<AuthScimManagedConnection?> disableConnection(
    AuthScimConnectionBinding binding,
    String connectionId, {
    required DateTime disabledAt,
  }) async {
    final id = connectionId.trim();
    final existing = await findConnection(binding, id);
    if (existing == null) return null;
    final current = disabledAt.toUtc();
    await _sql.batch([
      _sql.database
          .prepare('''UPDATE $_connections
            SET updated_at = ?, disabled_at = ?
            WHERE id = ? AND tenant_id = ? AND organization_id = ?
              AND disabled_at IS NULL''')
          .bind([
            _date(current),
            _date(current),
            id,
            binding.tenantId,
            binding.organizationId,
          ]),
      _sql.database
          .prepare('''UPDATE $_credentials
            SET updated_at = ?, revoked_at = ?
            WHERE connection_id = ? AND revoked_at IS NULL
              AND EXISTS (
                SELECT 1 FROM $_connections WHERE id = ?
                  AND tenant_id = ? AND organization_id = ?
                  AND disabled_at IS NOT NULL
              )''')
          .bind([
            _date(current),
            _date(current),
            id,
            id,
            binding.tenantId,
            binding.organizationId,
          ]),
    ]);
    return findConnection(binding, id);
  }

  @override
  Future<AuthScimStoredCredentialIssuance> issueCredential(
    AuthScimIssueCredentialTransaction transaction,
  ) async {
    final credential = transaction.credential;
    final connection = await findConnection(
      transaction.binding,
      credential.connectionId,
    );
    if (connection == null) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.notFound,
      );
    }
    _validateScimCredential(connection, credential);
    if (!connection.isActive) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.disabled,
      );
    }
    final operation = 'issue:${connection.id}';
    final replay = await _readReplay(
      transaction.binding,
      operation,
      transaction.idempotency,
      credential.createdAt,
    );
    if (replay != null) {
      return AuthScimStoredCredentialIssuance(
        credential: replay.credential,
        replayed: true,
      );
    }

    try {
      await _sql.batch([
        _sql.database
            .prepare('''INSERT INTO $_credentials
              (id, connection_id, tenant_id, organization_id, name,
               key_prefix, secret_digest, scopes, scope_mask, created_at,
               updated_at, expires_at, last_used_at, revoked_at)
              SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
              WHERE EXISTS (
                SELECT 1 FROM $_connections WHERE id = ?
                  AND tenant_id = ? AND organization_id = ?
                  AND disabled_at IS NULL
              )''')
            .bind([
              ..._scimCredentialValues(credential),
              connection.id,
              transaction.binding.tenantId,
              transaction.binding.organizationId,
            ]),
        _replayInsert(
          transaction.binding,
          operation,
          transaction.idempotency,
          connection.id,
          credential.id,
          credential.createdAt,
        ),
      ]);
    } catch (_) {
      final committed = await _readReplay(
        transaction.binding,
        operation,
        transaction.idempotency,
        credential.createdAt,
      );
      if (committed != null) {
        return AuthScimStoredCredentialIssuance(
          credential: committed.credential,
          replayed: true,
        );
      }
      if (await _hasScimCredentialConflict(credential)) {
        throw const AuthScimConnectionStoreException(
          AuthScimConnectionStoreFailure.conflict,
        );
      }
      throw StateError('D1 managed SCIM issuance failed atomically.');
    }
    return AuthScimStoredCredentialIssuance(
      credential: credential,
      replayed: false,
    );
  }

  @override
  Future<AuthScimStoredCredentialIssuance?> rotateCredential(
    AuthScimRotateCredentialTransaction transaction,
  ) async {
    final binding = transaction.binding;
    final connection = await findConnection(binding, transaction.connectionId);
    if (connection == null) return null;
    if (!connection.isActive) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.disabled,
      );
    }
    _validateScimCredential(connection, transaction.replacement);
    final operation =
        'rotate:${connection.id}:${transaction.credentialId.trim()}';
    final replay = await _readReplay(
      binding,
      operation,
      transaction.idempotency,
      transaction.revokedAt,
    );
    if (replay != null) {
      return AuthScimStoredCredentialIssuance(
        credential: replay.credential,
        replayed: true,
      );
    }

    final now = transaction.revokedAt.toUtc();
    final replacement = transaction.replacement;
    try {
      final results = await _sql.batch([
        _sql.database
            .prepare('''INSERT INTO $_credentials
              (id, connection_id, tenant_id, organization_id, name,
               key_prefix, secret_digest, scopes, scope_mask, created_at,
               updated_at, expires_at, last_used_at, revoked_at)
              SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
              WHERE EXISTS (
                SELECT 1 FROM $_credentials AS old
                JOIN $_connections AS connection
                  ON connection.id = old.connection_id
                WHERE old.id = ? AND old.connection_id = ?
                  AND old.revoked_at IS NULL
                  AND (old.expires_at IS NULL OR old.expires_at > ?)
                  AND connection.tenant_id = ?
                  AND connection.organization_id = ?
                  AND connection.disabled_at IS NULL
              )''')
            .bind([
              ..._scimCredentialValues(replacement),
              transaction.credentialId.trim(),
              connection.id,
              _date(now),
              binding.tenantId,
              binding.organizationId,
            ]),
        _sql.database
            .prepare('''UPDATE $_credentials
              SET updated_at = ?, revoked_at = ?
              WHERE id = ? AND connection_id = ? AND revoked_at IS NULL
                AND (expires_at IS NULL OR expires_at > ?)
                AND EXISTS (
                  SELECT 1 FROM $_credentials AS replacement
                  WHERE replacement.id = ?
                    AND replacement.connection_id = ?
                    AND replacement.secret_digest = ?
                )''')
            .bind([
              _date(now),
              _date(now),
              transaction.credentialId.trim(),
              connection.id,
              _date(now),
              replacement.id,
              connection.id,
              replacement.secretDigest,
            ]),
        _sql.database
            .prepare('''INSERT INTO $_replays
              (tenant_id, organization_id, operation, idempotency_key,
               fingerprint, connection_id, credential_id, expires_at)
              SELECT ?, ?, ?, ?, ?, ?, ?, ?
              WHERE EXISTS (
                SELECT 1 FROM $_credentials AS old
                WHERE old.id = ? AND old.connection_id = ?
                  AND old.revoked_at = ?
              ) AND EXISTS (
                SELECT 1 FROM $_credentials AS replacement
                WHERE replacement.id = ?
                  AND replacement.connection_id = ?
                  AND replacement.secret_digest = ?
              )''')
            .bind([
              binding.tenantId,
              binding.organizationId,
              operation,
              transaction.idempotency.key,
              transaction.idempotency.fingerprint,
              connection.id,
              replacement.id,
              _date(now.add(replayTtl)),
              transaction.credentialId.trim(),
              connection.id,
              _date(now),
              replacement.id,
              connection.id,
              replacement.secretDigest,
            ]),
      ]);
      if ((results.first.meta?.changes ?? 0) == 1 &&
          (results[1].meta?.changes ?? 0) == 1 &&
          (results.last.meta?.changes ?? 0) == 1) {
        return AuthScimStoredCredentialIssuance(
          credential: replacement,
          replayed: false,
        );
      }
      if (results.any((result) => (result.meta?.changes ?? 0) != 0)) {
        throw StateError('D1 managed SCIM rotation changed partial state.');
      }
      return null;
    } catch (_) {
      final committed = await _readReplay(
        binding,
        operation,
        transaction.idempotency,
        now,
      );
      if (committed != null) {
        return AuthScimStoredCredentialIssuance(
          credential: committed.credential,
          replayed: true,
        );
      }
      if (await _hasScimCredentialConflict(replacement)) {
        throw const AuthScimConnectionStoreException(
          AuthScimConnectionStoreFailure.conflict,
        );
      }
      throw StateError('D1 managed SCIM rotation failed atomically.');
    }
  }

  @override
  Future<AuthScimCredentialRecord?> revokeCredential(
    AuthScimConnectionBinding binding,
    String connectionId,
    String credentialId, {
    required DateTime revokedAt,
  }) async {
    final current = revokedAt.toUtc();
    final id = credentialId.trim();
    final connection = connectionId.trim();
    await _sql.run(
      '''UPDATE $_credentials SET updated_at = ?, revoked_at = ?
        WHERE id = ? AND connection_id = ? AND revoked_at IS NULL
          AND EXISTS (
            SELECT 1 FROM $_connections WHERE id = ?
              AND tenant_id = ? AND organization_id = ?
          )''',
      [
        _date(current),
        _date(current),
        id,
        connection,
        connection,
        binding.tenantId,
        binding.organizationId,
      ],
    );
    return _sql.first(
      '''SELECT credential.* FROM $_credentials AS credential
        JOIN $_connections AS connection
          ON connection.id = credential.connection_id
        WHERE credential.id = ? AND credential.connection_id = ?
          AND connection.tenant_id = ? AND connection.organization_id = ?''',
      [id, connection, binding.tenantId, binding.organizationId],
      _decodeScimCredential,
    );
  }

  @override
  Future<AuthScimCredentialPage> listCredentials(
    AuthScimCredentialCatalogQuery query, {
    required DateTime now,
  }) async {
    final connection = await findConnection(query.binding, query.connectionId);
    if (connection == null) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.notFound,
      );
    }
    final results = await _sql.batchRows([
      _sql.database
          .prepare(
            'SELECT COUNT(*) AS total FROM $_credentials '
            'WHERE connection_id = ?',
          )
          .bind([connection.id]),
      _sql.database
          .prepare(
            'SELECT * FROM $_credentials WHERE connection_id = ? '
            'ORDER BY created_at DESC LIMIT ? OFFSET ?',
          )
          .bind([connection.id, query.limit, query.offset]),
    ]);
    final total = (results.first.results.single['total'] as num).toInt();
    final current = now.toUtc();
    return AuthScimCredentialPage(
      items: results.last.results
          .map(_decodeScimCredential)
          .map((credential) => credential.toPublic(now: current))
          .toList(growable: false),
      total: total,
      limit: query.limit,
      offset: query.offset,
    );
  }

  @override
  Future<AuthScimConnectionIdentity?> resolveCredentialDigest(
    String digest, {
    required DateTime now,
  }) async {
    final normalized = digest.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(normalized)) return null;
    final current = now.toUtc();
    final predicate = '''credential.secret_digest = ?
      AND credential.revoked_at IS NULL
      AND (credential.expires_at IS NULL OR credential.expires_at > ?)
      AND connection.disabled_at IS NULL
      AND connection.tenant_id = credential.tenant_id
      AND connection.organization_id = credential.organization_id
      AND (credential.scope_mask & ~connection.scope_mask) = 0''';
    final results = await _sql.batchRows([
      _sql.database
          .prepare('''SELECT
              connection.id AS connection_id,
              credential.id AS credential_id,
              connection.tenant_id AS tenant_id,
              connection.organization_id AS organization_id,
              connection.provisioning_domain_id AS provisioning_domain_id,
              connection.subject_id AS subject_id,
              credential.scopes AS credential_scopes,
              credential.expires_at AS credential_expires_at
            FROM $_credentials AS credential
            JOIN $_connections AS connection
              ON connection.id = credential.connection_id
            WHERE $predicate''')
          .bind([normalized, _date(current)]),
      _sql.database
          .prepare('''UPDATE $_credentials AS credential
            SET updated_at = ?, last_used_at = ?
            WHERE secret_digest = ? AND revoked_at IS NULL
              AND (expires_at IS NULL OR expires_at > ?)
              AND EXISTS (
                SELECT 1 FROM $_connections AS connection
                WHERE connection.id = credential.connection_id
                  AND connection.disabled_at IS NULL
                  AND connection.tenant_id = credential.tenant_id
                  AND connection.organization_id = credential.organization_id
                  AND (credential.scope_mask & ~connection.scope_mask) = 0
              )''')
          .bind([_date(current), _date(current), normalized, _date(current)]),
    ]);
    if (results.first.results.length != 1 ||
        (results.last.meta?.changes ?? 0) != 1) {
      return null;
    }
    final row = results.first.results.single;
    return AuthScimConnectionIdentity(
      connectionId: row['connection_id']! as String,
      credentialId: row['credential_id']! as String,
      tenantId: row['tenant_id']! as String,
      organizationId: row['organization_id']! as String,
      provisioningDomainId: row['provisioning_domain_id']! as String,
      subjectId: row['subject_id']! as String,
      scopes: _decodeScimScopes(row['credential_scopes']),
      expiresAt: _optionalDate(row['credential_expires_at']),
    );
  }

  @override
  Future<void> deleteForSubject(String subjectId) async {
    await _sql.run('DELETE FROM $_connections WHERE subject_id = ?', [
      subjectId.trim(),
    ]);
  }

  @override
  Future<void> deleteForTenant(String tenantId) async {
    await _sql.run('DELETE FROM $_connections WHERE tenant_id = ?', [
      tenantId.trim(),
    ]);
  }

  CloudflareD1PreparedStatement _replayInsert(
    AuthScimConnectionBinding binding,
    String operation,
    AuthScimIdempotencyBinding idempotency,
    String connectionId,
    String credentialId,
    DateTime now,
  ) => _sql.database
      .prepare('''INSERT INTO $_replays
        (tenant_id, organization_id, operation, idempotency_key, fingerprint,
         connection_id, credential_id, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)''')
      .bind([
        binding.tenantId,
        binding.organizationId,
        operation,
        idempotency.key,
        idempotency.fingerprint,
        connectionId,
        credentialId,
        _date(now.toUtc().add(replayTtl)),
      ]);

  Future<_D1ScimReplay?> _readReplay(
    AuthScimConnectionBinding binding,
    String operation,
    AuthScimIdempotencyBinding idempotency,
    DateTime now,
  ) async {
    final keyValues = [
      binding.tenantId,
      binding.organizationId,
      operation,
      idempotency.key,
    ];
    await _sql.run(
      '''DELETE FROM $_replays
        WHERE tenant_id = ? AND organization_id = ? AND operation = ?
          AND idempotency_key = ? AND expires_at <= ?''',
      [...keyValues, _date(now)],
    );
    final replay = await _sql.first(
      '''SELECT
          replay.fingerprint AS replay_fingerprint,
          connection.id AS connection_id,
          connection.tenant_id AS connection_tenant_id,
          connection.organization_id AS connection_organization_id,
          connection.provisioning_domain_id AS connection_domain_id,
          connection.subject_id AS connection_subject_id,
          connection.name AS connection_name,
          connection.scopes AS connection_scopes,
          connection.created_at AS connection_created_at,
          connection.updated_at AS connection_updated_at,
          connection.disabled_at AS connection_disabled_at,
          credential.id AS credential_id,
          credential.connection_id AS credential_connection_id,
          credential.tenant_id AS credential_tenant_id,
          credential.organization_id AS credential_organization_id,
          credential.name AS credential_name,
          credential.key_prefix AS credential_key_prefix,
          credential.secret_digest AS credential_secret_digest,
          credential.scopes AS credential_scopes,
          credential.created_at AS credential_created_at,
          credential.updated_at AS credential_updated_at,
          credential.expires_at AS credential_expires_at,
          credential.last_used_at AS credential_last_used_at,
          credential.revoked_at AS credential_revoked_at
        FROM $_replays AS replay
        JOIN $_connections AS connection
          ON connection.id = replay.connection_id
        JOIN $_credentials AS credential
          ON credential.id = replay.credential_id
        WHERE replay.tenant_id = ? AND replay.organization_id = ?
          AND replay.operation = ? AND replay.idempotency_key = ?
          AND replay.expires_at > ?''',
      [...keyValues, _date(now)],
      _decodeScimReplay,
    );
    if (replay != null && replay.fingerprint != idempotency.fingerprint) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.replayMismatch,
      );
    }
    return replay;
  }

  Future<bool> _hasScimConflict(
    AuthScimManagedConnection connection,
    AuthScimCredentialRecord credential,
  ) async {
    final row = await _sql.first(
      '''SELECT 1 AS present WHERE
        EXISTS (SELECT 1 FROM $_connections WHERE id = ?) OR
        EXISTS (SELECT 1 FROM $_credentials
          WHERE id = ? OR secret_digest = ?)''',
      [connection.id, credential.id, credential.secretDigest],
      (_) => true,
    );
    return row ?? false;
  }

  Future<bool> _hasScimCredentialConflict(
    AuthScimCredentialRecord credential,
  ) async {
    final row = await _sql.first(
      'SELECT 1 AS present FROM $_credentials '
      'WHERE id = ? OR secret_digest = ? LIMIT 1',
      [credential.id, credential.secretDigest],
      (_) => true,
    );
    return row ?? false;
  }
}

final class _D1Users implements AuthUserStore {
  _D1Users(this.sql, this.schema);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  String get table => schema.table('users');
  String get deletionReceipts => schema.table('deletion_receipts');

  @override
  Future<AuthUser?> findById(String id) => sql.first(
    'SELECT payload FROM $table WHERE id = ?',
    [id.trim()],
    _decodeUser,
  );

  @override
  Future<AuthUser?> findByEmail(String email) => sql.first(
    'SELECT payload FROM $table WHERE email = ?',
    [_email(email)],
    _decodeUser,
  );

  @override
  Future<AuthUser> create(AuthUser user) async {
    validateAuthUserForPersistence(user);
    final id = user.id.trim();
    final result = await sql.run(
      '''INSERT INTO $table (id, email, payload)
         SELECT ?, ?, ?
         WHERE NOT EXISTS (
           SELECT 1 FROM $deletionReceipts WHERE user_id_hash = ?
         )''',
      [id, _nullableEmail(user.email), _encodeUser(user), hashOpaqueToken(id)],
    );
    if ((result.meta?.changes ?? 0) != 1) {
      throw StateError('Auth user ID is permanently unavailable.');
    }
    return user;
  }

  @override
  Future<AuthUserCreateResult> createOrFindByEmail(AuthUser user) async {
    validateAuthUserForPersistence(user);
    final email = _nullableEmail(user.email);
    final id = user.id.trim();
    if (email == null) {
      return AuthUserCreateResult(user: await create(user), created: true);
    }
    final inserted = await sql.run(
      '''INSERT INTO $table (id, email, payload)
         SELECT ?, ?, ?
         WHERE NOT EXISTS (
           SELECT 1 FROM $deletionReceipts WHERE user_id_hash = ?
         )
         ON CONFLICT(email) DO NOTHING''',
      [id, email, _encodeUser(user), hashOpaqueToken(id)],
    );
    if ((inserted.meta?.changes ?? 0) == 1) {
      return AuthUserCreateResult(user: user, created: true);
    }
    final existing = await findByEmail(email);
    if (existing == null) {
      throw StateError(
        'D1 refused a deleted user ID or lost the canonical email user.',
      );
    }
    return AuthUserCreateResult(user: existing, created: false);
  }

  @override
  Future<AuthUser?> update(AuthUser user) async {
    validateAuthUserForPersistence(user);
    await sql.run('UPDATE $table SET email = ?, payload = ? WHERE id = ?', [
      _nullableEmail(user.email),
      _encodeUser(user),
      user.id.trim(),
    ]);
    return findById(user.id);
  }

  @override
  Future<AuthUser?> updateEmailForUser(String userId, String email) async {
    final normalized = _email(email);
    await sql.run(
      '''UPDATE $table
         SET email = ?, payload = json_set(payload, '\$.email', ?)
         WHERE id = ?''',
      [normalized, normalized, userId.trim()],
    );
    return findById(userId);
  }

  @override
  Future<bool> delete(String userId) async =>
      (await sql.run('DELETE FROM $table WHERE id = ?', [
        userId.trim(),
      ])).meta?.changes ==
      1;
}

final class _D1Credentials
    implements AuthCredentialStore, AuthCredentialUserLookupStore {
  _D1Credentials(this.sql, this.schema);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  String get table => schema.table('credentials');

  @override
  Future<AuthPasswordCredential?> findByIdentifier(String identifier) =>
      sql.first('SELECT * FROM $table WHERE identifier = ?', [
        identifier.trim().toLowerCase(),
      ], _decodeCredential);

  Future<AuthPasswordCredential?> findByUsername(String username) =>
      findByIdentifier(username);

  Future<AuthPasswordCredential?> findById(String id) => sql.first(
    'SELECT * FROM $table WHERE id = ?',
    [id.trim()],
    _decodeCredential,
  );

  @override
  Future<AuthPasswordCredential?> findForUser(String userId) => sql.first(
    'SELECT * FROM $table WHERE user_id = ? ORDER BY created_at LIMIT 1',
    [userId.trim()],
    _decodeCredential,
  );

  Future<AuthPasswordCredential?> findUsernameForUser(String userId) =>
      sql.first(
        '''SELECT * FROM $table
           WHERE user_id = ? AND instr(identifier, '@') = 0
           ORDER BY created_at LIMIT 1''',
        [userId.trim()],
        _decodeCredential,
      );

  @override
  Future<AuthUser?> register(
    AuthUser user,
    AuthPasswordCredential credential,
  ) async {
    validateAuthUserForPersistence(user);
    if (credential.userId != user.id ||
        credential.passwordHash.trim().isEmpty) {
      throw ArgumentError('Credential ownership and hash must be valid.');
    }
    final userId = user.id.trim();
    final deletionReceipts = schema.table('deletion_receipts');
    final results = await sql.batch([
      sql.database
          .prepare('''INSERT INTO ${schema.table('users')} (id, email, payload)
               SELECT ?, ?, ?
               WHERE NOT EXISTS (
                 SELECT 1 FROM $deletionReceipts WHERE user_id_hash = ?
               )''')
          .bind([
            userId,
            _nullableEmail(user.email),
            _encodeUser(user),
            hashOpaqueToken(userId),
          ]),
      sql.database
          .prepare('''INSERT INTO $table
               (id, user_id, identifier, password_hash, created_at, updated_at, enabled)
               SELECT ?, ?, ?, ?, ?, ?, ?
               WHERE EXISTS (
                 SELECT 1 FROM ${schema.table('users')} WHERE id = ?
               )''')
          .bind([..._credentialValues(credential), userId]),
    ]);
    if ((results.first.meta?.changes ?? 0) != 1 ||
        (results.last.meta?.changes ?? 0) != 1) {
      return null;
    }
    return user;
  }

  @override
  Future<AuthPasswordCredential?> update(
    AuthPasswordCredential credential,
  ) async {
    await sql.run(
      '''UPDATE $table SET identifier = ?, password_hash = ?,
         updated_at = ?, enabled = ? WHERE id = ? AND user_id = ?''',
      [
        credential.identifier.trim().toLowerCase(),
        credential.passwordHash,
        _date(credential.updatedAt),
        credential.enabled ? 1 : 0,
        credential.id,
        credential.userId,
      ],
    );
    return sql.first('SELECT * FROM $table WHERE id = ?', [
      credential.id,
    ], _decodeCredential);
  }

  @override
  Future<int> updatePasswordForUser({
    required String userId,
    required String passwordHash,
    required DateTime updatedAt,
  }) async =>
      (await sql.run(
        'UPDATE $table SET password_hash = ?, updated_at = ? WHERE user_id = ?',
        [passwordHash, _date(updatedAt), userId.trim()],
      )).meta?.changes ??
      0;

  @override
  Future<void> delete(String credentialId) async {
    await sql.run('DELETE FROM $table WHERE id = ?', [credentialId.trim()]);
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await sql.run('DELETE FROM $table WHERE user_id = ?', [userId.trim()]);
  }
}

final class _D1Accounts implements AuthAccountStore {
  _D1Accounts(this.sql, this.schema);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  String get table => schema.table('accounts');

  @override
  Future<AuthAccount?> find(String providerId, String providerAccountId) =>
      sql.first(
        '''SELECT payload FROM $table
           WHERE provider_id = ? AND provider_account_id = ?''',
        [providerId.trim(), providerAccountId.trim()],
        _decodeAccount,
      );

  @override
  Future<List<AuthAccount>> listForUser(String userId) => sql.all(
    'SELECT payload FROM $table WHERE user_id = ? ORDER BY provider_id',
    [userId.trim()],
    _decodeAccount,
  );

  @override
  Future<AuthAccount> link(AuthAccount account) async {
    validateAuthAccountForLink(account);
    await sql.run(
      '''INSERT OR IGNORE INTO $table
         (provider_id, provider_account_id, user_id, payload)
         VALUES (?, ?, ?, ?)''',
      [
        account.providerId.trim(),
        account.providerAccountId.trim(),
        account.userId!.trim(),
        jsonEncode(account.toStorageJson()),
      ],
    );
    final canonical = await find(account.providerId, account.providerAccountId);
    if (canonical == null) throw StateError('D1 did not persist account link.');
    return canonical;
  }

  @override
  Future<bool> unlinkForUser(
    String userId,
    String providerId,
    String providerAccountId,
  ) async {
    final result = await sql.run(
      '''DELETE FROM $table
         WHERE user_id = ? AND provider_id = ? AND provider_account_id = ?''',
      [userId.trim(), providerId.trim(), providerAccountId.trim()],
    );
    return (result.meta?.changes ?? 0) == 1;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await sql.run('DELETE FROM $table WHERE user_id = ?', [userId.trim()]);
  }
}

final class _D1Sessions implements AuthSessionStore {
  _D1Sessions(this.sql, this.schema, this.clock);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  String get table => schema.table('sessions');

  @override
  Future<AuthSessionRecord?> find(String tokenHash) => sql.first(
    'SELECT * FROM $table WHERE token_hash = ?',
    [tokenHash.trim()],
    _decodeSession,
  );

  @override
  Future<AuthSessionRecord> create(AuthSessionRecord session) async {
    validateAuthSessionForPersistence(session);
    await sql.run('''INSERT INTO $table
         (id, token_hash, user_id, created_at, expires_at, last_used_at, revoked_at, payload)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''', _sessionValues(session));
    return session;
  }

  @override
  Future<AuthSessionRecord?> touch(
    String tokenHash,
    DateTime lastUsedAt,
  ) async {
    final result = await sql.run(
      '''UPDATE $table SET last_used_at = ?,
         payload = json_set(payload, '\$.last_used_at', ?)
         WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?''',
      [_date(lastUsedAt), _date(lastUsedAt), tokenHash, _date(clock())],
    );
    return (result.meta?.changes ?? 0) == 1 ? find(tokenHash) : null;
  }

  @override
  Future<List<AuthSessionRecord>> listForUser(String userId) => sql.all(
    'SELECT * FROM $table WHERE user_id = ? ORDER BY created_at',
    [userId.trim()],
    _decodeSession,
  );

  @override
  Future<AuthSessionRecord?> revoke(
    String tokenHash, {
    DateTime? revokedAt,
  }) async {
    final timestamp = _date(revokedAt ?? clock());
    await sql.run(
      '''UPDATE $table SET revoked_at = ?,
         payload = json_set(payload, '\$.revoked_at', ?)
         WHERE token_hash = ? AND revoked_at IS NULL''',
      [timestamp, timestamp, tokenHash.trim()],
    );
    return find(tokenHash);
  }

  @override
  Future<AuthSessionRecord?> revokeById(
    String userId,
    String sessionId, {
    DateTime? revokedAt,
  }) async {
    final timestamp = _date(revokedAt ?? clock());
    await sql.run(
      '''UPDATE $table SET revoked_at = ?,
         payload = json_set(payload, '\$.revoked_at', ?)
         WHERE id = ? AND user_id = ? AND revoked_at IS NULL''',
      [timestamp, timestamp, sessionId.trim(), userId.trim()],
    );
    return sql.first('SELECT * FROM $table WHERE id = ? AND user_id = ?', [
      sessionId.trim(),
      userId.trim(),
    ], _decodeSession);
  }

  @override
  Future<int> revokeAllForUser(String userId, {DateTime? revokedAt}) =>
      _revokeMany(userId, null, revokedAt);

  @override
  Future<int> revokeAllForUserExcept(
    String userId,
    String currentSessionId, {
    DateTime? revokedAt,
  }) => _revokeMany(userId, currentSessionId, revokedAt);

  Future<int> _revokeMany(
    String userId,
    String? except,
    DateTime? revokedAt,
  ) async {
    final timestamp = _date(revokedAt ?? clock());
    final result = await sql.run(
      '''UPDATE $table SET revoked_at = ?,
         payload = json_set(payload, '\$.revoked_at', ?)
         WHERE user_id = ? AND revoked_at IS NULL
         ${except == null ? '' : 'AND id <> ?'}''',
      [timestamp, timestamp, userId.trim(), ?except],
    );
    return result.meta?.changes ?? 0;
  }

  @override
  Future<AuthSessionRecord?> rotate({
    required String previousTokenHash,
    required AuthSessionRecord replacement,
  }) async {
    validateAuthSessionForPersistence(replacement);
    final now = _date(clock());
    final values = _sessionValues(replacement);
    final results = await sql.batch([
      sql.database
          .prepare('''UPDATE $table SET revoked_at = ?,
               payload = json_set(payload, '\$.revoked_at', ?,
                 '\$._rotation_replacement_hash', ?)
               WHERE token_hash = ? AND user_id = ?
                 AND revoked_at IS NULL AND expires_at > ?''')
          .bind([
            now,
            now,
            replacement.tokenHash,
            previousTokenHash.trim(),
            replacement.userId,
            now,
          ]),
      sql.database
          .prepare('''INSERT INTO $table
               (id, token_hash, user_id, created_at, expires_at, last_used_at, revoked_at, payload)
               SELECT ?, ?, ?, ?, ?, ?, ?, ?
               WHERE EXISTS (SELECT 1 FROM $table
                 WHERE token_hash = ? AND user_id = ?
                   AND revoked_at = ?
                   AND json_extract(payload,
                     '\$._rotation_replacement_hash') = ?)''')
          .bind([
            ...values,
            previousTokenHash.trim(),
            replacement.userId,
            now,
            replacement.tokenHash,
          ]),
    ]);
    if ((results.first.meta?.changes ?? 0) != 1 ||
        (results.last.meta?.changes ?? 0) != 1) {
      return null;
    }
    return replacement;
  }
}

final class _D1PasswordResetTokens implements AuthPasswordResetTokenStore {
  _D1PasswordResetTokens(this.sql, this.schema, this.clock);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  String get table => schema.table('password_reset_tokens');

  @override
  Future<void> save(AuthPasswordResetToken token) async {
    if (token.userId.trim().isEmpty || token.tokenHash.trim().isEmpty) {
      throw ArgumentError('Password-reset token fields must be non-empty.');
    }
    await sql.run(
      '''INSERT INTO $table (user_id, token_hash, created_at, expires_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET token_hash = excluded.token_hash,
           created_at = excluded.created_at, expires_at = excluded.expires_at''',
      [
        token.userId.trim(),
        token.tokenHash,
        _date(token.createdAt),
        _date(token.expiresAt),
      ],
    );
  }

  @override
  Future<AuthPasswordResetToken?> findActive(String token) => sql.first(
    'SELECT * FROM $table WHERE token_hash = ? AND expires_at > ?',
    [hashOpaqueToken(token), _date(clock())],
    _decodePasswordResetToken,
  );

  @override
  Future<AuthPasswordResetToken?> consume(String token) async {
    final values = [hashOpaqueToken(token), _date(clock())];
    final results = await sql.batchRows([
      sql.database
          .prepare(
            '''SELECT user_id, token_hash, created_at, expires_at FROM $table
               WHERE token_hash = ? AND expires_at > ?''',
          )
          .bind(values),
      sql.database
          .prepare('DELETE FROM $table WHERE token_hash = ? AND expires_at > ?')
          .bind(values),
    ]);
    if ((results.last.meta?.changes ?? 0) != 1 ||
        results.first.results.isEmpty) {
      return null;
    }
    return _decodePasswordResetToken(results.first.results.single);
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await sql.run('DELETE FROM $table WHERE user_id = ?', [userId.trim()]);
  }
}

final class _D1JwtVersions implements AuthJwtVersionStore {
  _D1JwtVersions(this.sql, this.schema);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  String get table => schema.table('jwt_versions');

  @override
  Future<int> current(String userId) async {
    final id = _required(userId, 'userId');
    return await sql.first<int>(
          'SELECT version FROM $table WHERE user_id = ?',
          [id],
          (row) => (row['version'] as num).toInt(),
        ) ??
        0;
  }

  @override
  Future<int> rotate(String userId) async {
    final id = _required(userId, 'userId');
    final results = await sql.batchRows([
      sql.database
          .prepare('''INSERT INTO $table (user_id, version) VALUES (?, 1)
               ON CONFLICT(user_id) DO UPDATE SET version = version + 1''')
          .bind([id]),
      sql.database.prepare('SELECT version FROM $table WHERE user_id = ?').bind(
        [id],
      ),
    ]);
    final rows = results.last.results;
    if (rows.isEmpty) throw StateError('D1 JWT rotation returned no row.');
    return (rows.single['version'] as num).toInt();
  }
}

final class _D1VerificationTokens extends AuthVerificationTokenStore
    implements AuthVerificationTokenConditionalDeleteStore {
  _D1VerificationTokens(this.sql, this.schema, this.clock);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  String get table => schema.table('verification_tokens');

  @override
  Future<void> save(AuthVerificationToken token) async {
    if (token.identifier.trim().isEmpty || token.token.trim().isEmpty) {
      throw ArgumentError('Verification token fields must be non-empty.');
    }
    if (!clock().toUtc().isBefore(token.expiresAt.toUtc())) return;
    await sql.run(
      '''INSERT INTO $table (identifier, token_hash, expires_at, metadata)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(identifier, token_hash) DO UPDATE SET
           expires_at = excluded.expires_at, metadata = excluded.metadata''',
      [
        token.identifier,
        hashOpaqueToken(token.token),
        _date(token.expiresAt),
        jsonEncode(token.metadata),
      ],
    );
  }

  @override
  Future<AuthVerificationToken?> consume(
    String identifier,
    String token,
  ) async {
    final digest = hashOpaqueToken(token);
    final values = [identifier, digest, _date(clock())];
    final results = await sql.batchRows([
      sql.database
          .prepare('''SELECT expires_at, metadata FROM $table
               WHERE identifier = ? AND token_hash = ? AND expires_at > ?''')
          .bind(values),
      sql.database
          .prepare('''DELETE FROM $table
               WHERE identifier = ? AND token_hash = ? AND expires_at > ?''')
          .bind(values),
    ]);
    if ((results.last.meta?.changes ?? 0) != 1 ||
        results.first.results.isEmpty) {
      return null;
    }
    final row = results.first.results.single;
    return AuthVerificationToken(
      identifier: identifier,
      token: token,
      expiresAt: DateTime.parse(row['expires_at']! as String),
      metadata: _jsonMap(row['metadata']),
    );
  }

  @override
  Future<void> delete(String identifier) async {
    await sql.run('DELETE FROM $table WHERE identifier = ?', [identifier]);
  }

  @override
  Future<bool> deleteToken(String identifier, String token) async =>
      (await sql.run(
        'DELETE FROM $table WHERE identifier = ? AND token_hash = ?',
        [identifier, hashOpaqueToken(token)],
      )).meta?.changes ==
      1;
}

final class _D1EmailChangeTokens
    implements
        AuthEmailChangeTokenStore,
        AuthEmailChangeTokenConditionalDeleteStore {
  _D1EmailChangeTokens(this.sql, this.schema, this.clock);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  String get table => schema.table('email_change_tokens');

  @override
  Future<void> save(AuthEmailChangeToken token) async {
    final id = _required(token.userId, 'token.userId');
    final email = _email(token.newEmail);
    await sql.run(
      '''INSERT INTO $table (user_id, token_hash, new_email, expires_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET token_hash = excluded.token_hash,
           new_email = excluded.new_email, expires_at = excluded.expires_at''',
      [id, hashOpaqueToken(token.token), email, _date(token.expiresAt)],
    );
  }

  @override
  Future<AuthEmailChangeToken?> consume(String token) async {
    final digest = hashOpaqueToken(token);
    final values = [digest, _date(clock())];
    final results = await sql.batchRows([
      sql.database
          .prepare('''SELECT user_id, new_email, expires_at FROM $table
               WHERE token_hash = ? AND expires_at > ?''')
          .bind(values),
      sql.database
          .prepare('DELETE FROM $table WHERE token_hash = ? AND expires_at > ?')
          .bind(values),
    ]);
    if ((results.last.meta?.changes ?? 0) != 1 ||
        results.first.results.isEmpty) {
      return null;
    }
    final row = results.first.results.single;
    return AuthEmailChangeToken(
      userId: row['user_id']! as String,
      newEmail: row['new_email']! as String,
      token: token,
      expiresAt: DateTime.parse(row['expires_at']! as String),
    );
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await sql.run('DELETE FROM $table WHERE user_id = ?', [userId.trim()]);
  }

  @override
  Future<bool> deleteTokenForUser(String userId, String token) async =>
      (await sql.run(
        'DELETE FROM $table WHERE user_id = ? AND token_hash = ?',
        [userId.trim(), hashOpaqueToken(token)],
      )).meta?.changes ==
      1;
}

final class _D1OAuthChallenges implements AuthOAuthChallengeStore {
  _D1OAuthChallenges(this.sql, this.schema, this.clock);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  String get table => schema.table('oauth_challenges');

  @override
  Future<void> save(AuthOAuthChallenge challenge) async {
    if (!challenge.isActive(now: clock())) {
      throw ArgumentError.value(challenge.expiresAt, 'challenge.expiresAt');
    }
    await sql.run(
      '''INSERT INTO $table (provider_id, state_hash, expires_at, payload)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(provider_id, state_hash) DO UPDATE SET
           expires_at = excluded.expires_at, payload = excluded.payload''',
      [
        _required(challenge.providerId, 'providerId'),
        hashOpaqueToken(_required(challenge.state, 'state')),
        _date(challenge.expiresAt),
        jsonEncode({
          'codeVerifier': challenge.codeVerifier,
          'nonce': challenge.nonce,
          'callbackUrl': challenge.callbackUrl,
        }),
      ],
    );
  }

  @override
  Future<AuthOAuthChallenge?> consume(String providerId, String state) async {
    final digest = hashOpaqueToken(state);
    final values = [providerId, digest, _date(clock())];
    final results = await sql.batchRows([
      sql.database
          .prepare('''SELECT expires_at, payload FROM $table
               WHERE provider_id = ? AND state_hash = ? AND expires_at > ?''')
          .bind(values),
      sql.database
          .prepare(
            '''DELETE FROM $table WHERE provider_id = ? AND state_hash = ?
               AND expires_at > ?''',
          )
          .bind(values),
    ]);
    if ((results.last.meta?.changes ?? 0) != 1 ||
        results.first.results.isEmpty) {
      return null;
    }
    final row = results.first.results.single;
    final payload = _jsonMap(row['payload']);
    return AuthOAuthChallenge(
      providerId: providerId,
      state: state,
      expiresAt: DateTime.parse(row['expires_at']! as String),
      codeVerifier: payload['codeVerifier']?.toString(),
      nonce: payload['nonce']?.toString(),
      callbackUrl: payload['callbackUrl']?.toString(),
    );
  }
}

final class _D1DeviceAuthorizations
    implements AuthDeviceAuthorizationStore, AuthUserDeletionPlanFactory {
  _D1DeviceAuthorizations(this.sql, this.schema, this.clock);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  String get table => schema.table('device_authorizations');

  @override
  AuthUserDeletionPlan createDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  }) {
    if (domain is! CloudflareD1UserDeletionDomain) {
      throw StateError('Device authorization received a foreign D1 domain.');
    }
    return CloudflareD1UserDeletionPlan(
      domain: domain,
      userId: user.id,
      namespace: namespace,
      statements: [
        CloudflareD1UserDeletionStatement(
          sql: 'DELETE FROM $table WHERE user_id = ? AND {{guard}}',
          parameters: [user.id],
        ),
      ],
    );
  }

  @override
  Future<AuthDeviceAuthorization> create(
    AuthDeviceAuthorization authorization,
  ) async {
    await sql.run('''INSERT INTO $table
         (device_code_hash, user_code_hash, user_id, status, expires_at, payload)
         VALUES (?, ?, ?, ?, ?, ?)''', _deviceValues(authorization));
    return authorization;
  }

  @override
  Future<AuthDeviceAuthorizationPollResult> poll(
    String deviceCodeHash, {
    DateTime? now,
  }) async {
    final current = (now ?? clock()).toUtc();
    final hash = deviceCodeHash.trim();
    final currentValue = _date(current);
    final results = await sql.batchRows([
      sql.database
          .prepare('SELECT payload FROM $table WHERE device_code_hash = ?')
          .bind([hash]),
      sql.database
          .prepare('''UPDATE $table SET payload = json_set(
                 payload,
                 '\$.last_polled_at', ?,
                 '\$.interval_seconds',
                 CASE
                   WHEN json_extract(payload, '\$.last_polled_at') IS NOT NULL
                     AND (julianday(?) - julianday(
                       json_extract(payload, '\$.last_polled_at')
                     )) * 86400 < json_extract(payload, '\$.interval_seconds')
                   THEN json_extract(payload, '\$.interval_seconds') + 5
                   ELSE json_extract(payload, '\$.interval_seconds')
                 END
               )
               WHERE device_code_hash = ?
                 AND status IN ('pending', 'approved') AND expires_at > ?''')
          .bind([currentValue, currentValue, hash, currentValue]),
    ]);
    final rows = results.first.results;
    final existing = rows.isEmpty
        ? null
        : _decodeDeviceAuthorization(rows.single);
    if (existing == null) {
      return const AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.invalid,
      );
    }
    if (existing.isExpired(now: current)) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.expired,
        existing,
      );
    }
    if (existing.status == AuthDeviceAuthorizationStatus.denied) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.denied,
        existing,
      );
    }
    if (existing.status == AuthDeviceAuthorizationStatus.consumed) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.consumed,
        existing,
      );
    }
    final previous = existing.lastPolledAt;
    final isSlowDown =
        previous != null && current.difference(previous) < existing.interval;
    final polled = existing.copyWith(
      lastPolledAt: current,
      interval: isSlowDown
          ? existing.interval + const Duration(seconds: 5)
          : existing.interval,
    );
    if (isSlowDown) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.slowDown,
        polled,
      );
    }
    return AuthDeviceAuthorizationPollResult(
      existing.status == AuthDeviceAuthorizationStatus.approved
          ? AuthDeviceAuthorizationPollStatus.approved
          : AuthDeviceAuthorizationPollStatus.pending,
      polled,
    );
  }

  @override
  Future<AuthDeviceAuthorization?> approve(
    String userCodeHash,
    String userId, {
    DateTime? now,
  }) async {
    final current = (now ?? clock()).toUtc();
    final codeHash = userCodeHash.trim();
    final id = _required(userId, 'userId');
    final timestamp = _date(current);
    final results = await sql.batchRows([
      sql.database
          .prepare('''UPDATE $table SET user_id = ?, status = 'approved',
               payload = json_set(payload, '\$.user_id', ?,
                 '\$.status', 'approved', '\$.approved_at', ?)
               WHERE user_code_hash = ? AND status = 'pending'
                 AND expires_at > ?''')
          .bind([id, id, timestamp, codeHash, timestamp]),
      sql.database
          .prepare('SELECT payload FROM $table WHERE user_code_hash = ?')
          .bind([codeHash]),
    ]);
    if ((results.first.meta?.changes ?? 0) != 1 ||
        results.last.results.isEmpty) {
      return null;
    }
    return _decodeDeviceAuthorization(results.last.results.single);
  }

  @override
  Future<AuthDeviceAuthorization?> deny(
    String userCodeHash, {
    DateTime? now,
  }) async {
    final current = (now ?? clock()).toUtc();
    final codeHash = userCodeHash.trim();
    final timestamp = _date(current);
    final results = await sql.batchRows([
      sql.database
          .prepare('''UPDATE $table SET status = 'denied',
               payload = json_set(payload, '\$.status', 'denied',
                 '\$.denied_at', ?)
               WHERE user_code_hash = ? AND status = 'pending'
                 AND expires_at > ?''')
          .bind([timestamp, codeHash, timestamp]),
      sql.database
          .prepare('SELECT payload FROM $table WHERE user_code_hash = ?')
          .bind([codeHash]),
    ]);
    if ((results.first.meta?.changes ?? 0) != 1 ||
        results.last.results.isEmpty) {
      return null;
    }
    return _decodeDeviceAuthorization(results.last.results.single);
  }

  @override
  Future<AuthDeviceAuthorizationIssuanceLeaseResult> beginIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    required DateTime leaseExpiresAt,
    DateTime? now,
  }) async {
    final current = (now ?? clock()).toUtc();
    final hash = deviceCodeHash.trim();
    final client = _required(clientId, 'clientId');
    final digest = _required(leaseDigest, 'leaseDigest');
    final timestamp = _date(current);
    final requestedExpiry = _date(leaseExpiresAt.toUtc());
    if (!leaseExpiresAt.toUtc().isAfter(current)) {
      return const AuthDeviceAuthorizationIssuanceLeaseResult(
        AuthDeviceAuthorizationIssuanceLeaseStatus.invalid,
      );
    }
    final results = await sql.batchRows([
      sql.database
          .prepare('''UPDATE $table SET issuance_lease_digest = ?,
               issuance_lease_expires_at =
                 CASE WHEN ? < expires_at THEN ? ELSE expires_at END,
               payload = json_set(payload,
                 '\$.issuance_lease_digest', ?,
                 '\$.issuance_lease_expires_at',
                   CASE WHEN ? < expires_at THEN ? ELSE expires_at END)
               WHERE device_code_hash = ? AND status = 'approved'
                 AND expires_at > ?
                 AND user_id IS NOT NULL
                 AND json_extract(payload, '\$.client_id') = ?
                 AND (issuance_lease_digest IS NULL
                   OR issuance_lease_expires_at <= ?)
               RETURNING payload''')
          .bind([
            digest,
            requestedExpiry,
            requestedExpiry,
            digest,
            requestedExpiry,
            requestedExpiry,
            hash,
            timestamp,
            client,
            timestamp,
          ]),
      sql.database
          .prepare('SELECT payload FROM $table WHERE device_code_hash = ?')
          .bind([hash]),
    ]);
    if (results.first.results.isNotEmpty) {
      final authorization = _decodeDeviceAuthorization(
        results.first.results.single,
      );
      final expiresAt = authorization.issuanceLeaseExpiresAt!;
      return AuthDeviceAuthorizationIssuanceLeaseResult(
        AuthDeviceAuthorizationIssuanceLeaseStatus.acquired,
        AuthDeviceAuthorizationIssuanceLease(
          authorization: authorization,
          leaseDigest: digest,
          expiresAt: expiresAt,
        ),
      );
    }
    if (results.last.results.isNotEmpty) {
      final authorization = _decodeDeviceAuthorization(
        results.last.results.single,
      );
      if (authorization.status == AuthDeviceAuthorizationStatus.approved &&
          authorization.clientId == client &&
          !authorization.isExpired(now: current) &&
          authorization.issuanceLeaseDigest != null &&
          authorization.issuanceLeaseExpiresAt?.toUtc().isAfter(current) ==
              true) {
        return const AuthDeviceAuthorizationIssuanceLeaseResult(
          AuthDeviceAuthorizationIssuanceLeaseStatus.busy,
        );
      }
    }
    return const AuthDeviceAuthorizationIssuanceLeaseResult(
      AuthDeviceAuthorizationIssuanceLeaseStatus.invalid,
    );
  }

  @override
  Future<bool> completeIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  }) async {
    final current = (now ?? clock()).toUtc();
    final timestamp = _date(current);
    final results = await sql.batchRows([
      sql.database
          .prepare('''UPDATE $table SET status = 'consumed',
               consumed_at = ?, issuance_lease_digest = NULL,
               issuance_lease_expires_at = NULL,
               payload = json_remove(json_set(payload,
                 '\$.status', 'consumed', '\$.consumed_at', ?),
                 '\$.issuance_lease_digest',
                 '\$.issuance_lease_expires_at')
               WHERE device_code_hash = ? AND status = 'approved'
                 AND expires_at > ? AND issuance_lease_expires_at > ?
                 AND issuance_lease_digest = ?
                 AND json_extract(payload, '\$.client_id') = ?
               RETURNING payload''')
          .bind([
            timestamp,
            timestamp,
            deviceCodeHash.trim(),
            timestamp,
            timestamp,
            leaseDigest.trim(),
            clientId.trim(),
          ]),
    ]);
    return results.single.results.length == 1;
  }

  @override
  Future<bool> releaseIssuance(
    String deviceCodeHash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  }) async {
    final results = await sql.batchRows([
      sql.database
          .prepare('''UPDATE $table SET issuance_lease_digest = NULL,
               issuance_lease_expires_at = NULL,
               payload = json_remove(payload,
                 '\$.issuance_lease_digest',
                 '\$.issuance_lease_expires_at')
               WHERE device_code_hash = ? AND status = 'approved'
                 AND issuance_lease_digest = ?
                 AND json_extract(payload, '\$.client_id') = ?
               RETURNING payload''')
          .bind([deviceCodeHash.trim(), leaseDigest.trim(), clientId.trim()]),
    ]);
    return results.single.results.length == 1;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await sql.run('DELETE FROM $table WHERE user_id = ?', [userId.trim()]);
  }
}

final class _D1EmailOtps
    implements AuthEmailOtpStore, AuthUserDeletionPlanFactory {
  _D1EmailOtps(this.sql, this.schema, this.clock);
  final _D1 sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  String get table => schema.table('email_otps');

  @override
  AuthUserDeletionPlan createDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  }) {
    if (domain is! CloudflareD1UserDeletionDomain) {
      throw StateError('Email OTP received a foreign D1 domain.');
    }
    final email = user.email;
    if (email == null || email.trim().isEmpty) {
      return AuthNoopUserDeletionPlan(
        domain: domain,
        userId: user.id,
        namespace: namespace,
      );
    }
    return CloudflareD1UserDeletionPlan(
      domain: domain,
      userId: user.id,
      namespace: namespace,
      statements: [
        CloudflareD1UserDeletionStatement(
          sql: 'DELETE FROM $table WHERE email = ? AND {{guard}}',
          parameters: [email],
        ),
      ],
    );
  }

  @override
  Future<void> save(AuthEmailOtp otp) async {
    await sql.run(
      '''INSERT INTO $table (email, type, code_hash, expires_at, payload)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(email, type) DO UPDATE SET code_hash = excluded.code_hash,
           expires_at = excluded.expires_at, payload = excluded.payload''',
      [
        _email(otp.email),
        otp.type.name,
        otp.codeHash,
        _date(otp.expiresAt),
        jsonEncode(otp.toStorageJson()),
      ],
    );
  }

  @override
  Future<AuthEmailOtpVerificationResult> verify(
    String email,
    AuthEmailOtpType type,
    String code, {
    DateTime? now,
  }) async {
    final normalizedEmail = _email(email);
    final current = (now ?? clock()).toUtc();
    final timestamp = _date(current);
    final candidate = hashAuthEmailOtpCode(code);
    final results = await sql.batchRows([
      sql.database
          .prepare('''UPDATE $table SET payload = json_set(
                 payload,
                 '\$.attempts', json_extract(payload, '\$.attempts') + 1,
                 '\$.consumed', CASE WHEN code_hash = ?
                   THEN json('true')
                   ELSE json_extract(payload, '\$.consumed') END
               )
               WHERE email = ? AND type = ? AND expires_at > ?
                 AND json_extract(payload, '\$.consumed') = 0
                 AND json_extract(payload, '\$.attempts')
                   < json_extract(payload, '\$.max_attempts')''')
          .bind([candidate, normalizedEmail, type.name, timestamp]),
      sql.database
          .prepare('SELECT payload FROM $table WHERE email = ? AND type = ?')
          .bind([normalizedEmail, type.name]),
    ]);
    final rows = results.last.results;
    final row = rows.isEmpty ? null : _decodeEmailOtp(rows.single);
    if (row == null || row.consumed) {
      if ((results.first.meta?.changes ?? 0) == 1 && row?.consumed == true) {
        return AuthEmailOtpVerificationResult(
          AuthEmailOtpVerificationStatus.verified,
          row,
        );
      }
      return const AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.invalid,
      );
    }
    if (row.isExpired(now: current)) {
      return AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.expired,
        row,
      );
    }
    if (row.attempts >= row.maxAttempts) {
      return AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.tooManyAttempts,
        row,
      );
    }
    final status = row.attempts >= row.maxAttempts
        ? AuthEmailOtpVerificationStatus.tooManyAttempts
        : AuthEmailOtpVerificationStatus.invalid;
    return AuthEmailOtpVerificationResult(status, row);
  }

  @override
  Future<void> deleteForEmail(String email) async {
    await sql.run('DELETE FROM $table WHERE email = ?', [_email(email)]);
  }
}

int _oauthChanges(CloudflareD1Result<Object?> result) {
  final changes = result.meta?.changes;
  if (changes == null) {
    throw StateError('D1 did not report OAuth statement changes.');
  }
  return changes;
}

void _validateOAuthClient(OAuthClient client) {
  _required(client.clientId, 'client.clientId');
  _required(client.clientSecretHash, 'client.clientSecretHash');
  _required(client.name, 'client.name');
  _required(client.tokenEndpointAuthMethod, 'client.tokenEndpointAuthMethod');
  if (client.redirectUris.isEmpty ||
      client.redirectUris.any((value) {
        final uri = Uri.tryParse(value);
        return uri == null ||
            !uri.isAbsolute ||
            uri.hasFragment ||
            uri.host.isEmpty;
      })) {
    throw ArgumentError('OAuth client redirect URIs must be absolute.');
  }
  if (client.grantTypes.isEmpty ||
      client.grantTypes.any((value) => value.trim().isEmpty) ||
      client.scopes.any((value) => value.trim().isEmpty)) {
    throw ArgumentError('OAuth client grants and scopes must be valid.');
  }
}

List<Object?> _oauthClientValues(OAuthClient client) => [
  client.clientId.trim(),
  client.clientSecretHash,
  client.name.trim(),
  client.description,
  jsonEncode(client.redirectUris),
  jsonEncode(client.grantTypes),
  jsonEncode(client.scopes),
  client.tokenEndpointAuthMethod,
  _nullableDate(client.createdAt),
  _nullableDate(client.updatedAt),
  client.enabled ? 1 : 0,
];

OAuthClient _decodeOAuthClient(Map<String, Object?> row) => OAuthClient(
  clientId: row['client_id']! as String,
  clientSecretHash: row['client_secret_hash']! as String,
  name: row['name']! as String,
  description: row['description']?.toString(),
  redirectUris: _decodeStringList(row['redirect_uris']),
  grantTypes: _decodeStringList(row['grant_types']),
  scopes: _decodeStringList(row['scopes']),
  tokenEndpointAuthMethod: row['token_endpoint_auth_method']! as String,
  createdAt: _optionalDate(row['created_at']),
  updatedAt: _optionalDate(row['updated_at']),
  enabled: (row['enabled'] as num).toInt() == 1,
);

void _validateD1OAuthAuthorizationCode(OAuthAuthorizationCode code) {
  _required(code.authorizationId, 'code.authorizationId');
  _required(code.codeHash, 'code.codeHash');
  _required(code.clientId, 'code.clientId');
  _required(code.userId, 'code.userId');
  _required(code.scope, 'code.scope');
  final redirect = Uri.tryParse(code.redirectUri);
  if (redirect == null ||
      !redirect.isAbsolute ||
      redirect.hasFragment ||
      redirect.host.isEmpty) {
    throw ArgumentError('OAuth redirect URI must be absolute.');
  }
  final challenge = code.codeChallenge;
  if ((challenge == null) != (code.codeChallengeMethod == null) ||
      challenge != null &&
          (challenge.trim().isEmpty || code.codeChallengeMethod != 'S256')) {
    throw ArgumentError('D1 OAuth authorization codes support only S256 PKCE.');
  }
  final createdAt = code.createdAt;
  if (createdAt != null && !code.expiresAt.toUtc().isAfter(createdAt.toUtc())) {
    throw ArgumentError(
      'OAuth authorization code expiry must follow creation.',
    );
  }
}

List<Object?> _oauthAuthorizationCodeValues(OAuthAuthorizationCode code) => [
  code.codeHash.trim(),
  code.authorizationId.trim(),
  code.clientId.trim(),
  code.userId.trim(),
  code.redirectUri,
  code.scope,
  _date(code.expiresAt),
  code.codeChallenge,
  code.codeChallengeMethod,
  code.nonce,
  _nullableDate(code.createdAt),
];

OAuthAuthorizationCode _decodeOAuthAuthorizationCode(
  Map<String, Object?> row,
) => OAuthAuthorizationCode(
  codeHash: row['code_hash']! as String,
  authorizationId: row['authorization_id']! as String,
  clientId: row['client_id']! as String,
  userId: row['user_id']! as String,
  redirectUri: row['redirect_uri']! as String,
  scope: row['scope']! as String,
  expiresAt: DateTime.parse(row['expires_at']! as String),
  codeChallenge: row['code_challenge']?.toString(),
  codeChallengeMethod: row['code_challenge_method']?.toString(),
  nonce: row['nonce']?.toString(),
  createdAt: _optionalDate(row['created_at']),
);

void _validateD1OAuthAccessToken(OAuthAccessToken token) {
  _required(token.tokenHash, 'token.tokenHash');
  _required(token.clientId, 'token.clientId');
  _required(token.userId, 'token.userId');
  _required(token.scope, 'token.scope');
  if (token.refreshTokenHash?.trim().isEmpty == true ||
      token.refreshTokenHash == null && token.refreshTokenExpiresAt != null ||
      token.refreshTokenUses < 0) {
    throw ArgumentError('OAuth refresh-token state is invalid.');
  }
  final issuedAt = token.issuedAt;
  if (issuedAt != null && !token.expiresAt.toUtc().isAfter(issuedAt.toUtc())) {
    throw ArgumentError('OAuth access-token expiry must follow issuance.');
  }
  final refreshExpiry = token.refreshTokenExpiresAt;
  if (refreshExpiry != null &&
      issuedAt != null &&
      !refreshExpiry.toUtc().isAfter(issuedAt.toUtc())) {
    throw ArgumentError('OAuth refresh-token expiry must follow issuance.');
  }
}

List<Object?> _oauthAccessTokenValues(OAuthAccessToken token) => [
  token.tokenHash.trim(),
  token.authorizationId?.trim(),
  token.clientId.trim(),
  token.userId.trim(),
  token.scope,
  _date(token.expiresAt),
  token.refreshTokenHash,
  _nullableDate(token.refreshTokenExpiresAt),
  token.refreshTokenUses,
  _nullableDate(token.issuedAt),
];

OAuthAccessToken _decodeOAuthAccessToken(Map<String, Object?> row) =>
    OAuthAccessToken(
      tokenHash: row['token_hash']! as String,
      authorizationId: row['authorization_id']?.toString(),
      clientId: row['client_id']! as String,
      userId: row['user_id']! as String,
      scope: row['scope']! as String,
      expiresAt: DateTime.parse(row['expires_at']! as String),
      refreshTokenHash: row['refresh_token_hash']?.toString(),
      refreshTokenExpiresAt: _optionalDate(row['refresh_token_expires_at']),
      refreshTokenUses: (row['refresh_token_uses'] as num).toInt(),
      issuedAt: _optionalDate(row['issued_at']),
    );

({String sql, List<Object?> values}) _d1OAuthBindingPredicate(
  OAuthAuthorizationCodeExchangeRequest request,
) {
  final expectedChallenge = request.codeVerifier == null
      ? null
      : _s256Challenge(request.codeVerifier!);
  return (
    sql: '''client_id = ? AND redirect_uri = ? AND expires_at > ? AND
      (code_challenge IS NULL OR
       (? IS NOT NULL AND code_challenge_method = 'S256' AND
        code_challenge = ?))''',
    values: <Object?>[
      request.clientId.trim(),
      request.redirectUri,
      _date(request.now),
      expectedChallenge,
      expectedChallenge,
    ],
  );
}

({String sql, List<Object?> values}) _d1OAuthCommitPredicate(
  OAuthAuthorizationCodeExchangeRequest request,
  String authorizationId,
  OAuthAccessToken token,
) {
  final binding = _d1OAuthBindingPredicate(request);
  return (
    sql: '''code_hash = ? AND authorization_id = ? AND ${binding.sql}
      AND user_id = ? AND scope = ?''',
    values: <Object?>[
      request.codeHash.trim(),
      authorizationId,
      ...binding.values,
      token.userId.trim(),
      token.scope,
    ],
  );
}

bool _d1OAuthBindingsMatch(
  OAuthAuthorizationCode code,
  OAuthAuthorizationCodeExchangeRequest request,
) {
  if (code.clientId != request.clientId.trim() ||
      code.redirectUri != request.redirectUri) {
    return false;
  }
  final challenge = code.codeChallenge;
  if (challenge == null) return true;
  final verifier = request.codeVerifier;
  return code.codeChallengeMethod == 'S256' &&
      verifier != null &&
      constantTimeStringEquals(_s256Challenge(verifier), challenge);
}

void _validatePreparedD1OAuthToken(
  OAuthAuthorizationCodeExchangeRequest request,
  String authorizationId,
  OAuthAccessToken token,
) {
  _required(request.codeHash, 'request.codeHash');
  _required(request.clientId, 'request.clientId');
  _required(request.redirectUri, 'request.redirectUri');
  _required(authorizationId, 'expectedAuthorizationId');
  _validateD1OAuthAccessToken(token);
  if (token.authorizationId != authorizationId ||
      token.clientId != request.clientId.trim() ||
      !token.expiresAt.toUtc().isAfter(request.now.toUtc())) {
    throw ArgumentError('Prepared OAuth token does not match the exchange.');
  }
}

String _s256Challenge(String verifier) => pkceS256CodeChallenge(verifier);

List<Object?> _scimConnectionValues(AuthScimManagedConnection value) => [
  value.id,
  value.tenantId,
  value.organizationId,
  value.provisioningDomainId,
  value.subjectId,
  value.name,
  _encodeScimScopes(value.scopes),
  _scimGrantedMask(value.scopes),
  _date(value.createdAt),
  _date(value.updatedAt),
  _nullableDate(value.disabledAt),
];

List<Object?> _scimCredentialValues(AuthScimCredentialRecord value) => [
  value.id,
  value.connectionId,
  value.tenantId,
  value.organizationId,
  value.name,
  value.keyPrefix,
  value.secretDigest,
  _encodeScimScopes(value.scopes),
  _scimExactMask(value.scopes),
  _date(value.createdAt),
  _date(value.updatedAt),
  _nullableDate(value.expiresAt),
  _nullableDate(value.lastUsedAt),
  _nullableDate(value.revokedAt),
];

AuthScimManagedConnection _decodeScimConnection(Map<String, Object?> row) =>
    AuthScimManagedConnection(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      organizationId: row['organization_id']! as String,
      provisioningDomainId: row['provisioning_domain_id']! as String,
      subjectId: row['subject_id']! as String,
      name: row['name']! as String,
      scopes: _decodeScimScopes(row['scopes']),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      disabledAt: _optionalDate(row['disabled_at']),
    );

AuthScimCredentialRecord _decodeScimCredential(Map<String, Object?> row) =>
    AuthScimCredentialRecord(
      id: row['id']! as String,
      connectionId: row['connection_id']! as String,
      tenantId: row['tenant_id']! as String,
      organizationId: row['organization_id']! as String,
      name: row['name']! as String,
      keyPrefix: row['key_prefix']! as String,
      secretDigest: row['secret_digest']! as String,
      scopes: _decodeScimScopes(row['scopes']),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      expiresAt: _optionalDate(row['expires_at']),
      lastUsedAt: _optionalDate(row['last_used_at']),
      revokedAt: _optionalDate(row['revoked_at']),
    );

_D1ScimReplay _decodeScimReplay(Map<String, Object?> row) => _D1ScimReplay(
  fingerprint: row['replay_fingerprint']! as String,
  connection: AuthScimManagedConnection(
    id: row['connection_id']! as String,
    tenantId: row['connection_tenant_id']! as String,
    organizationId: row['connection_organization_id']! as String,
    provisioningDomainId: row['connection_domain_id']! as String,
    subjectId: row['connection_subject_id']! as String,
    name: row['connection_name']! as String,
    scopes: _decodeScimScopes(row['connection_scopes']),
    createdAt: DateTime.parse(row['connection_created_at']! as String),
    updatedAt: DateTime.parse(row['connection_updated_at']! as String),
    disabledAt: _optionalDate(row['connection_disabled_at']),
  ),
  credential: AuthScimCredentialRecord(
    id: row['credential_id']! as String,
    connectionId: row['credential_connection_id']! as String,
    tenantId: row['credential_tenant_id']! as String,
    organizationId: row['credential_organization_id']! as String,
    name: row['credential_name']! as String,
    keyPrefix: row['credential_key_prefix']! as String,
    secretDigest: row['credential_secret_digest']! as String,
    scopes: _decodeScimScopes(row['credential_scopes']),
    createdAt: DateTime.parse(row['credential_created_at']! as String),
    updatedAt: DateTime.parse(row['credential_updated_at']! as String),
    expiresAt: _optionalDate(row['credential_expires_at']),
    lastUsedAt: _optionalDate(row['credential_last_used_at']),
    revokedAt: _optionalDate(row['credential_revoked_at']),
  ),
);

void _validateScimCredential(
  AuthScimManagedConnection connection,
  AuthScimCredentialRecord credential,
) {
  if (credential.connectionId != connection.id ||
      credential.tenantId != connection.tenantId ||
      credential.organizationId != connection.organizationId ||
      !authScimScopesAllow(connection.scopes, credential.scopes)) {
    throw const AuthScimConnectionStoreException(
      AuthScimConnectionStoreFailure.scopeMismatch,
    );
  }
}

String _encodeScimScopes(Iterable<AuthScimScope> scopes) {
  final values = scopes.map((scope) => scope.name).toList()..sort();
  return jsonEncode(values);
}

Set<AuthScimScope> _decodeScimScopes(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! List || decoded.isEmpty) {
    throw const FormatException('Invalid stored SCIM scopes.');
  }
  return Set<AuthScimScope>.unmodifiable(
    decoded.map((entry) => AuthScimScope.values.byName(entry.toString())),
  );
}

int _scimExactMask(Iterable<AuthScimScope> scopes) => scopes.fold<int>(
  0,
  (mask, scope) =>
      mask |
      switch (scope) {
        AuthScimScope.usersRead => 1,
        AuthScimScope.usersWrite => 2,
        AuthScimScope.groupsRead => 4,
        AuthScimScope.groupsWrite => 8,
      },
);

int _scimGrantedMask(Iterable<AuthScimScope> scopes) {
  var mask = _scimExactMask(scopes);
  if ((mask & 2) != 0) mask |= 1;
  if ((mask & 8) != 0) mask |= 4;
  return mask;
}

final class _D1ScimReplay {
  const _D1ScimReplay({
    required this.fingerprint,
    required this.connection,
    required this.credential,
  });

  final String fingerprint;
  final AuthScimManagedConnection connection;
  final AuthScimCredentialRecord credential;
}

List<String> _decodeStringList(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  return decoded is List
      ? decoded.map((item) => item.toString()).toList(growable: false)
      : const [];
}

DateTime? _optionalDate(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc();

String? _nullableDate(DateTime? value) => value == null ? null : _date(value);

String _required(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must be non-empty');
  }
  return normalized;
}

String _email(String value) => _required(value, 'email').toLowerCase();
String? _nullableEmail(String? value) => value == null ? null : _email(value);
String _date(DateTime value) => value.toUtc().toIso8601String();

String _encodeUser(AuthUser user) => jsonEncode({
  'id': user.id,
  'email': user.email,
  'name': user.name,
  'image': user.image,
  'roles': user.roles,
  'isAnonymous': user.isAnonymous,
  'attributes': user.attributes,
});

Map<String, dynamic> _jsonMap(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  return decoded is Map
      ? <String, dynamic>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        }
      : <String, dynamic>{};
}

AuthUser _decodeUser(Map<String, Object?> row) {
  final value = _jsonMap(row['payload']);
  return AuthUser(
    id: value['id']?.toString() ?? '',
    email: value['email']?.toString(),
    name: value['name']?.toString(),
    image: value['image']?.toString(),
    roles:
        (value['roles'] as List?)
            ?.map((role) => role.toString())
            .toList(growable: false) ??
        const [],
    isAnonymous: value['isAnonymous'] == true,
    attributes: _jsonMap(value['attributes']),
  );
}

AuthAccount _decodeAccount(Map<String, Object?> row) {
  final value = _jsonMap(row['payload']);
  return AuthAccount(
    providerId: value['provider_id']?.toString() ?? '',
    providerAccountId: value['provider_account_id']?.toString() ?? '',
    userId: value['user_id']?.toString(),
    accessToken: value['access_token']?.toString(),
    refreshToken: value['refresh_token']?.toString(),
    expiresAt: DateTime.tryParse(value['expires_at']?.toString() ?? ''),
    metadata: _jsonMap(value['metadata']),
  );
}

List<Object?> _credentialValues(AuthPasswordCredential value) => [
  value.id,
  value.userId,
  value.identifier.trim().toLowerCase(),
  value.passwordHash,
  _date(value.createdAt),
  _date(value.updatedAt),
  value.enabled ? 1 : 0,
];

AuthPasswordCredential _decodeCredential(Map<String, Object?> row) =>
    AuthPasswordCredential(
      id: row['id']! as String,
      userId: row['user_id']! as String,
      identifier: row['identifier']! as String,
      passwordHash: row['password_hash']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      enabled: (row['enabled'] as num).toInt() == 1,
    );

List<Object?> _sessionValues(AuthSessionRecord value) => [
  value.id,
  value.tokenHash,
  value.userId,
  _date(value.createdAt),
  _date(value.expiresAt),
  _date(value.lastUsedAt),
  value.revokedAt == null ? null : _date(value.revokedAt!),
  jsonEncode(value.toStorageJson()),
];

AuthSessionRecord _decodeSession(Map<String, Object?> row) {
  final payload = _jsonMap(row['payload']);
  return AuthSessionRecord(
    id: row['id']! as String,
    tokenHash: row['token_hash']! as String,
    userId: row['user_id']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    expiresAt: DateTime.parse(row['expires_at']! as String),
    lastUsedAt: DateTime.parse(row['last_used_at']! as String),
    revokedAt: DateTime.tryParse(row['revoked_at']?.toString() ?? ''),
    authenticationMethod: payload['authentication_method']?.toString() ?? '',
    ipAddress: payload['ip_address']?.toString(),
    userAgent: payload['user_agent']?.toString(),
    impersonatedBy: payload['impersonated_by']?.toString(),
  );
}

AuthPasswordResetToken _decodePasswordResetToken(Map<String, Object?> row) =>
    AuthPasswordResetToken(
      userId: row['user_id']! as String,
      tokenHash: row['token_hash']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      expiresAt: DateTime.parse(row['expires_at']! as String),
    );

List<Object?> _deviceValues(AuthDeviceAuthorization value) => [
  value.deviceCodeHash,
  value.userCodeHash,
  value.userId,
  value.status.name,
  _date(value.expiresAt),
  jsonEncode(value.toStorageJson()),
];

AuthDeviceAuthorization _decodeDeviceAuthorization(Map<String, Object?> row) {
  final value = _jsonMap(row['payload']);
  DateTime? optionalDate(String key) =>
      DateTime.tryParse(value[key]?.toString() ?? '');
  return AuthDeviceAuthorization(
    id: value['id']?.toString() ?? '',
    deviceCodeHash: value['device_code_hash']?.toString() ?? '',
    userCodeHash: value['user_code_hash']?.toString() ?? '',
    clientId: value['client_id']?.toString() ?? '',
    scopes:
        (value['scopes'] as List?)?.map((item) => item.toString()).toList() ??
        const [],
    createdAt: DateTime.parse(value['created_at']! as String),
    expiresAt: DateTime.parse(value['expires_at']! as String),
    interval: Duration(seconds: (value['interval_seconds'] as num).toInt()),
    status: AuthDeviceAuthorizationStatus.values.byName(
      value['status']! as String,
    ),
    userId: value['user_id']?.toString(),
    approvedAt: optionalDate('approved_at'),
    deniedAt: optionalDate('denied_at'),
    lastPolledAt: optionalDate('last_polled_at'),
    issuanceLeaseDigest: value['issuance_lease_digest']?.toString(),
    issuanceLeaseExpiresAt: optionalDate('issuance_lease_expires_at'),
    consumedAt: optionalDate('consumed_at'),
  );
}

AuthEmailOtp _decodeEmailOtp(Map<String, Object?> row) {
  final value = _jsonMap(row['payload']);
  return AuthEmailOtp(
    id: value['id']! as String,
    email: value['email']! as String,
    codeHash: value['code_hash']! as String,
    type: AuthEmailOtpType.values.byName(value['type']! as String),
    createdAt: DateTime.parse(value['created_at']! as String),
    expiresAt: DateTime.parse(value['expires_at']! as String),
    maxAttempts: (value['max_attempts'] as num).toInt(),
    attempts: (value['attempts'] as num).toInt(),
    consumed: value['consumed'] == true,
  );
}
