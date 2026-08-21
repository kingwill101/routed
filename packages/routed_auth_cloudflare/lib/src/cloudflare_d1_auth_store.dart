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
        AuthAnonymousAccountMutationStore,
        AuthMagicLinkBackend,
        AuthEmailOtpBackend,
        AuthPhoneNumberBackend,
        AuthWebAuthnStoreCapabilities,
        AuthWebAuthnUserDeletionPlanFactory,
        AuthUserDeletionCoordinatorHost,
        AuthOAuthAccountMutationStore,
        AuthAuthenticationMethodTopologyStore {
  CloudflareD1AuthStore(
    CloudflareD1Database database, {
    this.schema = const CloudflareD1AuthSchema(),
    this.scimReplayTtl = const Duration(days: 1),
    this.anonymousReplayTtl = const Duration(days: 1),
    this.anonymousMaxReceipts = 10000,
    this.apiKeyMaxRecords = 10000,
    this.webAuthnChallengeMaxRecords = 10000,
    this.webAuthnAuthenticatorMaxRecords = 10000,
    this.phoneNumberMaxVerifications = 2048,
    DateTime Function()? clock,
  }) : _database = database,
       _clock = clock ?? DateTime.now {
    if (anonymousReplayTtl <= Duration.zero) {
      throw ArgumentError.value(
        anonymousReplayTtl,
        'anonymousReplayTtl',
        'must be positive',
      );
    }
    if (anonymousMaxReceipts <= 0) {
      throw ArgumentError.value(
        anonymousMaxReceipts,
        'anonymousMaxReceipts',
        'must be positive',
      );
    }
    if (apiKeyMaxRecords <= 0) {
      throw ArgumentError.value(
        apiKeyMaxRecords,
        'apiKeyMaxRecords',
        'must be positive',
      );
    }
    if (webAuthnChallengeMaxRecords <= 0) {
      throw ArgumentError.value(
        webAuthnChallengeMaxRecords,
        'webAuthnChallengeMaxRecords',
        'must be positive',
      );
    }
    if (webAuthnAuthenticatorMaxRecords <= 0) {
      throw ArgumentError.value(
        webAuthnAuthenticatorMaxRecords,
        'webAuthnAuthenticatorMaxRecords',
        'must be positive',
      );
    }
    if (phoneNumberMaxVerifications <= 0) {
      throw ArgumentError.value(
        phoneNumberMaxVerifications,
        'phoneNumberMaxVerifications',
        'must be positive',
      );
    }
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
    phoneNumbers = CloudflareD1PhoneNumberStore._(
      sql,
      schema,
      _clock,
      phoneNumberMaxVerifications,
    );
    final deletionCoordinator = CloudflareD1UserDeletionCoordinator._(
      database: database,
      sql: sql,
      schema: schema,
      clock: _clock,
    );
    _deletionCoordinator = deletionCoordinator;
    webAuthnChallenges = CloudflareD1WebAuthnChallengeStore._(
      sql,
      schema,
      _clock,
      webAuthnChallengeMaxRecords,
    );
    webAuthnAuthenticators = CloudflareD1WebAuthnAuthenticatorStore._(
      sql,
      schema,
      _clock,
      webAuthnAuthenticatorMaxRecords,
      this,
    );
    apiKeys = CloudflareD1AuthApiKeyStore._(
      sql,
      schema,
      deletionCoordinator.domain,
      _clock,
      apiKeyMaxRecords,
      this,
    );
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
    Duration anonymousReplayTtl = const Duration(days: 1),
    int anonymousMaxReceipts = 10000,
    int apiKeyMaxRecords = 10000,
    int webAuthnChallengeMaxRecords = 10000,
    int webAuthnAuthenticatorMaxRecords = 10000,
    int phoneNumberMaxVerifications = 2048,
    DateTime Function()? clock,
  }) async {
    await schema.migrate(database);
    return CloudflareD1AuthStore(
      database,
      schema: schema,
      scimReplayTtl: scimReplayTtl,
      anonymousReplayTtl: anonymousReplayTtl,
      anonymousMaxReceipts: anonymousMaxReceipts,
      apiKeyMaxRecords: apiKeyMaxRecords,
      webAuthnChallengeMaxRecords: webAuthnChallengeMaxRecords,
      webAuthnAuthenticatorMaxRecords: webAuthnAuthenticatorMaxRecords,
      phoneNumberMaxVerifications: phoneNumberMaxVerifications,
      clock: clock,
    );
  }

  final CloudflareD1Database _database;
  late final _D1 _sql;
  final DateTime Function() _clock;
  final CloudflareD1AuthSchema schema;
  final Duration scimReplayTtl;
  final Duration anonymousReplayTtl;
  final int anonymousMaxReceipts;
  final int apiKeyMaxRecords;
  final int webAuthnChallengeMaxRecords;
  final int webAuthnAuthenticatorMaxRecords;
  final int phoneNumberMaxVerifications;
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
          : identical(binding.authenticationMethodStore, phoneNumbers)
          ? const {AuthAuthenticationMethodKind.phone}
          : identical(binding.authenticationMethodStore, apiKeys)
          ? const {AuthAuthenticationMethodKind.apiKey}
          : identical(binding.authenticationMethodStore, webAuthnAuthenticators)
          ? const {AuthAuthenticationMethodKind.passkey}
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
    var hasApiKeyFallback = false;
    var hasPasskeyFallback = false;
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
          hasPasskeyFallback = true;
        case AuthAuthenticationMethodKind.apiKey:
          hasApiKeyFallback = true;
        case AuthAuthenticationMethodKind.phone:
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
    if (hasApiKeyFallback) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('api_keys')}
           WHERE user_id = ? AND revoked_at IS NULL
             AND (expires_at IS NULL OR expires_at > ?))''');
      fallbackValues.addAll([userId, _date(_clock())]);
    }
    if (hasPasskeyFallback) {
      clauses.add(
        '''EXISTS (SELECT 1 FROM ${schema.table('webauthn_authenticators')}
           WHERE user_id = ?)''',
      );
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

  String get _anonymousGuards => schema.table('anonymous_mutation_guards');
  String get _anonymousReceipts => schema.table('anonymous_mutation_receipts');

  @override
  Future<AuthAnonymousMutationResult> createAnonymousAccount(
    AuthAnonymousCreateAccountCommand command,
  ) async {
    validateAuthAnonymousUser(command.user);
    validateAuthUserForPersistence(command.user);
    final now = _clock().toUtc();
    final operationIdHash = hashOpaqueToken(command.operationId);
    final subjectUserIdHash = hashOpaqueToken(command.user.id);
    final fingerprint = _anonymousCreateFingerprint(command);
    final usersTable = schema.table('users');
    final deletionReceipts = schema.table('deletion_receipts');
    final creationGuard =
        '''EXISTS (
      SELECT 1 FROM $_anonymousGuards
      WHERE operation_id_hash = ? AND fingerprint_hash = ?
        AND subject_user_id_hash = ?
    )''';
    final creationGuardValues = [
      operationIdHash,
      fingerprint,
      subjectUserIdHash,
    ];
    try {
      final results = await _sql.batch([
        _database
            .prepare('''INSERT INTO $_anonymousGuards
                 (operation_id_hash, fingerprint_hash, subject_user_id_hash,
                  created_at)
                 SELECT ?, ?, ?, ?
                 WHERE NOT EXISTS (
                   SELECT 1 FROM $_anonymousReceipts
                   WHERE operation_id_hash = ?
                 )
                   AND NOT EXISTS (
                     SELECT 1 FROM $usersTable WHERE id = ?
                   )
                   AND NOT EXISTS (
                     SELECT 1 FROM $deletionReceipts WHERE user_id_hash = ?
                   )''')
            .bind([
              operationIdHash,
              fingerprint,
              subjectUserIdHash,
              _date(now),
              operationIdHash,
              command.user.id,
              subjectUserIdHash,
            ]),
        ..._anonymousReceiptRetentionStatements(
          now,
          guard: creationGuard,
          guardValues: creationGuardValues,
        ),
        _database
            .prepare('''INSERT INTO $usersTable (id, email, payload)
                 SELECT ?, NULL, ?
                 WHERE $creationGuard''')
            .bind([
              command.user.id,
              _encodeUser(command.user),
              ...creationGuardValues,
            ]),
        _database
            .prepare('''INSERT INTO $_anonymousReceipts
                 (operation_id_hash, operation_type, fingerprint_hash,
                 subject_user_id_hash, target_user_id_hash, created_at,
                  expires_at)
                 SELECT ?, 'create', ?, ?, NULL, ?, ?
                 WHERE $creationGuard''')
            .bind([
              ...creationGuardValues,
              _date(now),
              _date(now.add(anonymousReplayTtl)),
              operationIdHash,
              fingerprint,
              subjectUserIdHash,
            ]),
        _database
            .prepare(
              'DELETE FROM $_anonymousGuards WHERE operation_id_hash = ?',
            )
            .bind([operationIdHash]),
      ]);
      if ((results.first.meta?.changes ?? 0) == 1 &&
          (results[3].meta?.changes ?? 0) == 1 &&
          (results[4].meta?.changes ?? 0) == 1 &&
          (results.last.meta?.changes ?? 0) == 1) {
        return AuthAnonymousMutationResult(
          AuthAnonymousMutationStatus.applied,
          user: command.user,
        );
      }
    } catch (error, stackTrace) {
      final replay = await _readAnonymousReplay(
        operationIdHash: operationIdHash,
        fingerprint: fingerprint,
        createUserId: command.user.id,
        now: now,
      );
      if (replay != null) return replay;
      Error.throwWithStackTrace(error, stackTrace);
    }
    final replay = await _readAnonymousReplay(
      operationIdHash: operationIdHash,
      fingerprint: fingerprint,
      createUserId: command.user.id,
      now: now,
    );
    if (replay != null) return replay;
    throw StateError('D1 anonymous account creation was not committed.');
  }

  @override
  Future<AuthAnonymousMutationResult> deleteAnonymousAccount(
    AuthAnonymousDeleteAccountCommand command,
  ) => _removeAnonymousAccount(
    operationId: command.operationId,
    operationType: 'delete',
    anonymousUserId: command.userId,
  );

  @override
  Future<AuthAnonymousMutationResult> completeAnonymousAccountUpgrade(
    AuthAnonymousCompleteUpgradeCommand command,
  ) => _removeAnonymousAccount(
    operationId: command.operationId,
    operationType: 'upgrade',
    anonymousUserId: command.anonymousUserId,
    targetUserId: command.targetUserId,
  );

  Future<AuthAnonymousMutationResult> _removeAnonymousAccount({
    required String operationId,
    required String operationType,
    required String anonymousUserId,
    String? targetUserId,
  }) async {
    final now = _clock().toUtc();
    final operationIdHash = hashOpaqueToken(operationId);
    final subjectUserIdHash = hashOpaqueToken(anonymousUserId);
    final targetUserIdHash = targetUserId == null
        ? null
        : hashOpaqueToken(targetUserId);
    final fingerprint = hashOpaqueToken(
      targetUserId == null
          ? 'delete:$anonymousUserId'
          : 'upgrade:$anonymousUserId:$targetUserId',
    );
    final replay = await _readAnonymousReplay(
      operationIdHash: operationIdHash,
      fingerprint: fingerprint,
      now: now,
    );
    if (replay != null) return replay;

    final source = await users.findById(anonymousUserId);
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

    late final bool deleted;
    try {
      deleted = await _deletionCoordinator._delete(
        userId: anonymousUserId,
        plans: null,
        confirmationToken: null,
        requireAnonymous: true,
        completion: (guard, guardValues, deletedAt) => [
          ..._anonymousReceiptRetentionStatements(
            deletedAt,
            guard: guard,
            guardValues: guardValues,
          ),
          _database
              .prepare('''INSERT INTO $_anonymousReceipts
                 (operation_id_hash, operation_type, fingerprint_hash,
                  subject_user_id_hash, target_user_id_hash, created_at,
                  expires_at)
                 SELECT ?, ?, ?, ?, ?, ?, ? WHERE $guard''')
              .bind([
                operationIdHash,
                operationType,
                fingerprint,
                subjectUserIdHash,
                targetUserIdHash,
                _date(deletedAt),
                _date(deletedAt.add(anonymousReplayTtl)),
                ...guardValues,
              ]),
        ],
      );
    } catch (error, stackTrace) {
      final conflict = await _readAnonymousReplay(
        operationIdHash: operationIdHash,
        fingerprint: fingerprint,
        now: now,
      );
      if (conflict != null) return conflict;
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (deleted) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.applied,
      );
    }
    final concurrentReplay = await _readAnonymousReplay(
      operationIdHash: operationIdHash,
      fingerprint: fingerprint,
      now: now,
    );
    if (concurrentReplay != null) return concurrentReplay;
    final current = await users.findById(anonymousUserId);
    if (current == null) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notFound,
      );
    }
    if (!current.isAnonymous) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.notAnonymous,
      );
    }
    throw StateError('D1 anonymous account removal was not committed.');
  }

  Iterable<CloudflareD1PreparedStatement> _anonymousReceiptRetentionStatements(
    DateTime now, {
    String? guard,
    List<Object?> guardValues = const [],
  }) sync* {
    final predicate = guard == null ? '' : ' AND $guard';
    yield _database
        .prepare(
          'DELETE FROM $_anonymousReceipts '
          'WHERE expires_at <= ?$predicate',
        )
        .bind([_date(now), ...guardValues]);
    yield _database
        .prepare('''DELETE FROM $_anonymousReceipts
             WHERE operation_id_hash IN (
               SELECT operation_id_hash FROM $_anonymousReceipts
               ORDER BY created_at DESC, operation_id_hash DESC
               LIMIT -1 OFFSET ?
             )$predicate''')
        .bind([anonymousMaxReceipts - 1, ...guardValues]);
  }

  Future<AuthAnonymousMutationResult?> _readAnonymousReplay({
    required String operationIdHash,
    required String fingerprint,
    required DateTime now,
    String? createUserId,
  }) async {
    final receipt = await _sql.first(
      '''SELECT fingerprint_hash FROM $_anonymousReceipts
         WHERE operation_id_hash = ? AND expires_at > ?''',
      [operationIdHash, _date(now)],
      (row) => row['fingerprint_hash']?.toString() ?? '',
    );
    if (receipt == null) return null;
    if (!constantTimeStringEquals(receipt, fingerprint)) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.replayMismatch,
      );
    }
    if (createUserId == null) {
      return const AuthAnonymousMutationResult(
        AuthAnonymousMutationStatus.replayed,
      );
    }
    final user = await users.findById(createUserId);
    if (user == null || !user.isAnonymous) {
      throw StateError('D1 anonymous creation replay is unavailable.');
    }
    return AuthAnonymousMutationResult(
      AuthAnonymousMutationStatus.replayed,
      user: user,
    );
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
    var hasApiKeyFallback = false;
    var hasPasskeyFallback = false;
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
          hasPasskeyFallback = true;
        case AuthAuthenticationMethodKind.apiKey:
          hasApiKeyFallback = true;
        case AuthAuthenticationMethodKind.phone:
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
    if (hasApiKeyFallback) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('api_keys')}
           WHERE user_id = ? AND revoked_at IS NULL
             AND (expires_at IS NULL OR expires_at > ?))''');
      fallbackValues.addAll([userId, _date(_clock())]);
    }
    if (hasPasskeyFallback) {
      clauses.add(
        '''EXISTS (SELECT 1 FROM ${schema.table('webauthn_authenticators')}
           WHERE user_id = ?)''',
      );
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

  /// Digest-only, bounded phone verification persistence in this D1 domain.
  late final CloudflareD1PhoneNumberStore phoneNumbers;

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
  @override
  AuthEmailOtpStore get emailOtpStore => emailOtps;

  @override
  Future<AuthPhoneNumberIssueResult> issuePhoneNumberCode(
    AuthPhoneNumberIssueCodeCommand command,
  ) => phoneNumbers.issuePhoneNumberCode(command);

  @override
  Future<AuthPhoneNumberVerifyResult> verifyPhoneNumberCode(
    AuthPhoneNumberVerifyCodeCommand command,
  ) => phoneNumbers.verifyPhoneNumberCode(command);

  @override
  Future<AuthPhoneNumberIdentity?> findPhoneNumberIdentity(
    String phoneNumber,
  ) => phoneNumbers.findPhoneNumberIdentity(phoneNumber);

  @override
  Future<AuthPhoneNumberIdentity?> findPhoneNumberIdentityForUser(
    String userId,
  ) => phoneNumbers.findPhoneNumberIdentityForUser(userId);

  @override
  Future<void> issueMagicLink(AuthMagicLinkIssueCommand command) async {
    final record = command.record;
    await _sql.run(
      '''INSERT INTO ${schema.table('magic_links')}
         (provider_id, email, token_hash, issued_at, expires_at,
          consumption_marker)
         VALUES (?, ?, ?, ?, ?, NULL)
         ON CONFLICT(provider_id, email) DO UPDATE SET
           token_hash = excluded.token_hash,
           issued_at = excluded.issued_at,
           expires_at = excluded.expires_at,
           consumption_marker = NULL''',
      [
        record.providerId,
        record.email,
        record.tokenHash,
        _date(record.issuedAt),
        _date(record.expiresAt),
      ],
    );
  }

  @override
  Future<AuthMagicLinkConsumeResult> consumeMagicLink(
    AuthMagicLinkConsumeCommand command,
  ) async {
    final links = schema.table('magic_links');
    final userTable = schema.table('users');
    final receipts = schema.table('deletion_receipts');
    final marker = secureRandomToken(length: 24);
    final candidate = _verifiedEmailUser(command.candidate);
    final timestamp = _date(command.now);
    final results = await _sql.batchRows([
      _sql.database
          .prepare('''SELECT token_hash, expires_at FROM $links
               WHERE provider_id = ? AND email = ?''')
          .bind([command.providerId, command.email]),
      _sql.database
          .prepare('''UPDATE $links SET consumption_marker = ?
               WHERE provider_id = ? AND email = ? AND token_hash = ?
                 AND expires_at > ? AND consumption_marker IS NULL''')
          .bind([
            marker,
            command.providerId,
            command.email,
            command.tokenHash,
            timestamp,
          ]),
      _sql.database
          .prepare('''INSERT INTO $userTable (id, email, payload)
               SELECT ?, ?, ? FROM $links
               WHERE provider_id = ? AND email = ?
                 AND consumption_marker = ?
                 AND NOT EXISTS (SELECT 1 FROM $userTable WHERE email = ?)
                 AND NOT EXISTS (SELECT 1 FROM $userTable WHERE id = ?)
                 AND NOT EXISTS (
                   SELECT 1 FROM $receipts WHERE user_id_hash = ?
                 )''')
          .bind([
            candidate.id,
            command.email,
            _encodeUser(candidate),
            command.providerId,
            command.email,
            marker,
            command.email,
            candidate.id,
            hashOpaqueToken(candidate.id),
          ]),
      _sql.database
          .prepare('''UPDATE $userTable
               SET payload = json_set(
                 payload, '\$.attributes.emailVerified', json('true')
               )
               WHERE email = ? AND ${_usableUserSql('payload')}
                 AND EXISTS (
                   SELECT 1 FROM $links WHERE provider_id = ? AND email = ?
                     AND consumption_marker = ?
                 )''')
          .bind([command.email, command.providerId, command.email, marker]),
      _sql.database
          .prepare('SELECT payload FROM $userTable WHERE email = ?')
          .bind([command.email]),
      _sql.database
          .prepare('''DELETE FROM $links WHERE provider_id = ? AND email = ?
               AND consumption_marker = ?''')
          .bind([command.providerId, command.email, marker]),
    ]);
    final before = results[0].results.firstOrNull;
    final claimed = (results[1].meta?.changes ?? 0) == 1;
    if (!claimed) {
      final expiresAt = before == null
          ? null
          : DateTime.tryParse(before['expires_at']?.toString() ?? '');
      return AuthMagicLinkConsumeResult(
        expiresAt != null && !command.now.isBefore(expiresAt.toUtc())
            ? AuthMagicLinkConsumeStatus.expired
            : AuthMagicLinkConsumeStatus.invalid,
      );
    }
    final row = results[4].results.firstOrNull;
    final user = row == null ? null : _decodeUser(row);
    if (user == null || authUserIsDisabled(user)) {
      return const AuthMagicLinkConsumeResult(
        AuthMagicLinkConsumeStatus.userUnavailable,
      );
    }
    return AuthMagicLinkConsumeResult(
      AuthMagicLinkConsumeStatus.consumed,
      user: user,
      created: (results[2].meta?.changes ?? 0) == 1,
    );
  }

  @override
  Future<void> issueEmailOtp(AuthEmailOtpIssueCommand command) =>
      Future.sync(() => emailOtps.save(command.otp));

  @override
  Future<AuthEmailOtpVerificationResult> verifyEmailOtp(
    AuthEmailOtpVerifyCommand command,
  ) => Future.sync(
    () => emailOtps.verifyDigest(
      command.email,
      command.type,
      command.codeHash,
      now: command.now,
    ),
  );

  @override
  Future<AuthEmailOtpUserTransitionResult> signInWithEmailOtp(
    AuthEmailOtpSignInCommand command,
  ) => _consumeEmailOtpForUser(
    email: command.email,
    type: AuthEmailOtpType.signIn,
    codeHash: command.codeHash,
    now: command.now,
    candidate: command.disableSignUp ? null : command.candidate,
  );

  @override
  Future<AuthEmailOtpUserTransitionResult> verifyUserEmailWithOtp(
    AuthEmailOtpVerifyUserCommand command,
  ) => _consumeEmailOtpForUser(
    email: command.email,
    type: AuthEmailOtpType.emailVerification,
    codeHash: command.codeHash,
    now: command.now,
    requiredUserId: command.userId,
  );

  Future<AuthEmailOtpUserTransitionResult> _consumeEmailOtpForUser({
    required String email,
    required AuthEmailOtpType type,
    required String codeHash,
    required DateTime now,
    AuthUser? candidate,
    String? requiredUserId,
  }) async {
    final otpTable = schema.table('email_otps');
    final userTable = schema.table('users');
    final receipts = schema.table('deletion_receipts');
    final marker = secureRandomToken(length: 24);
    final timestamp = _date(now);
    final verifiedCandidate = candidate == null
        ? null
        : _verifiedEmailUser(candidate);
    final batch = <CloudflareD1PreparedStatement>[
      _sql.database
          .prepare(
            'SELECT payload, verification_marker FROM $otpTable '
            'WHERE email = ? AND type = ?',
          )
          .bind([email, type.name]),
      _sql.database
          .prepare('''UPDATE $otpTable SET
                 payload = json_set(
                   payload,
                   '\$.attempts', json_extract(payload, '\$.attempts') + 1,
                   '\$.consumed', CASE WHEN code_hash = ?
                     THEN json('true')
                     ELSE json_extract(payload, '\$.consumed') END
                 ),
                 verification_marker = CASE WHEN code_hash = ? THEN ? ELSE NULL END
               WHERE email = ? AND type = ? AND expires_at > ?
                 AND json_extract(payload, '\$.consumed') = 0
                 AND json_extract(payload, '\$.attempts')
                   < json_extract(payload, '\$.max_attempts')''')
          .bind([codeHash, codeHash, marker, email, type.name, timestamp]),
      if (verifiedCandidate != null)
        _sql.database
            .prepare('''INSERT INTO $userTable (id, email, payload)
                 SELECT ?, ?, ? FROM $otpTable
                 WHERE email = ? AND type = ? AND verification_marker = ?
                   AND NOT EXISTS (SELECT 1 FROM $userTable WHERE email = ?)
                   AND NOT EXISTS (SELECT 1 FROM $userTable WHERE id = ?)
                   AND NOT EXISTS (
                     SELECT 1 FROM $receipts WHERE user_id_hash = ?
                   )''')
            .bind([
              verifiedCandidate.id,
              email,
              _encodeUser(verifiedCandidate),
              email,
              type.name,
              marker,
              email,
              verifiedCandidate.id,
              hashOpaqueToken(verifiedCandidate.id),
            ]),
      _sql.database
          .prepare('''UPDATE $userTable
               SET payload = json_set(
                 payload, '\$.attributes.emailVerified', json('true')
               )
               WHERE email = ?
                 ${requiredUserId == null ? '' : 'AND id = ?'}
                 AND ${_usableUserSql('payload')}
                 AND EXISTS (
                   SELECT 1 FROM $otpTable WHERE email = ? AND type = ?
                     AND verification_marker = ?
                 )''')
          .bind([email, ?requiredUserId, email, type.name, marker]),
      _sql.database
          .prepare(
            'SELECT payload, verification_marker FROM $otpTable '
            'WHERE email = ? AND type = ?',
          )
          .bind([email, type.name]),
      _sql.database
          .prepare('SELECT payload FROM $userTable WHERE email = ?')
          .bind([email]),
    ];
    final results = await _sql.batchRows(batch);
    final afterIndex = batch.length - 2;
    final userIndex = batch.length - 1;
    final afterRow = results[afterIndex].results.firstOrNull;
    final otp = afterRow == null ? null : _decodeEmailOtp(afterRow);
    final matched = afterRow?['verification_marker'] == marker;
    if (!matched) {
      return AuthEmailOtpUserTransitionResult(
        _emailOtpTransitionStatus(otp, now),
      );
    }
    final userRow = results[userIndex].results.firstOrNull;
    final user = userRow == null ? null : _decodeUser(userRow);
    if (user == null) {
      return const AuthEmailOtpUserTransitionResult(
        AuthEmailOtpUserTransitionStatus.userNotFound,
      );
    }
    if (authUserIsDisabled(user) ||
        (requiredUserId != null && user.id != requiredUserId)) {
      return const AuthEmailOtpUserTransitionResult(
        AuthEmailOtpUserTransitionStatus.userUnavailable,
      );
    }
    final inserted = verifiedCandidate != null
        ? (results[2].meta?.changes ?? 0) == 1
        : false;
    return AuthEmailOtpUserTransitionResult(
      AuthEmailOtpUserTransitionStatus.applied,
      user: user,
      created: inserted,
    );
  }

  /// Digest-only, bounded API-key persistence in this D1 domain.
  late final CloudflareD1AuthApiKeyStore apiKeys;

  @override
  late final CloudflareD1WebAuthnChallengeStore webAuthnChallenges;

  @override
  late final CloudflareD1WebAuthnAuthenticatorStore webAuthnAuthenticators;

  @override
  AuthUserDeletionPlan createWebAuthnDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  }) {
    if (!identical(domain, _deletionCoordinator.domain)) {
      throw StateError('WebAuthn received a foreign D1 deletion domain.');
    }
    return CloudflareD1UserDeletionPlan(
      domain: _deletionCoordinator.domain,
      userId: user.id,
      namespace: namespace,
      statements: [
        CloudflareD1UserDeletionStatement(
          sql:
              'DELETE FROM ${schema.table('webauthn_challenges')} '
              'WHERE user_id = ? AND {{guard}}',
          parameters: [user.id],
        ),
        CloudflareD1UserDeletionStatement(
          sql:
              'DELETE FROM ${schema.table('webauthn_authenticators')} '
              'WHERE user_id = ? AND {{guard}}',
          parameters: [user.id],
        ),
      ],
    );
  }

  /// Applies all pending schema migrations.
  Future<void> migrate() => schema.migrate(_database);
}

