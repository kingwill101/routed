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
        AuthUserDeletionCoordinatorHost,
        AuthOAuthAccountMutationStore,
        AuthAuthenticationMethodTopologyStore {
  CloudflareD1AuthStore(
    CloudflareD1Database database, {
    this.schema = const CloudflareD1AuthSchema(),
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
    _deletionCoordinator = CloudflareD1UserDeletionCoordinator._(
      database: database,
      sql: sql,
      schema: schema,
      clock: _clock,
    );
  }

  /// Creates an adapter and applies all pending typed migrations.
  static Future<CloudflareD1AuthStore> open(
    CloudflareD1Database database, {
    CloudflareD1AuthSchema schema = const CloudflareD1AuthSchema(),
    DateTime Function()? clock,
  }) async {
    await schema.migrate(database);
    return CloudflareD1AuthStore(database, schema: schema, clock: clock);
  }

  final CloudflareD1Database _database;
  late final _D1 _sql;
  final DateTime Function() _clock;
  final CloudflareD1AuthSchema schema;
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
      final allowedKinds = identical(binding.authenticationMethodStore, users)
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

  @override
  Future<AuthPasswordCredential?> findForUser(String userId) => sql.first(
    'SELECT * FROM $table WHERE user_id = ? ORDER BY created_at LIMIT 1',
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