String _anonymousCreateFingerprint(AuthAnonymousCreateAccountCommand command) =>
    hashOpaqueToken('create:${_encodeUser(command.user)}');

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
    bool requireAnonymous = false,
    Iterable<CloudflareD1PreparedStatement> Function(
      String guard,
      List<Object?> guardValues,
      DateTime deletedAt,
    )?
    completion,
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
      guard = requireAnonymous
          ? '''EXISTS (SELECT 1 FROM $users WHERE id = ?
                AND json_extract(payload, '\$.isAnonymous') = 1)'''
          : 'EXISTS (SELECT 1 FROM $users WHERE id = ?)';
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
    if (completion != null) {
      batch.addAll(completion(guard, guardValues, current));
    }
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
      (schema.table('api_keys'), 'user_id'),
      (schema.table('webauthn_challenges'), 'user_id'),
      (schema.table('webauthn_authenticators'), 'user_id'),
    ]) {
      yield _sql.database
          .prepare('DELETE FROM ${entry.$1} WHERE ${entry.$2} = ? AND $guard')
          .bind([id, ...guardValues]);
    }
    final phoneIdentities = schema.table('phone_identities');
    final phoneVerifications = schema.table('phone_verifications');
    final phoneReceipts = schema.table('phone_issue_receipts');
    yield _sql.database
        .prepare('''DELETE FROM $phoneVerifications
             WHERE phone_number IN (
               SELECT phone_number FROM $phoneIdentities WHERE user_id = ?
             ) AND $guard''')
        .bind([id, ...guardValues]);
    yield _sql.database
        .prepare('''DELETE FROM $phoneReceipts
             WHERE phone_number IN (
               SELECT phone_number FROM $phoneIdentities WHERE user_id = ?
             ) AND $guard''')
        .bind([id, ...guardValues]);
    yield _sql.database
        .prepare('DELETE FROM $phoneIdentities WHERE user_id = ? AND $guard')
        .bind([id, ...guardValues]);
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
      yield _sql.database
          .prepare(
            'DELETE FROM ${schema.table('magic_links')} '
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
    final anonymousReceipts = schema.table('anonymous_mutation_receipts');
    yield _sql.database
        .prepare('''DELETE FROM $anonymousReceipts
             WHERE subject_user_id_hash = ? AND $guard''')
        .bind([hashOpaqueToken(id), ...guardValues]);
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

/// Bounded, digest-only one-time WebAuthn challenge persistence in D1.
final class CloudflareD1WebAuthnChallengeStore
    implements AuthWebAuthnChallengeStore {
  CloudflareD1WebAuthnChallengeStore._(
    this._sql,
    this.schema,
    this._clock,
    this.maxRecords,
  );

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() _clock;
  final int maxRecords;

  String get table => schema.table('webauthn_challenges');

  @override
  Future<void> save(AuthWebAuthnChallenge challenge) async {
    _validateD1WebAuthnChallenge(challenge);
    final now = _clock().toUtc();
    if (!challenge.expiresAt.toUtc().isAfter(now)) {
      throw StateError('WebAuthn challenge is already expired.');
    }
    final userId = challenge.userId;
    final results = await _sql.batch([
      _sql.database.prepare('DELETE FROM $table WHERE expires_at <= ?').bind([
        _date(now),
      ]),
      _sql.database
          .prepare('''INSERT OR IGNORE INTO $table
            (challenge_hash, id, ceremony, relying_party_id, origin, user_id,
             created_at, expires_at)
            SELECT ?, ?, ?, ?, ?, ?, ?, ?
            WHERE (SELECT COUNT(*) FROM $table) < ?
              AND (? IS NULL OR NOT EXISTS (
                SELECT 1 FROM ${schema.table('deletion_receipts')}
                WHERE user_id_hash = ?
              ))''')
          .bind([
            challenge.challengeHash,
            challenge.id,
            challenge.ceremony.name,
            challenge.relyingPartyId,
            challenge.origin,
            userId,
            _date(challenge.createdAt),
            _date(challenge.expiresAt),
            maxRecords,
            userId,
            userId == null ? null : hashOpaqueToken(userId),
          ]),
    ]);
    if ((results[1].meta?.changes ?? 0) != 1) {
      throw StateError(
        'WebAuthn challenge capacity, identity, or owner is unavailable.',
      );
    }
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
    final digest = _d1WebAuthnDigest(challengeHash, 'challengeHash');
    final rpId = _d1WebAuthnComponent(relyingPartyId, 'relyingPartyId', 253);
    final exactOrigin = _d1WebAuthnComponent(origin, 'origin', 2048);
    final owner = userId == null
        ? null
        : _d1WebAuthnComponent(userId, 'userId', 512);
    final current = (now ?? _clock()).toUtc();
    final results = await _sql.batchRows([
      _sql.database.prepare('DELETE FROM $table WHERE expires_at <= ?').bind([
        _date(current),
      ]),
      _sql.database
          .prepare('''DELETE FROM $table
            WHERE challenge_hash = ? AND ceremony = ?
              AND relying_party_id = ? AND origin = ?
              AND ((user_id IS NULL AND ? IS NULL) OR user_id = ?)
              AND created_at <= ? AND expires_at > ?
            RETURNING *''')
          .bind([
            digest,
            ceremony.name,
            rpId,
            exactOrigin,
            owner,
            owner,
            _date(current),
            _date(current),
          ]),
    ]);
    final row = results[1].results.firstOrNull;
    return row == null ? null : _decodeD1WebAuthnChallenge(row);
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await _sql.run('DELETE FROM $table WHERE user_id = ?', [
      _d1WebAuthnComponent(userId, 'userId', 512),
    ]);
  }
}

/// Bounded passkey persistence with exact counter and removal mutations.
final class CloudflareD1WebAuthnAuthenticatorStore
    implements
        AuthWebAuthnAuthenticatorStore,
        AuthWebAuthnAuthenticatorMutationStore {
  CloudflareD1WebAuthnAuthenticatorStore._(
    this._sql,
    this.schema,
    this._clock,
    this.maxRecords,
    this._root,
  );

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() _clock;
  final int maxRecords;
  final CloudflareD1AuthStore _root;

  String get table => schema.table('webauthn_authenticators');

  @override
  Future<WebAuthnAuthenticator?> findByCredentialId(String credentialId) =>
      _sql.first('SELECT * FROM $table WHERE credential_id = ?', [
        _d1WebAuthnComponent(
          credentialId,
          'credentialId',
          _webAuthnCredentialIdMaxLength,
        ),
      ], _decodeD1WebAuthnAuthenticator);

  @override
  Future<List<WebAuthnAuthenticator>> listForUser(String userId) => _sql.all(
    'SELECT * FROM $table WHERE user_id = ? ORDER BY created_at, credential_id',
    [_d1WebAuthnComponent(userId, 'userId', 512)],
    _decodeD1WebAuthnAuthenticator,
  );

  @override
  Future<WebAuthnAuthenticator> create(
    WebAuthnAuthenticator authenticator,
  ) async {
    _validateD1WebAuthnAuthenticator(authenticator);
    final result = await _sql.run(
      '''INSERT OR IGNORE INTO $table
        (credential_id, user_id, public_key, counter, transports, name,
         created_at, last_used_at)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?
        WHERE (SELECT COUNT(*) FROM $table) < ?
          AND NOT EXISTS (
            SELECT 1 FROM ${schema.table('deletion_receipts')}
            WHERE user_id_hash = ?
          )''',
      [
        ..._d1WebAuthnAuthenticatorValues(authenticator),
        maxRecords,
        hashOpaqueToken(authenticator.userId!),
      ],
    );
    if ((result.meta?.changes ?? 0) != 1) {
      throw StateError(
        'WebAuthn credential capacity, identity, or owner is unavailable.',
      );
    }
    return authenticator;
  }

  @override
  Future<WebAuthnAuthenticator?> updateUsage({
    required String credentialId,
    required int expectedCounter,
    required int newCounter,
    required DateTime lastUsedAt,
  }) {
    if (expectedCounter < 0 ||
        newCounter < expectedCounter ||
        newCounter > 0x7fffffffffffffff) {
      return Future.value(null);
    }
    final timestamp = _date(lastUsedAt);
    return _sql.first(
      '''UPDATE $table SET counter = ?,
           last_used_at = CASE
             WHEN last_used_at IS NULL OR last_used_at < ? THEN ?
             ELSE last_used_at END
         WHERE credential_id = ? AND counter = ? AND created_at <= ?
         RETURNING *''',
      [
        newCounter,
        timestamp,
        timestamp,
        _d1WebAuthnComponent(
          credentialId,
          'credentialId',
          _webAuthnCredentialIdMaxLength,
        ),
        expectedCounter,
        timestamp,
      ],
      _decodeD1WebAuthnAuthenticator,
    );
  }

  @override
  Future<bool> deleteForUser(String userId, String credentialId) async {
    final result = await _sql
        .run('DELETE FROM $table WHERE user_id = ? AND credential_id = ?', [
          _d1WebAuthnComponent(userId, 'userId', 512),
          _d1WebAuthnComponent(
            credentialId,
            'credentialId',
            _webAuthnCredentialIdMaxLength,
          ),
        ]);
    return (result.meta?.changes ?? 0) == 1;
  }

  @override
  Future<WebAuthnAuthenticator?> renameForUser(
    String userId,
    String credentialId,
    String name,
  ) => _sql.first(
    '''UPDATE $table SET name = ?
       WHERE user_id = ? AND credential_id = ? RETURNING *''',
    [
      _d1WebAuthnComponent(name, 'name', 256),
      _d1WebAuthnComponent(userId, 'userId', 512),
      _d1WebAuthnComponent(
        credentialId,
        'credentialId',
        _webAuthnCredentialIdMaxLength,
      ),
    ],
    _decodeD1WebAuthnAuthenticator,
  );

  @override
  Future<AuthAuthenticationMethodMutationResult> removeCredentialIfSafe(
    AuthWebAuthnCredentialRemovalCommand command,
  ) async {
    if (!_root._authenticationMethodTopologyBound ||
        !_root._authenticationMethodInventoryAuthoritative) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final snapshot = await command.loadInventory();
    if (!snapshot.isComplete) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final target = AuthAuthenticationMethod.passkey(command.credentialId);
    if (!snapshot.methods.contains(target)) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    final fallbacks = snapshot.methods
        .where((method) => method.canAuthenticate && method != target)
        .toList(growable: false);
    if (fallbacks.isEmpty) {
      return AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
    }
    final predicate = _fallbackPredicate(
      command.userId,
      command.credentialId,
      fallbacks,
    );
    if (predicate == null) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final result = await _sql.run(
      '''DELETE FROM $table
         WHERE user_id = ? AND credential_id = ? AND (${predicate.$1})''',
      [command.userId, command.credentialId, ...predicate.$2],
    );
    if ((result.meta?.changes ?? 0) == 1) {
      return AuthAuthenticationMethodMutationResult.mutated;
    }
    final existing = await findByCredentialId(command.credentialId);
    return existing?.userId == command.userId
        ? AuthAuthenticationMethodMutationResult.lastAuthenticationMethod
        : AuthAuthenticationMethodMutationResult.notFound;
  }

  (String, List<Object?>)? _fallbackPredicate(
    String userId,
    String credentialId,
    List<AuthAuthenticationMethod> methods,
  ) {
    var credentials = false;
    var email = false;
    var apiKeys = false;
    var passkeys = false;
    final oauthProviders = <String>{};
    for (final method in methods) {
      switch (method.kind) {
        case AuthAuthenticationMethodKind.password:
        case AuthAuthenticationMethodKind.username:
          credentials = true;
        case AuthAuthenticationMethodKind.oauthProvider:
          final providerId = method.providerId;
          if (providerId == null || method.providerAccountId == null) {
            return null;
          }
          oauthProviders.add(providerId);
        case AuthAuthenticationMethodKind.emailOtp:
        case AuthAuthenticationMethodKind.emailLink:
          email = true;
        case AuthAuthenticationMethodKind.apiKey:
          apiKeys = true;
        case AuthAuthenticationMethodKind.passkey:
          passkeys = true;
        case AuthAuthenticationMethodKind.phone:
        case AuthAuthenticationMethodKind.plugin:
          return null;
      }
    }
    final clauses = <String>[];
    final values = <Object?>[];
    if (credentials) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('credentials')}
        WHERE user_id = ? AND enabled = 1)''');
      values.add(userId);
    }
    if (oauthProviders.isNotEmpty) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('accounts')}
        WHERE user_id = ? AND provider_id IN
          (${List.filled(oauthProviders.length, '?').join(', ')}))''');
      values.addAll([userId, ...oauthProviders]);
    }
    if (email) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('users')}
        WHERE id = ? AND email IS NOT NULL AND email <> ''
          AND ${_usableUserSql('payload')})''');
      values.add(userId);
    }
    if (apiKeys) {
      final now = _date(_clock());
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('api_keys')}
        WHERE user_id = ? AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > ?))''');
      values.addAll([userId, now]);
    }
    if (passkeys) {
      clauses.add('''EXISTS (SELECT 1 FROM $table
        WHERE user_id = ? AND credential_id <> ?)''');
      values.addAll([userId, credentialId]);
    }
    return clauses.isEmpty ? null : (clauses.join(' OR '), values);
  }
}

/// Bounded, digest-only API-key persistence backed by Cloudflare D1.
final class CloudflareD1AuthApiKeyStore
    implements
        AuthApiKeyStore,
        AuthApiKeyUserAccessRevocationStore,
        AuthApiKeyPrimaryMutationStore,
        AuthUserDeletionPlanFactory {
  CloudflareD1AuthApiKeyStore._(
    this._sql,
    this.schema,
    this.domain,
    this._clock,
    this.maxRecords,
    this._root,
  );

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final CloudflareD1UserDeletionDomain domain;
  final DateTime Function() _clock;
  final int maxRecords;
  final CloudflareD1AuthStore _root;

  String get table => schema.table('api_keys');

  @override
  AuthUserDeletionPlan createDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  }) {
    if (!identical(domain, this.domain)) {
      throw StateError('API keys received a foreign D1 deletion domain.');
    }
    return CloudflareD1UserDeletionPlan(
      domain: this.domain,
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
  Future<AuthApiKeyRecord> create(AuthApiKeyRecord record) async {
    _validateD1ApiKeyRecord(record);
    final now = _clock().toUtc();
    final results = await _sql.batch([
      _pruneStatement(now),
      _sql.database
          .prepare('''INSERT OR IGNORE INTO $table
            (id, user_id, name, key_prefix, secret_hash, scopes, created_at,
             updated_at, expires_at, last_used_at, revoked_at)
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            WHERE (SELECT COUNT(*) FROM $table) < ?
              AND NOT EXISTS (
                SELECT 1 FROM ${schema.table('deletion_receipts')}
                WHERE user_id_hash = ?
              )''')
          .bind([
            ..._apiKeyValues(record),
            maxRecords,
            hashOpaqueToken(record.userId),
          ]),
    ]);
    if ((results[1].meta?.changes ?? 0) != 1) {
      throw StateError('API key storage capacity or owner is unavailable.');
    }
    return record;
  }

  @override
  Future<AuthApiKeyRecord?> findById(String id) => _sql.first(
    'SELECT * FROM $table WHERE id = ?',
    [_d1ApiKeyComponent(id, 'id', 512)],
    _decodeApiKeyRecord,
  );

  @override
  Future<List<AuthApiKeyRecord>> listForUser(String userId) => _sql.all(
    'SELECT * FROM $table WHERE user_id = ? ORDER BY created_at, id',
    [_d1ApiKeyComponent(userId, 'userId', 512)],
    _decodeApiKeyRecord,
  );

  @override
  Future<AuthApiKeyRecord?> touchIfActive(String id, DateTime lastUsedAt) =>
      _sql.first(
        '''UPDATE $table SET last_used_at = ?, updated_at = ?
       WHERE id = ? AND revoked_at IS NULL
         AND (expires_at IS NULL OR expires_at > ?)
       RETURNING *''',
        [
          _date(lastUsedAt),
          _date(lastUsedAt),
          _d1ApiKeyComponent(id, 'id', 512),
          _date(lastUsedAt),
        ],
        _decodeApiKeyRecord,
      );

  @override
  Future<AuthApiKeyRecord?> revokeForUser(
    String userId,
    String id, {
    DateTime? revokedAt,
  }) {
    final current = (revokedAt ?? _clock()).toUtc();
    return _sql.first(
      '''UPDATE $table SET revoked_at = ?, updated_at = ?
         WHERE user_id = ? AND id = ?
         RETURNING *''',
      [
        _date(current),
        _date(current),
        _d1ApiKeyComponent(userId, 'userId', 512),
        _d1ApiKeyComponent(id, 'id', 512),
      ],
      _decodeApiKeyRecord,
    );
  }

  @override
  Future<int> revokeAllForUser(String userId, {DateTime? revokedAt}) async {
    final current = (revokedAt ?? _clock()).toUtc();
    final result = await _sql.run(
      '''UPDATE $table SET revoked_at = ?, updated_at = ?
         WHERE user_id = ? AND revoked_at IS NULL''',
      [
        _date(current),
        _date(current),
        _d1ApiKeyComponent(userId, 'userId', 512),
      ],
    );
    return result.meta?.changes ?? 0;
  }

  @override
  Future<AuthApiKeyRecord?> rotateForUser({
    required String userId,
    required String id,
    required AuthApiKeyRecord replacement,
    DateTime? revokedAt,
  }) async {
    _validateD1ApiKeyRecord(replacement);
    final owner = _d1ApiKeyComponent(userId, 'userId', 512);
    final currentId = _d1ApiKeyComponent(id, 'id', 512);
    final current = (revokedAt ?? _clock()).toUtc();
    if (replacement.userId != owner ||
        replacement.id == currentId ||
        !replacement.isActive(now: current)) {
      return null;
    }
    final timestamp = _date(current);
    final rotationMarker = secureRandomToken(length: 24);
    final results = await _sql.batch([
      _pruneStatement(current),
      _sql.database
          .prepare('''INSERT OR IGNORE INTO $table
            (id, user_id, name, key_prefix, secret_hash, scopes, created_at,
             updated_at, expires_at, last_used_at, revoked_at, rotation_marker)
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            WHERE (SELECT COUNT(*) FROM $table) <= ?
              AND EXISTS (
                SELECT 1 FROM $table
                WHERE id = ? AND user_id = ? AND revoked_at IS NULL
                  AND (expires_at IS NULL OR expires_at > ?)
              )
              AND NOT EXISTS (
                SELECT 1 FROM ${schema.table('deletion_receipts')}
                WHERE user_id_hash = ?
              )''')
          .bind([
            ..._apiKeyValues(replacement),
            rotationMarker,
            maxRecords,
            currentId,
            owner,
            timestamp,
            hashOpaqueToken(owner),
          ]),
      _sql.database
          .prepare('''UPDATE $table SET revoked_at = ?, updated_at = ?
            WHERE id = ? AND user_id = ? AND revoked_at IS NULL
              AND EXISTS (SELECT 1 FROM $table
                WHERE id = ? AND rotation_marker = ?)
              AND (SELECT COUNT(*) FROM $table) <= ?''')
          .bind([
            timestamp,
            timestamp,
            currentId,
            owner,
            replacement.id,
            rotationMarker,
            maxRecords,
          ]),
      _sql.database
          .prepare('''DELETE FROM $table
            WHERE id = ? AND user_id = ? AND revoked_at IS NULL
              AND EXISTS (SELECT 1 FROM $table
                WHERE id = ? AND rotation_marker = ?)
              AND (SELECT COUNT(*) FROM $table) > ?''')
          .bind([currentId, owner, replacement.id, rotationMarker, maxRecords]),
      _sql.database
          .prepare('''UPDATE $table SET rotation_marker = NULL
            WHERE id = ? AND rotation_marker = ?''')
          .bind([replacement.id, rotationMarker]),
    ]);
    if ((results[1].meta?.changes ?? 0) != 1 ||
        (results[2].meta?.changes ?? 0) + (results[3].meta?.changes ?? 0) !=
            1 ||
        (results[4].meta?.changes ?? 0) != 1) {
      return null;
    }
    return replacement;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await _sql.run('DELETE FROM $table WHERE user_id = ?', [
      _d1ApiKeyComponent(userId, 'userId', 512),
    ]);
  }

  @override
  Future<AuthAuthenticationMethodMutationResult> revokePrimaryKeyIfSafe(
    AuthApiKeyPrimaryRevocationCommand command,
  ) async {
    if (!_root._authenticationMethodTopologyBound ||
        !_root._authenticationMethodInventoryAuthoritative) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final snapshot = await command.loadInventory();
    if (!snapshot.isComplete) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final target = AuthAuthenticationMethod.apiKey(command.keyId);
    if (!snapshot.methods.contains(target)) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    final fallbacks = snapshot.methods
        .where((method) => method.canAuthenticate && method != target)
        .toList(growable: false);
    if (fallbacks.isEmpty) {
      return AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
    }

    final predicate = _primaryFallbackPredicate(
      command.userId,
      command.keyId,
      command.revokedAt,
      fallbacks,
    );
    if (predicate == null) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final current = _date(command.revokedAt);
    final result = await _sql.run(
      '''UPDATE $table SET revoked_at = ?, updated_at = ?
         WHERE user_id = ? AND id = ? AND revoked_at IS NULL
           AND (expires_at IS NULL OR expires_at > ?)
           AND (${predicate.$1})''',
      [
        current,
        current,
        command.userId,
        command.keyId,
        current,
        ...predicate.$2,
      ],
    );
    if ((result.meta?.changes ?? 0) == 1) {
      return AuthAuthenticationMethodMutationResult.mutated;
    }
    final existing = await findById(command.keyId);
    return existing == null ||
            existing.userId != command.userId ||
            !existing.isActive(now: command.revokedAt)
        ? AuthAuthenticationMethodMutationResult.notFound
        : AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
  }

  (String, List<Object?>)? _primaryFallbackPredicate(
    String userId,
    String keyId,
    DateTime now,
    List<AuthAuthenticationMethod> methods,
  ) {
    var credentials = false;
    var email = false;
    var apiKeys = false;
    var passkeys = false;
    final oauthProviders = <String>{};
    for (final method in methods) {
      switch (method.kind) {
        case AuthAuthenticationMethodKind.password:
        case AuthAuthenticationMethodKind.username:
          credentials = true;
        case AuthAuthenticationMethodKind.oauthProvider:
          final providerId = method.providerId;
          if (providerId == null || method.providerAccountId == null) {
            return null;
          }
          oauthProviders.add(providerId);
        case AuthAuthenticationMethodKind.emailOtp:
        case AuthAuthenticationMethodKind.emailLink:
          email = true;
        case AuthAuthenticationMethodKind.apiKey:
          apiKeys = true;
        case AuthAuthenticationMethodKind.passkey:
          passkeys = true;
        case AuthAuthenticationMethodKind.phone:
        case AuthAuthenticationMethodKind.plugin:
          return null;
      }
    }
    final clauses = <String>[];
    final values = <Object?>[];
    if (credentials) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('credentials')}
        WHERE user_id = ? AND enabled = 1)''');
      values.add(userId);
    }
    if (oauthProviders.isNotEmpty) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('accounts')}
        WHERE user_id = ? AND provider_id IN
          (${List.filled(oauthProviders.length, '?').join(', ')}))''');
      values.addAll([userId, ...oauthProviders]);
    }
    if (email) {
      clauses.add('''EXISTS (SELECT 1 FROM ${schema.table('users')}
        WHERE id = ? AND email IS NOT NULL AND email <> ''
          AND COALESCE(json_extract(payload, '\$.attributes.disabled'), 0) <> 1
          AND COALESCE(json_extract(payload, '\$.attributes.accountDisabled'), 0) <> 1
          AND json_extract(payload, '\$.attributes.deletedAt') IS NULL)''');
      values.add(userId);
    }
    if (apiKeys) {
      clauses.add('''EXISTS (SELECT 1 FROM $table
        WHERE user_id = ? AND id <> ? AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > ?))''');
      values.addAll([userId, keyId, _date(now)]);
    }
    if (passkeys) {
      clauses.add(
        '''EXISTS (SELECT 1 FROM ${schema.table('webauthn_authenticators')}
          WHERE user_id = ?)''',
      );
      values.add(userId);
    }
    return clauses.isEmpty ? null : (clauses.join(' OR '), values);
  }

  CloudflareD1PreparedStatement _pruneStatement(DateTime now) => _sql.database
      .prepare('''DELETE FROM $table
        WHERE revoked_at IS NOT NULL
           OR (expires_at IS NOT NULL AND expires_at <= ?)''')
      .bind([_date(now)]);
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

/// Durable, digest-only phone authentication commands owned by the D1 domain.
final class CloudflareD1PhoneNumberStore implements AuthPhoneNumberBackend {
  CloudflareD1PhoneNumberStore._(
    this._sql,
    this.schema,
    this.clock,
    this.maxVerifications,
  );

  final _D1 _sql;
  final CloudflareD1AuthSchema schema;
  final DateTime Function() clock;
  final int maxVerifications;

  String get _verifications => schema.table('phone_verifications');
  String get _identities => schema.table('phone_identities');
  String get _receipts => schema.table('phone_issue_receipts');
  String get _users => schema.table('users');
  String get _deletionReceipts => schema.table('deletion_receipts');

  @override
  Future<AuthPhoneNumberIssueResult> issuePhoneNumberCode(
    AuthPhoneNumberIssueCodeCommand command,
  ) async {
    final sql = _sql;
    final verification = command.verification;
    final idHash = hashOpaqueToken(verification.id);
    final fingerprint = hashOpaqueToken(
      jsonEncode(verification.toStorageJson()),
    );
    final claimNonce = secureRandomToken(length: 24);
    final now = clock().toUtc();
    final results = await sql.batch([
      sql.database
          .prepare('DELETE FROM $_verifications WHERE expires_at <= ?')
          .bind([_date(now)]),
      sql.database
          .prepare('''DELETE FROM $_verifications
               WHERE id_hash IN (
                 SELECT id_hash FROM $_verifications
                 ORDER BY created_at DESC, id_hash DESC
                 LIMIT -1 OFFSET ?
               )''')
          .bind([maxVerifications]),
      sql.database
          .prepare('''DELETE FROM $_receipts
               WHERE operation_id_hash IN (
                 SELECT operation_id_hash FROM $_receipts
                 ORDER BY created_at DESC, operation_id_hash DESC
                 LIMIT -1 OFFSET ?
               )''')
          .bind([maxVerifications * 2]),
      sql.database
          .prepare('''INSERT OR IGNORE INTO $_receipts
               (operation_id_hash, fingerprint_hash, phone_number,
                claim_nonce, created_at)
               VALUES (?, ?, ?, ?, ?)''')
          .bind([
            idHash,
            fingerprint,
            verification.phoneNumber,
            claimNonce,
            _date(verification.createdAt),
          ]),
      sql.database
          .prepare('''INSERT INTO $_verifications
               (id_hash, phone_number, code_digest, created_at, expires_at,
                max_attempts, attempts, locked_at, consumed_at,
                verification_marker)
               SELECT ?, ?, ?, ?, ?, ?, 0, NULL, NULL, NULL
               WHERE EXISTS (
                 SELECT 1 FROM $_receipts
                 WHERE operation_id_hash = ? AND fingerprint_hash = ?
                   AND claim_nonce = ?
               )
               ON CONFLICT(phone_number) DO UPDATE SET
                 id_hash = excluded.id_hash,
                 code_digest = excluded.code_digest,
                 created_at = excluded.created_at,
                 expires_at = excluded.expires_at,
                 max_attempts = excluded.max_attempts,
                 attempts = excluded.attempts,
                 locked_at = NULL,
                 consumed_at = NULL,
                 verification_marker = NULL''')
          .bind([
            idHash,
            verification.phoneNumber,
            verification.codeDigest,
            _date(verification.createdAt),
            _date(verification.expiresAt),
            verification.maxAttempts,
            idHash,
            fingerprint,
            claimNonce,
          ]),
      sql.database
          .prepare('''DELETE FROM $_verifications
               WHERE id_hash IN (
                 SELECT id_hash FROM $_verifications
                 ORDER BY created_at DESC, id_hash DESC
                 LIMIT -1 OFFSET ?
               )''')
          .bind([maxVerifications]),
    ]);
    if ((results[3].meta?.changes ?? 0) == 1) {
      if ((results[4].meta?.changes ?? 0) != 1) {
        throw StateError('D1 phone challenge was not installed.');
      }
      return AuthPhoneNumberIssueResult(
        AuthPhoneNumberIssueStatus.issued,
        verification: verification,
      );
    }

    final receipt = await sql.first(
      'SELECT fingerprint_hash, phone_number FROM $_receipts '
      'WHERE operation_id_hash = ?',
      [idHash],
      (row) => (
        row['fingerprint_hash']?.toString() ?? '',
        row['phone_number']?.toString() ?? '',
      ),
    );
    if (receipt == null ||
        !constantTimeStringEquals(receipt.$1, fingerprint) ||
        receipt.$2 != verification.phoneNumber) {
      return const AuthPhoneNumberIssueResult(
        AuthPhoneNumberIssueStatus.replayMismatch,
      );
    }
    final active = await sql.first(
      'SELECT id_hash FROM $_verifications '
      'WHERE phone_number = ? AND id_hash = ? AND consumed_at IS NULL',
      [verification.phoneNumber, idHash],
      (row) => row['id_hash']?.toString(),
    );
    return active == null
        ? const AuthPhoneNumberIssueResult(
            AuthPhoneNumberIssueStatus.replayMismatch,
          )
        : AuthPhoneNumberIssueResult(
            AuthPhoneNumberIssueStatus.replayed,
            verification: verification,
          );
  }

  @override
  Future<AuthPhoneNumberVerifyResult> verifyPhoneNumberCode(
    AuthPhoneNumberVerifyCodeCommand command,
  ) async {
    final sql = _sql;
    final marker = secureRandomToken(length: 24);
    final now = command.now.toUtc();
    final candidate = command.candidateUser;
    final projectedCandidate = candidate == null
        ? null
        : _phoneVerifiedUser(candidate, command.phoneNumber);
    final candidateEmail = candidate == null
        ? null
        : _nullableEmail(candidate.email);
    final results = await sql.batchRows([
      sql.database
          .prepare('SELECT * FROM $_verifications WHERE phone_number = ?')
          .bind([command.phoneNumber]),
      sql.database
          .prepare('''UPDATE $_verifications SET
               attempts = attempts + 1,
               locked_at = CASE
                 WHEN code_digest = ? THEN locked_at
                 WHEN attempts + 1 >= max_attempts THEN ?
                 ELSE locked_at
               END,
               consumed_at = CASE
                 WHEN code_digest = ? THEN ?
                 ELSE consumed_at
               END,
               verification_marker = CASE
                 WHEN code_digest = ? THEN ?
                 ELSE NULL
               END
             WHERE phone_number = ? AND expires_at > ?
               AND consumed_at IS NULL AND locked_at IS NULL
               AND attempts < max_attempts''')
          .bind([
            command.codeDigest,
            _date(now),
            command.codeDigest,
            _date(now),
            command.codeDigest,
            marker,
            command.phoneNumber,
            _date(now),
          ]),
      if (projectedCandidate == null)
        sql.database.prepare('SELECT 1').bind([])
      else
        sql.database
            .prepare('''INSERT INTO $_users (id, email, payload)
                 SELECT ?, ?, ?
                 WHERE EXISTS (
                   SELECT 1 FROM $_verifications
                   WHERE phone_number = ? AND verification_marker = ?
                 )
                   AND NOT EXISTS (
                     SELECT 1 FROM $_identities WHERE phone_number = ?
                   )
                   AND NOT EXISTS (SELECT 1 FROM $_users WHERE id = ?)
                   AND (? IS NULL OR NOT EXISTS (
                     SELECT 1 FROM $_users WHERE email = ?
                   ))
                   AND NOT EXISTS (
                     SELECT 1 FROM $_deletionReceipts WHERE user_id_hash = ?
                   )''')
            .bind([
              projectedCandidate.id,
              candidateEmail,
              _encodeUser(projectedCandidate),
              command.phoneNumber,
              marker,
              command.phoneNumber,
              projectedCandidate.id,
              candidateEmail,
              candidateEmail,
              hashOpaqueToken(projectedCandidate.id),
            ]),
      sql.database
          .prepare('''INSERT INTO $_identities
               (phone_number, user_id, created_at, verified_at)
               SELECT ?, ?, ?, ?
               WHERE EXISTS (
                 SELECT 1 FROM $_verifications
                 WHERE phone_number = ? AND verification_marker = ?
               )
                 AND NOT EXISTS (
                   SELECT 1 FROM $_identities WHERE phone_number = ?
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM $_identities WHERE user_id = ?
                 )
                 AND EXISTS (SELECT 1 FROM $_users WHERE id = ?)''')
          .bind([
            command.phoneNumber,
            projectedCandidate?.id,
            _date(now),
            _date(now),
            command.phoneNumber,
            marker,
            command.phoneNumber,
            projectedCandidate?.id,
            projectedCandidate?.id,
          ]),
      sql.database
          .prepare('''UPDATE $_users SET payload = json_set(
               payload,
               '\$.attributes.phoneNumber', ?,
               '\$.attributes.phoneNumberVerified', json('true')
             )
             WHERE id = (
               SELECT user_id FROM $_identities
               WHERE phone_number = ?
             )
               AND ${_usableUserSql('payload')}
               AND EXISTS (
                 SELECT 1 FROM $_verifications
                 WHERE phone_number = ? AND verification_marker = ?
               )''')
          .bind([
            command.phoneNumber,
            command.phoneNumber,
            command.phoneNumber,
            marker,
          ]),
      sql.database
          .prepare('SELECT * FROM $_verifications WHERE phone_number = ?')
          .bind([command.phoneNumber]),
      sql.database
          .prepare('SELECT * FROM $_identities WHERE phone_number = ?')
          .bind([command.phoneNumber]),
      sql.database
          .prepare('''SELECT u.payload FROM $_users u
             WHERE u.id = (
               SELECT user_id FROM $_identities WHERE phone_number = ?
             )''')
          .bind([command.phoneNumber]),
    ]);

    final after = results[5].results.firstOrNull;
    final verification = after == null ? null : _decodePhoneVerification(after);
    if (verification == null) {
      return const AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.invalid,
      );
    }
    final markerMatched = after!['verification_marker']?.toString() == marker;
    if (verification.isExpired(now: now)) {
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.expired,
        verification: verification,
      );
    }
    if (!markerMatched && verification.isConsumed) {
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.invalid,
        verification: verification,
      );
    }
    if (!markerMatched && verification.isLocked) {
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.tooManyAttempts,
        verification: verification,
      );
    }
    if (!markerMatched) {
      return AuthPhoneNumberVerifyResult(
        verification.attempts >= verification.maxAttempts
            ? AuthPhoneNumberVerifyStatus.tooManyAttempts
            : AuthPhoneNumberVerifyStatus.invalid,
        verification: verification,
      );
    }

    final identityRow = results[6].results.firstOrNull;
    final identity = identityRow == null
        ? null
        : _decodePhoneIdentity(identityRow);
    if (identity == null) {
      return AuthPhoneNumberVerifyResult(
        candidate == null
            ? AuthPhoneNumberVerifyStatus.userNotFound
            : AuthPhoneNumberVerifyStatus.conflict,
        verification: verification,
      );
    }
    final userRow = results[7].results.firstOrNull;
    final user = userRow == null ? null : _decodeUser(userRow);
    if (user == null) {
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.userNotFound,
        verification: verification,
        identity: identity,
      );
    }
    if (authUserIsDisabled(user)) {
      return AuthPhoneNumberVerifyResult(
        AuthPhoneNumberVerifyStatus.userUnavailable,
        verification: verification,
        identity: identity,
      );
    }
    return AuthPhoneNumberVerifyResult(
      AuthPhoneNumberVerifyStatus.verified,
      verification: verification,
      identity: identity,
      user: user,
    );
  }

  @override
  Future<AuthPhoneNumberIdentity?> findPhoneNumberIdentity(String phoneNumber) {
    final sql = _sql;
    return sql.first('SELECT * FROM $_identities WHERE phone_number = ?', [
      validateAuthCanonicalPhoneNumber(phoneNumber),
    ], _decodePhoneIdentity);
  }

  @override
  Future<AuthPhoneNumberIdentity?> findPhoneNumberIdentityForUser(
    String userId,
  ) {
    final sql = _sql;
    return sql.first('SELECT * FROM $_identities WHERE user_id = ?', [
      userId.trim(),
    ], _decodePhoneIdentity);
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
           expires_at = excluded.expires_at, payload = excluded.payload,
           verification_marker = NULL''',
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
  Future<AuthEmailOtpVerificationResult> verifyDigest(
    String email,
    AuthEmailOtpType type,
    String codeHash, {
    DateTime? now,
  }) async {
    final normalizedEmail = _email(email);
    final current = (now ?? clock()).toUtc();
    final timestamp = _date(current);
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
          .bind([codeHash, normalizedEmail, type.name, timestamp]),
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

const int _webAuthnCredentialIdMaxLength = 4096;

AuthWebAuthnChallenge _decodeD1WebAuthnChallenge(Map<String, Object?> row) {
  final challenge = AuthWebAuthnChallenge(
    id: row['id']! as String,
    challengeHash: row['challenge_hash']! as String,
    ceremony: AuthWebAuthnCeremony.values.byName(row['ceremony']! as String),
    relyingPartyId: row['relying_party_id']! as String,
    origin: row['origin']! as String,
    userId: row['user_id'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    expiresAt: DateTime.parse(row['expires_at']! as String).toUtc(),
  );
  _validateD1WebAuthnChallenge(challenge);
  return challenge;
}

void _validateD1WebAuthnChallenge(AuthWebAuthnChallenge challenge) {
  _d1WebAuthnComponent(challenge.id, 'challenge.id', 512);
  _d1WebAuthnDigest(challenge.challengeHash, 'challenge.challengeHash');
  _d1WebAuthnComponent(
    challenge.relyingPartyId,
    'challenge.relyingPartyId',
    253,
  );
  _d1WebAuthnComponent(challenge.origin, 'challenge.origin', 2048);
  if (challenge.userId case final userId?) {
    _d1WebAuthnComponent(userId, 'challenge.userId', 512);
  }
  if (!challenge.expiresAt.toUtc().isAfter(challenge.createdAt.toUtc())) {
    throw ArgumentError.value(
      challenge.expiresAt,
      'challenge.expiresAt',
      'must be after createdAt',
    );
  }
}

List<Object?> _d1WebAuthnAuthenticatorValues(WebAuthnAuthenticator value) => [
  value.credentialId,
  value.userId,
  value.publicKey,
  value.counter,
  jsonEncode(value.transports ?? const <String>[]),
  value.name,
  _date(value.createdAt!),
  _nullableDate(value.lastUsedAt),
];

WebAuthnAuthenticator _decodeD1WebAuthnAuthenticator(Map<String, Object?> row) {
  final authenticator = WebAuthnAuthenticator(
    credentialId: row['credential_id']! as String,
    userId: row['user_id']! as String,
    publicKey: row['public_key']! as String,
    counter: (row['counter']! as num).toInt(),
    transports: _decodeStringList(row['transports']),
    name: row['name'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    lastUsedAt: _optionalDate(row['last_used_at']),
  );
  _validateD1WebAuthnAuthenticator(authenticator);
  return authenticator;
}

void _validateD1WebAuthnAuthenticator(WebAuthnAuthenticator authenticator) {
  _d1WebAuthnComponent(
    authenticator.credentialId,
    'authenticator.credentialId',
    _webAuthnCredentialIdMaxLength,
  );
  _d1WebAuthnComponent(
    authenticator.publicKey,
    'authenticator.publicKey',
    16384,
  );
  final userId = authenticator.userId;
  if (userId == null) {
    throw ArgumentError.value(userId, 'authenticator.userId', 'is required');
  }
  _d1WebAuthnComponent(userId, 'authenticator.userId', 512);
  final createdAt = authenticator.createdAt;
  if (createdAt == null) {
    throw ArgumentError.value(
      createdAt,
      'authenticator.createdAt',
      'is required',
    );
  }
  if (authenticator.counter < 0 || authenticator.counter > 0x7fffffffffffffff) {
    throw ArgumentError.value(
      authenticator.counter,
      'authenticator.counter',
      'must fit a non-negative SQLite integer',
    );
  }
  final transports = authenticator.transports ?? const <String>[];
  if (transports.length > 16 ||
      transports.toSet().length != transports.length) {
    throw ArgumentError.value(
      transports,
      'authenticator.transports',
      'must contain at most 16 unique values',
    );
  }
  for (final transport in transports) {
    _d1WebAuthnComponent(transport, 'authenticator.transport', 32);
  }
  if (authenticator.name case final name?) {
    _d1WebAuthnComponent(name, 'authenticator.name', 256);
  }
  final lastUsedAt = authenticator.lastUsedAt;
  if (lastUsedAt != null && lastUsedAt.toUtc().isBefore(createdAt.toUtc())) {
    throw ArgumentError.value(
      lastUsedAt,
      'authenticator.lastUsedAt',
      'must not be before createdAt',
    );
  }
}

String _d1WebAuthnDigest(String value, String name) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a SHA-256 base64url digest',
    );
  }
  return value;
}

String _d1WebAuthnComponent(String value, String name, int maxLength) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > maxLength ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError.value(value, name, 'must be a bounded safe value');
  }
  return value;
}

List<Object?> _apiKeyValues(AuthApiKeyRecord value) => [
  value.id,
  value.userId,
  value.name,
  value.keyPrefix,
  value.secretHash,
  jsonEncode(value.scopes),
  _date(value.createdAt),
  _date(value.updatedAt),
  _nullableDate(value.expiresAt),
  _nullableDate(value.lastUsedAt),
  _nullableDate(value.revokedAt),
];

AuthApiKeyRecord _decodeApiKeyRecord(Map<String, Object?> row) {
  final record = AuthApiKeyRecord(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    name: row['name']! as String,
    keyPrefix: row['key_prefix']! as String,
    secretHash: row['secret_hash']! as String,
    scopes: _decodeStringList(row['scopes']),
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    expiresAt: _optionalDate(row['expires_at']),
    lastUsedAt: _optionalDate(row['last_used_at']),
    revokedAt: _optionalDate(row['revoked_at']),
  );
  _validateD1ApiKeyRecord(record);
  return record;
}

void _validateD1ApiKeyRecord(AuthApiKeyRecord record) {
  _d1ApiKeyComponent(record.id, 'record.id', 512);
  _d1ApiKeyComponent(record.userId, 'record.userId', 512);
  _d1ApiKeyComponent(record.name, 'record.name', 100);
  _d1ApiKeyComponent(record.keyPrefix, 'record.keyPrefix', 128);
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(record.secretHash)) {
    throw ArgumentError.value(
      record.secretHash,
      'record.secretHash',
      'must be a SHA-256 base64url digest',
    );
  }
  if (record.updatedAt.toUtc().isBefore(record.createdAt.toUtc())) {
    throw ArgumentError.value(
      record.updatedAt,
      'record.updatedAt',
      'must not be before createdAt',
    );
  }
  if (record.scopes.length > 128 ||
      record.scopes.toSet().length != record.scopes.length ||
      record.scopes.any(
        (scope) =>
            scope.isEmpty ||
            scope.length > 100 ||
            scope != scope.trim().toLowerCase() ||
            !RegExp(r'^[a-z0-9:_./*-]+$').hasMatch(scope),
      )) {
    throw ArgumentError.value(record.scopes, 'record.scopes', 'must be safe');
  }
}

String _d1ApiKeyComponent(String value, String name, int maxLength) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > maxLength ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError.value(value, name, 'must be a bounded safe value');
  }
  return value;
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

String _usableUserSql(String payloadColumn) =>
    "COALESCE(json_extract($payloadColumn, '\$.attributes.disabled'), 0) != 1 "
    "AND COALESCE(json_extract($payloadColumn, "
    "'\$.attributes.accountDisabled'), 0) != 1 "
    "AND json_extract($payloadColumn, '\$.attributes.deletedAt') IS NULL";

AuthUser _verifiedEmailUser(AuthUser user) => AuthUser(
  id: user.id,
  email: user.email,
  name: user.name,
  image: user.image,
  roles: user.roles,
  attributes: <String, dynamic>{...user.attributes, 'emailVerified': true},
);

AuthEmailOtpUserTransitionStatus _emailOtpTransitionStatus(
  AuthEmailOtp? otp,
  DateTime now,
) {
  if (otp == null || otp.consumed) {
    return AuthEmailOtpUserTransitionStatus.invalid;
  }
  if (otp.isExpired(now: now)) {
    return AuthEmailOtpUserTransitionStatus.expired;
  }
  if (otp.attempts >= otp.maxAttempts) {
    return AuthEmailOtpUserTransitionStatus.tooManyAttempts;
  }
  return AuthEmailOtpUserTransitionStatus.invalid;
}

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

AuthPhoneNumberIdentity _decodePhoneIdentity(Map<String, Object?> row) =>
    AuthPhoneNumberIdentity(
      phoneNumber: row['phone_number']! as String,
      userId: row['user_id']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      verifiedAt: DateTime.parse(row['verified_at']! as String),
    );

AuthPhoneNumberVerification _decodePhoneVerification(
  Map<String, Object?> row,
) => AuthPhoneNumberVerification(
  id: row['id_hash']! as String,
  phoneNumber: row['phone_number']! as String,
  codeDigest: row['code_digest']! as String,
  createdAt: DateTime.parse(row['created_at']! as String),
  expiresAt: DateTime.parse(row['expires_at']! as String),
  maxAttempts: (row['max_attempts'] as num).toInt(),
  attempts: (row['attempts'] as num).toInt(),
  lockedAt: _optionalDate(row['locked_at']),
  consumedAt: _optionalDate(row['consumed_at']),
);

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
