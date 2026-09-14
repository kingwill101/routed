import 'dart:async';
import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:server_auth/server_auth.dart';

import 'orm_auth_schema.dart';
import 'orm_transaction_gate.dart';

/// Durable core authentication store backed by an Ormed database.
///
/// This adapter intentionally uses Ormed's codegen-optional ad-hoc query
/// builder. Values are kept in a typed record envelope so adding a new
/// `server_auth` store does not require a generated model or handwritten SQL.
final class OrmAuthStore
    implements
        AuthStore,
        AuthAdminStoreCapabilities,
        AuthOAuthAccountMutationStore,
        AuthUserDeletionCoordinatorHost {
  /// Creates a store over an open Ormed database.
  ///
  /// Transaction-capable drivers run mutations atomically. Drivers without a
  /// callback transaction boundary, such as Cloudflare D1, are supported with
  /// per-database operation ordering; callers should use the database's
  /// native atomic-batch API for fixed multi-statement workflows.
  OrmAuthStore(
    this.database, {
    this.schema = const OrmAuthSchema(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _transactionGate = transactionGateFor(database) {
    if (!database.isOpen) {
      throw ArgumentError.value(database, 'database', 'must be open');
    }
    _users = _OrmUsers(this);
    _credentials = _OrmCredentials(this);
    _accounts = _OrmAccounts(this);
    _sessions = _OrmSessions(this);
    _oauthChallenges = _OrmOAuthChallenges(this);
    _passwordResetTokens = _OrmPasswordResetTokens(this);
    _jwtVersions = _OrmJwtVersions(this);
    _verificationTokens = _OrmVerificationTokens(this);
    _emailChangeTokens = _OrmEmailChangeTokens(this);
    _deviceAuthorizations = _OrmDeviceAuthorizations(this);
    _emailOtps = _OrmEmailOtps(this);
    _deletionCoordinator = _OrmUserDeletionCoordinator(this);
  }

  /// Opens a store after applying its migration.
  static Future<OrmAuthStore> open(
    OrmDatabase database, {
    OrmAuthSchema schema = const OrmAuthSchema(),
    String ledgerTable = 'orm_migrations',
    DateTime Function()? clock,
  }) async {
    await schema.migrate(database, ledgerTable: ledgerTable);
    return OrmAuthStore(database, schema: schema, clock: clock);
  }

  /// Ormed database handle supplied by the application lifecycle.
  final OrmDatabase database;

  /// Schema configuration for this adapter.
  final OrmAuthSchema schema;
  final DateTime Function() _clock;
  late final _OrmUsers _users;
  late final _OrmCredentials _credentials;
  late final _OrmAccounts _accounts;
  late final _OrmSessions _sessions;
  late final _OrmOAuthChallenges _oauthChallenges;
  late final _OrmPasswordResetTokens _passwordResetTokens;
  late final _OrmJwtVersions _jwtVersions;
  late final _OrmVerificationTokens _verificationTokens;
  late final _OrmEmailChangeTokens _emailChangeTokens;
  late final _OrmDeviceAuthorizations _deviceAuthorizations;
  late final _OrmEmailOtps _emailOtps;
  late final _OrmUserDeletionCoordinator _deletionCoordinator;
  final OrmAuthTransactionGate _transactionGate;

  /// Durable hard-deletion coordinator used by auth plugins.
  @override
  AuthUserDeletionCoordinator get userDeletionCoordinator =>
      _deletionCoordinator;

  /// Returns the durable database transaction used by plugin deletion plans.
  Future<T> runDeletionTransaction<T>(Future<T> Function() action) =>
      _transaction(action);

  /// Consumes an account-deletion confirmation token inside the current
  /// Ormed transaction.
  Future<bool> consumeDeletionTokenInTransaction(
    String userId,
    String token,
  ) async {
    final key = _verificationKey('account_deletion:${userId.trim()}', token);
    final row = await _findKey(key);
    if (row == null ||
        row.expiresAt == null ||
        !_now.isBefore(row.expiresAt!)) {
      return false;
    }
    await _deleteKey(key);
    return true;
  }

  /// Binds the plugin deletion topology exactly once.
  @override
  void bindUserDeletionPlanContributors(
    Iterable<AuthUserDeletionPlanContributor> contributors,
  ) => _deletionCoordinator.bind(contributors);

  /// User persistence operations.
  @override
  AuthUserStore get users => _users;

  /// Password credential persistence operations.
  @override
  AuthCredentialStore get credentials => _credentials;

  /// External provider account persistence operations.
  @override
  AuthAccountStore get accounts => _accounts;

  /// Server-side session persistence operations.
  @override
  AuthSessionStore get sessions => _sessions;

  /// OAuth challenge persistence operations.
  @override
  AuthOAuthChallengeStore get oauthChallenges => _oauthChallenges;

  /// Password-reset persistence operations.
  @override
  AuthPasswordResetTokenStore get passwordResetTokens => _passwordResetTokens;

  /// JWT-version persistence operations.
  @override
  AuthJwtVersionStore get jwtVersions => _jwtVersions;

  /// Verification-token persistence operations.
  @override
  AuthVerificationTokenStore get verificationTokens => _verificationTokens;

  /// Email-change persistence operations.
  @override
  AuthEmailChangeTokenStore get emailChangeTokens => _emailChangeTokens;

  /// Device-authorization persistence operations.
  @override
  AuthDeviceAuthorizationStore get deviceAuthorizations =>
      _deviceAuthorizations;

  /// Email OTP persistence operations.
  @override
  AuthEmailOtpStore get emailOtps => _emailOtps;

  Future<T> _transaction<T>(Future<T> Function() action) =>
      _transactionGate.run(database, action);

  Query<AdHocRow> _table() =>
      database.table(schema.table('records'), columns: _columns);

  Future<List<_Record>> _find({
    String? kind,
    String? lookup,
    String? ownerId,
  }) async {
    var query = _table();
    if (kind != null) query = query.whereEquals('kind', kind);
    if (lookup != null) query = query.whereEquals('lookup', lookup);
    if (ownerId != null) query = query.whereEquals('owner_id', ownerId);
    final rows = await query.get();
    return rows.map(_Record.fromRow).toList(growable: false);
  }

  Future<_Record?> _findKey(String key) async {
    final rows = await _table().whereEquals('record_key', key).get();
    return rows.isEmpty ? null : _Record.fromRow(rows.first);
  }

  Future<void> _insert(_Record record) async {
    await _table().insertManyInputs([record.toRow()], returning: false);
  }

  Future<int> _deleteKey(String key) =>
      _table().whereEquals('record_key', key).delete();

  Future<int> _deleteWhere({String? kind, String? ownerId, String? lookup}) {
    var query = _table();
    if (kind != null) query = query.whereEquals('kind', kind);
    if (ownerId != null) query = query.whereEquals('owner_id', ownerId);
    if (lookup != null) query = query.whereEquals('lookup', lookup);
    return query.delete();
  }

  DateTime get _now => _clock().toUtc();

  @override
  Future<List<AuthUser>> listUsersForAdministration() => _transaction(() async {
    final records = await _find(kind: 'user');
    return records.map(_userFromRecord).toList(growable: false);
  });

  @override
  Future<AuthUser?> updateUserForAdministration(AuthUser user) =>
      _users.update(user);

  @override
  Future<AuthPasswordCredential?> findCredentialForUser(String userId) =>
      _credentials.findForUser(userId);

  @override
  Future<AuthPasswordCredential> upsertCredentialForAdministration(
    AuthPasswordCredential credential,
  ) => _transaction(() async {
    final existing = await _findKey(_credentialKey(credential.id));
    final conflicting = await _find(
      kind: 'credential',
      lookup: credential.identifier,
    );
    if (conflicting.any(
      (record) => record.key != _credentialKey(credential.id),
    )) {
      throw StateError('Auth credential identifier already exists');
    }
    if (existing != null) await _deleteKey(existing.key);
    await _insert(_credentialRecord(credential));
    return credential;
  });

  @override
  Future<bool> deleteUserForAdministration(String userId) =>
      _transaction(() => _deleteCore(userId));

  @override
  Future<bool> tombstoneUserForAdministration(
    String userId, {
    DateTime? deletedAt,
  }) => _transaction(() async {
    final record = await _findKey(_userKey(userId.trim()));
    if (record == null) return false;
    final user = _userFromRecord(record);
    if (authUserIsDisabled(user)) return false;
    final tombstone = AuthUser(
      id: user.id,
      attributes: <String, dynamic>{
        'deletedAt': (deletedAt ?? _now).toUtc().toIso8601String(),
      },
    );
    await _replace(_userRecord(tombstone, now: _now));
    await _deleteWhere(kind: 'credential', ownerId: user.id);
    await _deleteWhere(kind: 'account', ownerId: user.id);
    await _deleteWhere(kind: 'session', ownerId: user.id);
    await _deleteWhere(kind: 'remember', ownerId: user.id);
    await _deleteWhere(kind: 'password_reset', ownerId: user.id);
    await _deleteWhere(kind: 'verification', ownerId: user.id);
    await _deleteWhere(kind: 'email_change', ownerId: user.id);
    await _deleteWhere(kind: 'device', ownerId: user.id);
    if (user.email != null) {
      await _deleteWhere(
        kind: 'verification',
        lookup: normalizeAuthEmail(user.email!),
      );
      await _deleteWhere(
        kind: 'otp',
        lookup: normalizeAuthEmailOtpEmail(user.email!),
      );
    }
    return true;
  });

  @override
  Future<bool> purgeTombstonedUserForAdministration(String userId) =>
      _transaction(() async {
        final record = await _findKey(_userKey(userId.trim()));
        if (record == null) return false;
        final user = _userFromRecord(record);
        if (user.attributes['deletedAt'] == null) return false;
        return _deleteCore(user.id);
      });

  Future<bool> _deleteCore(String userId) async {
    final id = userId.trim();
    if (id.isEmpty || await _findKey(_userKey(id)) == null) return false;
    await _deleteWhere(ownerId: id);
    await _deleteWhere(kind: 'user', lookup: id);
    await _deleteKey(_userKey(id));
    await _deleteWhere(kind: 'password_reset', ownerId: id);
    await _deleteWhere(kind: 'verification', ownerId: id);
    await _deleteWhere(kind: 'email_change', ownerId: id);
    await _deleteWhere(kind: 'device', ownerId: id);
    await _deleteWhere(kind: 'jwt', ownerId: id);
    final now = _now;
    await _insert(
      _Record(
        key: 'jwt:$id',
        kind: 'jwt',
        lookup: null,
        ownerId: id,
        payload: {'version': 1},
        createdAt: now,
        expiresAt: null,
        updatedAt: now,
      ),
    );
    await _insert(
      _Record(
        key: 'deleted_user:$id',
        kind: 'deleted_user',
        lookup: id,
        ownerId: null,
        payload: {'user_id': id, 'deleted_at': now.toIso8601String()},
        createdAt: now,
        expiresAt: null,
        updatedAt: now,
      ),
    );
    return true;
  }

  Future<void> _replace(_Record record) async {
    await _deleteKey(record.key);
    await _insert(record);
  }

  @override
  Future<AuthAuthenticationMethodMutationResult> unlinkOAuthAccountIfSafe({
    required String userId,
    required String providerId,
    required String providerAccountId,
    required AuthAuthenticationMethodInventoryLoader loadInventory,
  }) => _transaction(() async {
    // Inventory contributors may call this store's typed reads. The shared
    // gate is re-entrant, so transaction-capable drivers use savepoints for
    // those reads; D1 simply continues the ordered operation.
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
    if (!snapshot.methods.any(
      (method) => method.canAuthenticate && method != target,
    )) {
      return AuthAuthenticationMethodMutationResult.lastAuthenticationMethod;
    }
    final key = _accountKey(providerId, providerAccountId);
    final account = await _findKey(key);
    if (account == null || account.ownerId != userId.trim()) {
      return AuthAuthenticationMethodMutationResult.notFound;
    }
    await _deleteKey(key);
    return AuthAuthenticationMethodMutationResult.mutated;
  });
}

final class _Record {
  const _Record({
    required this.key,
    required this.kind,
    required this.lookup,
    required this.ownerId,
    required this.payload,
    required this.createdAt,
    required this.expiresAt,
    required this.updatedAt,
  });

  factory _Record.fromRow(AdHocRow row) => _Record(
    key: row['record_key']!.toString(),
    kind: row['kind']!.toString(),
    lookup: row['lookup']?.toString(),
    ownerId: row['owner_id']?.toString(),
    payload: Map<String, dynamic>.from(
      jsonDecode(row['payload']!.toString()) as Map,
    ),
    createdAt:
        DateTime.tryParse(row['created_at']!.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    expiresAt: row['expires_at'] == null
        ? null
        : DateTime.tryParse(row['expires_at']!.toString()),
    updatedAt:
        DateTime.tryParse(row['updated_at']!.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final String key;
  final String kind;
  final String? lookup;
  final String? ownerId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime updatedAt;

  Map<String, Object?> toRow() => <String, Object?>{
    'record_key': key,
    'kind': kind,
    'lookup': lookup,
    'owner_id': ownerId,
    'payload': jsonEncode(payload),
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

const _columns = <AdHocColumn>[
  AdHocColumn(
    name: 'record_key',
    dartType: 'String',
    isNullable: false,
    isPrimaryKey: true,
  ),
  AdHocColumn(name: 'kind', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'lookup', dartType: 'String'),
  AdHocColumn(name: 'owner_id', dartType: 'String'),
  AdHocColumn(name: 'payload', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'created_at', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'expires_at', dartType: 'String'),
  AdHocColumn(name: 'updated_at', dartType: 'String', isNullable: false),
];

String _userKey(String id) => 'user:${id.trim()}';
String _credentialKey(String id) => 'credential:${id.trim()}';
String _accountKey(String provider, String account) =>
    'account:${hashOpaqueToken(jsonEncode([provider, account]))}';
String _accountLookup(String provider, String account) =>
    jsonEncode([provider, account]);
String _sessionKey(String hash) => 'session:$hash';
String _oauthKey(String provider, String state) =>
    'oauth:${hashOpaqueToken(jsonEncode([provider, state]))}';
String _verificationKey(String identifier, String token) =>
    'verification:$identifier:${hashOpaqueToken(token)}';
String _emailChangeKey(String token) =>
    'email_change:${hashOpaqueToken(token)}';
String _deviceKey(String hash) => 'device:$hash';
String _otpKey(String email, AuthEmailOtpType type) =>
    'otp:${hashOpaqueToken(jsonEncode([normalizeAuthEmailOtpEmail(email), type.name]))}';

_Record _userRecord(AuthUser user, {DateTime? now}) {
  final timestamp = (now ?? DateTime.now()).toUtc();
  return _Record(
    key: _userKey(user.id),
    kind: 'user',
    lookup: user.email?.trim().toLowerCase(),
    ownerId: user.id,
    payload: user.toJson(),
    createdAt: timestamp,
    expiresAt: null,
    updatedAt: timestamp,
  );
}

AuthUser _userFromRecord(_Record record) => AuthUser.fromJson(record.payload);
_Record _credentialRecord(AuthPasswordCredential value) => _Record(
  key: _credentialKey(value.id),
  kind: 'credential',
  lookup: value.identifier,
  ownerId: value.userId,
  payload: value.toStorageJson(),
  createdAt: value.createdAt,
  expiresAt: null,
  updatedAt: value.updatedAt,
);
AuthPasswordCredential _credentialFromRecord(_Record r) =>
    AuthPasswordCredential(
      id: r.payload['id'].toString(),
      userId: r.payload['user_id'].toString(),
      identifier: r.payload['identifier'].toString(),
      passwordHash: r.payload['password_hash'].toString(),
      createdAt: _date(r.payload['created_at'])!,
      updatedAt: _date(r.payload['updated_at'])!,
      enabled: r.payload['enabled'] == true,
    );
DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

final class _OrmUsers implements AuthUserStore {
  const _OrmUsers(this.root);
  final OrmAuthStore root;
  @override
  Future<AuthUser?> findById(String id) => root._transaction(() async {
    final row = await root._findKey(_userKey(id));
    return row == null ? null : _userFromRecord(row);
  });
  @override
  Future<AuthUser?> findByEmail(String email) => root._transaction(() async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final rows = await root._find(kind: 'user', lookup: normalized);
    return rows.isEmpty ? null : _userFromRecord(rows.first);
  });
  @override
  Future<AuthUser> create(AuthUser user) => root._transaction(() async {
    validateAuthUserForPersistence(user);
    if (await root._findKey('deleted_user:${user.id.trim()}') != null) {
      throw StateError('Auth user ID is permanently unavailable');
    }
    if (await root._findKey(_userKey(user.id)) != null) {
      throw StateError('Auth user ID already exists');
    }
    if (user.email != null &&
        (await root._find(
          kind: 'user',
          lookup: user.email!.trim().toLowerCase(),
        )).isNotEmpty) {
      throw StateError('Auth user email already exists');
    }
    final record = _userRecord(user, now: root._now);
    await root._insert(record);
    return user;
  });
  @override
  Future<AuthUserCreateResult> createOrFindByEmail(AuthUser user) =>
      root._transaction(() async {
        validateAuthUserForPersistence(user);
        if (await root._findKey('deleted_user:${user.id.trim()}') != null) {
          throw StateError('Auth user ID is permanently unavailable');
        }
        final byId = await root._findKey(_userKey(user.id));
        if (byId != null) {
          return AuthUserCreateResult(
            user: _userFromRecord(byId),
            created: false,
          );
        }
        if (user.email != null) {
          final byEmail = await root._find(
            kind: 'user',
            lookup: user.email!.trim().toLowerCase(),
          );
          if (byEmail.isNotEmpty) {
            return AuthUserCreateResult(
              user: _userFromRecord(byEmail.first),
              created: false,
            );
          }
        }
        await root._insert(_userRecord(user, now: root._now));
        return AuthUserCreateResult(user: user, created: true);
      });
  @override
  Future<AuthUser?> update(AuthUser user) => root._transaction(() async {
    validateAuthUserForPersistence(user);
    final current = await root._findKey(_userKey(user.id));
    if (current == null) return null;
    if (user.email != null) {
      final conflict = await root._find(
        kind: 'user',
        lookup: user.email!.trim().toLowerCase(),
      );
      if (conflict.any((row) => row.key != current.key)) return null;
    }
    await root._replace(_userRecord(user, now: root._now));
    return user;
  });
  @override
  Future<AuthUser?> updateEmailForUser(String userId, String email) =>
      root._transaction(() async {
        final id = userId.trim();
        final normalized = email.trim().toLowerCase();
        if (id.isEmpty || normalized.isEmpty) return null;
        final current = await root._findKey(_userKey(id));
        if (current == null) return null;
        final conflict = await root._find(kind: 'user', lookup: normalized);
        if (conflict.any((row) => row.key != current.key)) return null;
        final existing = _userFromRecord(current);
        final updated = AuthUser(
          id: existing.id,
          email: normalized,
          name: existing.name,
          image: existing.image,
          roles: existing.roles,
          isAnonymous: existing.isAnonymous,
          attributes: existing.attributes,
        );
        await root._replace(_userRecord(updated, now: root._now));
        return updated;
      });
  @override
  Future<bool> delete(String userId) =>
      root._transaction(() => root._deleteCore(userId));
}

final class _OrmCredentials
    implements AuthCredentialStore, AuthCredentialUserLookupStore {
  const _OrmCredentials(this.root);
  final OrmAuthStore root;
  @override
  Future<AuthPasswordCredential?> findByIdentifier(String identifier) =>
      root._transaction(() async {
        final normalized = identifier.trim();
        if (normalized.isEmpty) return null;
        final rows = await root._find(kind: 'credential', lookup: normalized);
        return rows.isEmpty ? null : _credentialFromRecord(rows.first);
      });
  @override
  Future<AuthPasswordCredential?> findForUser(String userId) =>
      root._transaction(() async {
        final rows = await root._find(
          kind: 'credential',
          ownerId: userId.trim(),
        );
        return rows.isEmpty ? null : _credentialFromRecord(rows.first);
      });
  @override
  Future<AuthUser?> register(
    AuthUser user,
    AuthPasswordCredential credential,
  ) => root._transaction(() async {
    validateAuthUserForPersistence(user);
    if (credential.id.trim().isEmpty ||
        credential.userId != user.id ||
        credential.identifier.trim().isEmpty ||
        credential.passwordHash.isEmpty) {
      return null;
    }
    if (await root._findKey(_userKey(user.id)) != null ||
        await root._findKey(_credentialKey(credential.id)) != null) {
      return null;
    }
    if (user.email != null &&
        (await root._find(
          kind: 'user',
          lookup: user.email!.trim().toLowerCase(),
        )).isNotEmpty) {
      return null;
    }
    if ((await root._find(
      kind: 'credential',
      lookup: credential.identifier,
    )).isNotEmpty) {
      return null;
    }
    await root._insert(_userRecord(user, now: root._now));
    await root._insert(_credentialRecord(credential));
    return user;
  });
  @override
  Future<AuthPasswordCredential?> update(AuthPasswordCredential credential) =>
      root._transaction(() async {
        final current = await root._findKey(_credentialKey(credential.id));
        if (current == null) return null;
        final conflict = await root._find(
          kind: 'credential',
          lookup: credential.identifier,
        );
        if (conflict.any((row) => row.key != current.key)) return null;
        await root._replace(_credentialRecord(credential));
        return credential;
      });
  @override
  Future<int> updatePasswordForUser({
    required String userId,
    required String passwordHash,
    required DateTime updatedAt,
  }) => root._transaction(() async {
    final rows = await root._find(kind: 'credential', ownerId: userId.trim());
    for (final row in rows) {
      final old = _credentialFromRecord(row);
      await root._replace(
        _credentialRecord(
          old.copyWith(passwordHash: passwordHash, updatedAt: updatedAt),
        ),
      );
    }
    return rows.length;
  });
  @override
  Future<void> delete(String credentialId) => root._transaction(() async {
    await root._deleteKey(_credentialKey(credentialId));
  });
  @override
  Future<void> deleteForUser(String userId) => root._transaction(() async {
    await root._deleteWhere(kind: 'credential', ownerId: userId.trim());
  });
}

final class _OrmAccounts implements AuthAccountStore {
  const _OrmAccounts(this.root);
  final OrmAuthStore root;
  @override
  Future<AuthAccount?> find(String providerId, String providerAccountId) =>
      root._transaction(() async {
        final row = await root._findKey(
          _accountKey(providerId, providerAccountId),
        );
        return row == null ? null : _accountFromRecord(row);
      });
  @override
  Future<List<AuthAccount>> listForUser(String userId) =>
      root._transaction(() async {
        final rows = await root._find(kind: 'account', ownerId: userId.trim());
        return rows.map(_accountFromRecord).toList(growable: false);
      });
  @override
  Future<AuthAccount> link(AuthAccount account) => root._transaction(() async {
    validateAuthAccountForLink(account);
    final key = _accountKey(account.providerId, account.providerAccountId);
    final existing = await root._findKey(key);
    if (existing != null) return _accountFromRecord(existing);
    try {
      await root._insert(_accountRecord(account, now: root._now));
      return account;
    } on Object {
      // A second process can win the unique account race after the initial
      // lookup. Preserve the contract's canonical-winner result instead of
      // leaking a driver-specific constraint error.
      final winner = await root._findKey(key);
      if (winner != null) return _accountFromRecord(winner);
      rethrow;
    }
  });
  @override
  Future<bool> unlinkForUser(
    String userId,
    String providerId,
    String providerAccountId,
  ) => root._transaction(() async {
    final key = _accountKey(providerId, providerAccountId);
    final row = await root._findKey(key);
    if (row == null || row.ownerId != userId.trim()) return false;
    await root._deleteKey(key);
    return true;
  });
  @override
  Future<void> deleteForUser(String userId) => root._transaction(() async {
    await root._deleteWhere(kind: 'account', ownerId: userId.trim());
  });
}

_Record _accountRecord(AuthAccount value, {DateTime? now}) {
  final timestamp = (now ?? DateTime.now()).toUtc();
  return _Record(
    key: _accountKey(value.providerId, value.providerAccountId),
    kind: 'account',
    lookup: _accountLookup(value.providerId, value.providerAccountId),
    ownerId: value.userId,
    payload: value.toStorageJson(),
    createdAt: timestamp,
    expiresAt: value.expiresAt,
    updatedAt: timestamp,
  );
}

AuthAccount _accountFromRecord(_Record r) => AuthAccount(
  providerId: r.payload['provider_id'].toString(),
  providerAccountId: r.payload['provider_account_id'].toString(),
  userId: r.payload['user_id']?.toString(),
  accessToken: r.payload['access_token']?.toString(),
  refreshToken: r.payload['refresh_token']?.toString(),
  expiresAt: _date(r.payload['expires_at']),
  metadata: r.payload['metadata'] is Map
      ? Map<String, dynamic>.from(r.payload['metadata'] as Map)
      : const {},
);

final class _OrmSessions implements AuthSessionStore {
  const _OrmSessions(this.root);
  final OrmAuthStore root;
  @override
  Future<AuthSessionRecord?> find(String tokenHash) =>
      root._transaction(() async {
        final row = await root._findKey(_sessionKey(tokenHash));
        return row == null ? null : _sessionFromRecord(row);
      });
  @override
  Future<AuthSessionRecord> create(AuthSessionRecord session) =>
      root._transaction(() async {
        validateAuthSessionForPersistence(session);
        if (await root._findKey(_sessionKey(session.tokenHash)) != null) {
          throw StateError('Auth session token hash already exists');
        }
        await root._insert(_sessionRecord(session));
        return session;
      });
  @override
  Future<AuthSessionRecord?> touch(String tokenHash, DateTime lastUsedAt) =>
      root._transaction(() async {
        final row = await root._findKey(_sessionKey(tokenHash));
        if (row == null) return null;
        final current = _sessionFromRecord(row);
        if (tokenHash.trim().isEmpty || !current.isActive(now: root._now)) {
          return null;
        }
        final updated = current.copyWith(
          lastUsedAt: lastUsedAt.isAfter(current.lastUsedAt)
              ? lastUsedAt
              : current.lastUsedAt,
        );
        await root._replace(_sessionRecord(updated));
        return updated;
      });
  @override
  Future<List<AuthSessionRecord>> listForUser(String userId) =>
      root._transaction(() async {
        final rows = await root._find(kind: 'session', ownerId: userId.trim());
        return rows.map(_sessionFromRecord).toList(growable: false);
      });
  @override
  Future<AuthSessionRecord?> revoke(String tokenHash, {DateTime? revokedAt}) =>
      root._transaction(() async {
        final row = await root._findKey(_sessionKey(tokenHash));
        if (row == null || tokenHash.trim().isEmpty) return null;
        final current = _sessionFromRecord(row);
        if (current.revokedAt != null) return current;
        final updated = current.copyWith(revokedAt: revokedAt ?? root._now);
        await root._replace(_sessionRecord(updated));
        return updated;
      });
  @override
  Future<AuthSessionRecord?> revokeById(
    String userId,
    String sessionId, {
    DateTime? revokedAt,
  }) => root._transaction(() async {
    final rows = await root._find(kind: 'session', ownerId: userId.trim());
    final row = rows
        .where((r) => r.payload['id']?.toString() == sessionId)
        .firstOrNull;
    if (row == null) return null;
    final current = _sessionFromRecord(row);
    if (current.revokedAt != null) return current;
    final updated = current.copyWith(revokedAt: revokedAt ?? root._now);
    await root._replace(_sessionRecord(updated));
    return updated;
  });
  @override
  Future<int> revokeAllForUser(String userId, {DateTime? revokedAt}) =>
      _revoke(userId.trim(), revokedAt);
  @override
  Future<int> revokeAllForUserExcept(
    String userId,
    String currentSessionId, {
    DateTime? revokedAt,
  }) => _revoke(userId.trim(), revokedAt, exceptId: currentSessionId);
  Future<int> _revoke(String userId, DateTime? revokedAt, {String? exceptId}) =>
      root._transaction(() async {
        final rows = await root._find(kind: 'session', ownerId: userId);
        var count = 0;
        for (final row in rows) {
          if (row.payload['id']?.toString() == exceptId) continue;
          final current = _sessionFromRecord(row);
          if (current.revokedAt == null) {
            await root._replace(
              _sessionRecord(
                current.copyWith(revokedAt: revokedAt ?? root._now),
              ),
            );
            count++;
          }
        }
        return count;
      });
  @override
  Future<AuthSessionRecord?> rotate({
    required String previousTokenHash,
    required AuthSessionRecord replacement,
  }) => root._transaction(() async {
    validateAuthSessionForPersistence(replacement);
    final previousRow = await root._findKey(_sessionKey(previousTokenHash));
    if (previousRow == null ||
        !_sessionFromRecord(previousRow).isActive(now: root._now)) {
      return null;
    }
    if (await root._findKey(_sessionKey(replacement.tokenHash)) != null) {
      throw StateError('Auth session token hash already exists');
    }
    await root._replace(
      _sessionRecord(
        _sessionFromRecord(previousRow).copyWith(revokedAt: root._now),
      ),
    );
    await root._insert(_sessionRecord(replacement));
    return replacement;
  });
}

_Record _sessionRecord(AuthSessionRecord value) => _Record(
  key: _sessionKey(value.tokenHash),
  kind: 'session',
  lookup: value.id,
  ownerId: value.userId,
  payload: value.toStorageJson(),
  createdAt: value.createdAt,
  expiresAt: value.expiresAt,
  updatedAt: value.lastUsedAt,
);
AuthSessionRecord _sessionFromRecord(_Record r) => AuthSessionRecord(
  id: r.payload['id'].toString(),
  tokenHash: r.payload['token_hash'].toString(),
  userId: r.payload['user_id'].toString(),
  createdAt: _date(r.payload['created_at'])!,
  expiresAt: _date(r.payload['expires_at'])!,
  lastUsedAt: _date(r.payload['last_used_at'])!,
  revokedAt: _date(r.payload['revoked_at']),
  ipAddress: r.payload['ip_address']?.toString(),
  userAgent: r.payload['user_agent']?.toString(),
  authenticationMethod: r.payload['authentication_method'].toString(),
  impersonatedBy: r.payload['impersonated_by']?.toString(),
);

final class _OrmOAuthChallenges implements AuthOAuthChallengeStore {
  const _OrmOAuthChallenges(this.root);
  final OrmAuthStore root;
  @override
  Future<void> save(AuthOAuthChallenge c) => root._transaction(() async {
    if (c.providerId.isEmpty ||
        c.state.isEmpty ||
        !c.isActive(now: root._now)) {
      throw ArgumentError('Invalid OAuth challenge');
    }
    await root._deleteKey(_oauthKey(c.providerId, c.state));
    await root._insert(
      _Record(
        key: _oauthKey(c.providerId, c.state),
        kind: 'oauth',
        lookup: c.providerId,
        ownerId: null,
        payload: {
          'provider_id': c.providerId,
          'state_hash': hashOpaqueToken(c.state),
          'code_verifier': c.codeVerifier,
          'nonce': c.nonce,
          'callback_url': c.callbackUrl,
        },
        createdAt: root._now,
        expiresAt: c.expiresAt,
        updatedAt: root._now,
      ),
    );
  });
  @override
  Future<AuthOAuthChallenge?> consume(String providerId, String state) =>
      root._transaction(() async {
        if (providerId.isEmpty || state.isEmpty) return null;
        final key = _oauthKey(providerId, state);
        final row = await root._findKey(key);
        if (row == null) return null;
        await root._deleteKey(key);
        if (row.expiresAt == null || !root._now.isBefore(row.expiresAt!)) {
          return null;
        }
        return AuthOAuthChallenge(
          providerId: providerId,
          state: state,
          expiresAt: row.expiresAt!,
          codeVerifier: row.payload['code_verifier']?.toString(),
          nonce: row.payload['nonce']?.toString(),
          callbackUrl: row.payload['callback_url']?.toString(),
        );
      });
}

final class _OrmPasswordResetTokens implements AuthPasswordResetTokenStore {
  const _OrmPasswordResetTokens(this.root);
  final OrmAuthStore root;
  @override
  Future<void> save(AuthPasswordResetToken t) => root._transaction(() async {
    if (t.userId.trim().isEmpty ||
        t.tokenHash.trim().isEmpty ||
        !t.expiresAt.isAfter(t.createdAt)) {
      throw ArgumentError('Invalid password-reset token');
    }
    await root._deleteWhere(kind: 'password_reset', ownerId: t.userId.trim());
    await root._insert(
      _Record(
        key: 'password_reset:${t.tokenHash}',
        kind: 'password_reset',
        lookup: t.tokenHash,
        ownerId: t.userId.trim(),
        payload: {
          'user_id': t.userId.trim(),
          'token_hash': t.tokenHash,
          'created_at': t.createdAt.toUtc().toIso8601String(),
          'expires_at': t.expiresAt.toUtc().toIso8601String(),
        },
        createdAt: t.createdAt,
        expiresAt: t.expiresAt,
        updatedAt: t.createdAt,
      ),
    );
  });
  @override
  Future<AuthPasswordResetToken?> consume(String token) =>
      root._transaction(() async {
        if (token.trim().isEmpty) return null;
        final hash = hashOpaqueToken(token);
        final row = await root._findKey('password_reset:$hash');
        if (row == null) return null;
        await root._deleteKey(row.key);
        if (row.expiresAt == null || !root._now.isBefore(row.expiresAt!)) {
          return null;
        }
        return _passwordResetFromRecord(row);
      });
  @override
  Future<AuthPasswordResetToken?> findActive(String token) =>
      root._transaction(() async {
        if (token.trim().isEmpty) return null;
        final row = await root._findKey(
          'password_reset:${hashOpaqueToken(token)}',
        );
        if (row == null ||
            row.expiresAt == null ||
            !root._now.isBefore(row.expiresAt!)) {
          return null;
        }
        return _passwordResetFromRecord(row);
      });
  @override
  Future<void> deleteForUser(String userId) => root._transaction(() async {
    await root._deleteWhere(kind: 'password_reset', ownerId: userId.trim());
  });
}

AuthPasswordResetToken _passwordResetFromRecord(_Record r) =>
    AuthPasswordResetToken(
      userId: r.payload['user_id'].toString(),
      tokenHash: r.payload['token_hash'].toString(),
      createdAt: _date(r.payload['created_at'])!,
      expiresAt: _date(r.payload['expires_at'])!,
    );

final class _OrmJwtVersions implements AuthJwtVersionStore {
  const _OrmJwtVersions(this.root);
  final OrmAuthStore root;
  @override
  Future<int> current(String userId) => root._transaction(() async {
    final id = userId.trim();
    if (id.isEmpty) throw ArgumentError.value(userId, 'userId');
    final row = await root._findKey('jwt:$id');
    return row == null ? 0 : (row.payload['version'] as num).toInt();
  });
  @override
  Future<int> rotate(String userId) => root._transaction(() async {
    final id = userId.trim();
    if (id.isEmpty) throw ArgumentError.value(userId, 'userId');
    final row = await root._findKey('jwt:$id');
    final next = row == null ? 1 : (row.payload['version'] as num).toInt() + 1;
    final now = root._now;
    final record = _Record(
      key: 'jwt:$id',
      kind: 'jwt',
      lookup: null,
      ownerId: id,
      payload: {'version': next},
      createdAt: row?.createdAt ?? now,
      expiresAt: null,
      updatedAt: now,
    );
    if (row == null) {
      await root._insert(record);
    } else {
      await root._replace(record);
    }
    return next;
  });
}

final class _OrmVerificationTokens
    implements
        AuthVerificationTokenStore,
        AuthVerificationTokenConditionalDeleteStore {
  const _OrmVerificationTokens(this.root);
  final OrmAuthStore root;
  @override
  Future<void> save(AuthVerificationToken t) => root._transaction(() async {
    if (t.identifier.isEmpty || t.token.isEmpty) {
      throw ArgumentError('Invalid verification token');
    }
    await root._deleteKey(_verificationKey(t.identifier, t.token));
    await root._insert(
      _Record(
        key: _verificationKey(t.identifier, t.token),
        kind: 'verification',
        lookup: t.identifier,
        ownerId: t.metadata['userId']?.toString(),
        payload: {
          'identifier': t.identifier,
          'token_hash': hashOpaqueToken(t.token),
          'metadata': t.metadata,
        },
        createdAt: root._now,
        expiresAt: t.expiresAt,
        updatedAt: root._now,
      ),
    );
  });
  @override
  Future<AuthVerificationToken?> consume(String identifier, String token) =>
      root._transaction(() async {
        if (identifier.isEmpty || token.isEmpty) return null;
        final key = _verificationKey(identifier, token);
        final row = await root._findKey(key);
        if (row == null) return null;
        await root._deleteKey(key);
        if (row.expiresAt == null || !root._now.isBefore(row.expiresAt!)) {
          return null;
        }
        return AuthVerificationToken(
          identifier: identifier,
          token: token,
          expiresAt: row.expiresAt!,
          metadata: row.payload['metadata'] is Map
              ? Map<String, dynamic>.from(row.payload['metadata'] as Map)
              : const {},
        );
      });
  @override
  Future<void> delete(String identifier) => root._transaction(() async {
    await root._deleteWhere(kind: 'verification', lookup: identifier);
  });
  @override
  Future<bool> deleteToken(String identifier, String token) =>
      root._transaction(() async {
        return await root._deleteKey(_verificationKey(identifier, token)) > 0;
      });
}

final class _OrmEmailChangeTokens
    implements
        AuthEmailChangeTokenStore,
        AuthEmailChangeTokenConditionalDeleteStore {
  const _OrmEmailChangeTokens(this.root);
  final OrmAuthStore root;
  @override
  Future<void> save(AuthEmailChangeToken t) => root._transaction(() async {
    if (t.userId.trim().isEmpty ||
        t.newEmail.trim().isEmpty ||
        t.token.trim().isEmpty) {
      throw ArgumentError('Invalid email-change token');
    }
    await root._deleteWhere(kind: 'email_change', ownerId: t.userId.trim());
    await root._insert(
      _Record(
        key: _emailChangeKey(t.token),
        kind: 'email_change',
        lookup: null,
        ownerId: t.userId.trim(),
        payload: {
          'user_id': t.userId.trim(),
          'new_email': t.newEmail.trim().toLowerCase(),
        },
        createdAt: root._now,
        expiresAt: t.expiresAt,
        updatedAt: root._now,
      ),
    );
  });
  @override
  Future<AuthEmailChangeToken?> consume(String token) =>
      root._transaction(() async {
        if (token.trim().isEmpty) return null;
        final key = _emailChangeKey(token);
        final row = await root._findKey(key);
        if (row == null) return null;
        await root._deleteKey(key);
        if (row.expiresAt == null || !root._now.isBefore(row.expiresAt!)) {
          return null;
        }
        return AuthEmailChangeToken(
          userId: row.ownerId!,
          newEmail: row.payload['new_email'].toString(),
          token: token,
          expiresAt: row.expiresAt!,
        );
      });
  @override
  Future<void> deleteForUser(String userId) => root._transaction(() async {
    await root._deleteWhere(kind: 'email_change', ownerId: userId.trim());
  });
  @override
  Future<bool> deleteTokenForUser(String userId, String token) =>
      root._transaction(() async {
        final key = _emailChangeKey(token);
        final row = await root._findKey(key);
        if (row == null || row.ownerId != userId.trim()) return false;
        await root._deleteKey(key);
        return true;
      });
}

final class _OrmDeviceAuthorizations implements AuthDeviceAuthorizationStore {
  const _OrmDeviceAuthorizations(this.root);
  final OrmAuthStore root;
  @override
  Future<AuthDeviceAuthorization> create(AuthDeviceAuthorization a) =>
      root._transaction(() async {
        if (a.id.trim().isEmpty ||
            a.deviceCodeHash.trim().isEmpty ||
            a.userCodeHash.trim().isEmpty ||
            a.clientId.trim().isEmpty ||
            a.interval <= Duration.zero ||
            !a.expiresAt.isAfter(a.createdAt)) {
          throw ArgumentError('Invalid device authorization');
        }
        if (await root._findKey(_deviceKey(a.deviceCodeHash)) != null ||
            (await root._find(
              kind: 'device',
              lookup: a.userCodeHash,
            )).isNotEmpty) {
          throw StateError('Device authorization code already exists');
        }
        await root._insert(_deviceRecord(a));
        return a;
      });
  @override
  Future<AuthDeviceAuthorizationPollResult> poll(
    String hash, {
    DateTime? now,
  }) => root._transaction(() async {
    final row = await root._findKey(_deviceKey(hash.trim()));
    if (row == null) {
      return const AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.invalid,
      );
    }
    final a = _deviceFromRecord(row);
    final current = (now ?? root._now).toUtc();
    if (a.isExpired(now: current)) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.expired,
        a,
      );
    }
    if (a.status == AuthDeviceAuthorizationStatus.denied) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.denied,
        a,
      );
    }
    if (a.status == AuthDeviceAuthorizationStatus.consumed) {
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.consumed,
        a,
      );
    }
    if (a.lastPolledAt != null &&
        current.difference(a.lastPolledAt!) < a.interval) {
      final slowed = a.copyWith(
        interval: a.interval + const Duration(seconds: 5),
      );
      await root._replace(_deviceRecord(slowed));
      return AuthDeviceAuthorizationPollResult(
        AuthDeviceAuthorizationPollStatus.slowDown,
        slowed,
      );
    }
    final updated = a.copyWith(lastPolledAt: current);
    await root._replace(_deviceRecord(updated));
    return AuthDeviceAuthorizationPollResult(
      updated.status == AuthDeviceAuthorizationStatus.approved
          ? AuthDeviceAuthorizationPollStatus.approved
          : AuthDeviceAuthorizationPollStatus.pending,
      updated,
    );
  });
  @override
  Future<AuthDeviceAuthorization?> approve(
    String userCodeHash,
    String userId, {
    DateTime? now,
  }) => _transition(
    userCodeHash,
    now,
    (a, current) =>
        a.status == AuthDeviceAuthorizationStatus.pending &&
            !a.isExpired(now: current) &&
            userId.trim().isNotEmpty
        ? a.copyWith(
            status: AuthDeviceAuthorizationStatus.approved,
            userId: userId.trim(),
            approvedAt: current,
          )
        : null,
  );
  @override
  Future<AuthDeviceAuthorization?> deny(String userCodeHash, {DateTime? now}) =>
      _transition(
        userCodeHash,
        now,
        (a, current) =>
            a.status == AuthDeviceAuthorizationStatus.pending &&
                !a.isExpired(now: current)
            ? a.copyWith(
                status: AuthDeviceAuthorizationStatus.denied,
                deniedAt: current,
              )
            : null,
      );
  Future<AuthDeviceAuthorization?> _transition(
    String hash,
    DateTime? now,
    AuthDeviceAuthorization? Function(AuthDeviceAuthorization, DateTime) change,
  ) => root._transaction(() async {
    final rows = await root._find(kind: 'device', lookup: hash.trim());
    if (rows.isEmpty) return null;
    final row = rows.first;
    final updated = change(_deviceFromRecord(row), (now ?? root._now).toUtc());
    if (updated == null) return null;
    await root._replace(_deviceRecord(updated));
    return updated;
  });
  @override
  Future<AuthDeviceAuthorizationIssuanceLeaseResult> beginIssuance(
    String hash, {
    required String clientId,
    required String leaseDigest,
    required DateTime leaseExpiresAt,
    DateTime? now,
  }) => root._transaction(() async {
    final row = await root._findKey(_deviceKey(hash.trim()));
    final current = (now ?? root._now).toUtc();
    if (row == null) {
      return const AuthDeviceAuthorizationIssuanceLeaseResult(
        AuthDeviceAuthorizationIssuanceLeaseStatus.invalid,
      );
    }
    final a = _deviceFromRecord(row);
    if (a.isExpired(now: current) ||
        a.status != AuthDeviceAuthorizationStatus.approved ||
        a.clientId != clientId.trim() ||
        leaseDigest.trim().isEmpty ||
        !leaseExpiresAt.toUtc().isAfter(current)) {
      return const AuthDeviceAuthorizationIssuanceLeaseResult(
        AuthDeviceAuthorizationIssuanceLeaseStatus.invalid,
      );
    }
    if (a.issuanceLeaseDigest != null &&
        a.issuanceLeaseExpiresAt != null &&
        current.isBefore(a.issuanceLeaseExpiresAt!)) {
      return const AuthDeviceAuthorizationIssuanceLeaseResult(
        AuthDeviceAuthorizationIssuanceLeaseStatus.busy,
      );
    }
    final expiry = leaseExpiresAt.toUtc().isBefore(a.expiresAt)
        ? leaseExpiresAt.toUtc()
        : a.expiresAt;
    final updated = a.copyWith(
      issuanceLeaseDigest: leaseDigest.trim(),
      issuanceLeaseExpiresAt: expiry,
    );
    await root._replace(_deviceRecord(updated));
    return AuthDeviceAuthorizationIssuanceLeaseResult(
      AuthDeviceAuthorizationIssuanceLeaseStatus.acquired,
      AuthDeviceAuthorizationIssuanceLease(
        authorization: updated,
        leaseDigest: leaseDigest.trim(),
        expiresAt: expiry,
      ),
    );
  });
  @override
  Future<bool> completeIssuance(
    String hash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  }) => _leaseTransition(hash, clientId, leaseDigest, now, consume: true);
  @override
  Future<bool> releaseIssuance(
    String hash, {
    required String clientId,
    required String leaseDigest,
    DateTime? now,
  }) => _leaseTransition(hash, clientId, leaseDigest, now, consume: false);
  Future<bool> _leaseTransition(
    String hash,
    String clientId,
    String digest,
    DateTime? now, {
    required bool consume,
  }) => root._transaction(() async {
    final row = await root._findKey(_deviceKey(hash.trim()));
    if (row == null) return false;
    final a = _deviceFromRecord(row);
    final current = (now ?? root._now).toUtc();
    if (a.clientId != clientId.trim() ||
        a.issuanceLeaseDigest != digest.trim() ||
        a.issuanceLeaseExpiresAt == null ||
        (!consume && a.status != AuthDeviceAuthorizationStatus.approved)) {
      return false;
    }
    if (consume && !current.isBefore(a.issuanceLeaseExpiresAt!)) return false;
    final updated = consume
        ? a.copyWith(
            status: AuthDeviceAuthorizationStatus.consumed,
            consumedAt: current,
            clearIssuanceLease: true,
          )
        : a.copyWith(clearIssuanceLease: true);
    await root._replace(_deviceRecord(updated));
    return true;
  });
  @override
  Future<void> deleteForUser(String userId) => root._transaction(() async {
    await root._deleteWhere(kind: 'device', ownerId: userId.trim());
  });
}

_Record _deviceRecord(AuthDeviceAuthorization a) => _Record(
  key: _deviceKey(a.deviceCodeHash),
  kind: 'device',
  lookup: a.userCodeHash,
  ownerId: a.userId,
  payload: a.toStorageJson(),
  createdAt: a.createdAt,
  expiresAt: a.expiresAt,
  updatedAt: a.lastPolledAt ?? a.createdAt,
);
AuthDeviceAuthorization _deviceFromRecord(_Record r) {
  final p = r.payload;
  AuthDeviceAuthorizationStatus status;
  status = AuthDeviceAuthorizationStatus.values.firstWhere(
    (v) => v.name == p['status'],
    orElse: () => AuthDeviceAuthorizationStatus.pending,
  );
  return AuthDeviceAuthorization(
    id: p['id'].toString(),
    deviceCodeHash: p['device_code_hash'].toString(),
    userCodeHash: p['user_code_hash'].toString(),
    clientId: p['client_id'].toString(),
    scopes: (p['scopes'] as List? ?? const [])
        .map((v) => v.toString())
        .toList(),
    createdAt: _date(p['created_at'])!,
    expiresAt: _date(p['expires_at'])!,
    interval: Duration(seconds: (p['interval_seconds'] as num).toInt()),
    status: status,
    userId: p['user_id']?.toString(),
    approvedAt: _date(p['approved_at']),
    deniedAt: _date(p['denied_at']),
    lastPolledAt: _date(p['last_polled_at']),
    issuanceLeaseDigest: p['issuance_lease_digest']?.toString(),
    issuanceLeaseExpiresAt: _date(p['issuance_lease_expires_at']),
    consumedAt: _date(p['consumed_at']),
  );
}

final class _OrmEmailOtps implements AuthEmailOtpStore {
  const _OrmEmailOtps(this.root);
  final OrmAuthStore root;
  @override
  Future<void> save(AuthEmailOtp otp) => root._transaction(() async {
    await root._deleteKey(_otpKey(otp.email, otp.type));
    await root._insert(_otpRecord(otp));
  });
  @override
  Future<AuthEmailOtpVerificationResult> verifyDigest(
    String email,
    AuthEmailOtpType type,
    String codeHash, {
    DateTime? now,
  }) => root._transaction(() async {
    final row = await root._findKey(_otpKey(email, type));
    final current = (now ?? root._now).toUtc();
    if (row == null) {
      return const AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.invalid,
      );
    }
    final otp = _otpFromRecord(row);
    if (otp.consumed) {
      return AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.invalid,
        otp,
      );
    }
    if (otp.isExpired(now: current)) {
      return AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.expired,
        otp,
      );
    }
    if (otp.attempts >= otp.maxAttempts) {
      return AuthEmailOtpVerificationResult(
        AuthEmailOtpVerificationStatus.tooManyAttempts,
        otp,
      );
    }
    if (!constantTimeStringEquals(codeHash, otp.codeHash)) {
      final updated = otp.copyWith(attempts: otp.attempts + 1);
      await root._replace(_otpRecord(updated));
      return AuthEmailOtpVerificationResult(
        updated.attempts >= updated.maxAttempts
            ? AuthEmailOtpVerificationStatus.tooManyAttempts
            : AuthEmailOtpVerificationStatus.invalid,
        updated,
      );
    }
    final consumed = otp.copyWith(attempts: otp.attempts + 1, consumed: true);
    await root._replace(_otpRecord(consumed));
    return AuthEmailOtpVerificationResult(
      AuthEmailOtpVerificationStatus.verified,
      consumed,
    );
  });
  @override
  Future<void> deleteForEmail(String email) => root._transaction(() async {
    final normalized = normalizeAuthEmailOtpEmail(email);
    await root._deleteWhere(kind: 'otp', lookup: normalized);
  });
}

_Record _otpRecord(AuthEmailOtp a) => _Record(
  key: _otpKey(a.email, a.type),
  kind: 'otp',
  lookup: normalizeAuthEmailOtpEmail(a.email),
  ownerId: null,
  payload: a.toStorageJson(),
  createdAt: a.createdAt,
  expiresAt: a.expiresAt,
  updatedAt: a.createdAt,
);
AuthEmailOtp _otpFromRecord(_Record r) {
  final p = r.payload;
  return AuthEmailOtp(
    id: p['id'].toString(),
    email: p['email'].toString(),
    codeHash: p['code_hash'].toString(),
    type: AuthEmailOtpType.values.firstWhere(
      (v) => v.name == p['type'],
      orElse: () => AuthEmailOtpType.signIn,
    ),
    createdAt: _date(p['created_at'])!,
    expiresAt: _date(p['expires_at'])!,
    maxAttempts: (p['max_attempts'] as num).toInt(),
    attempts: (p['attempts'] as num).toInt(),
    consumed: p['consumed'] == true,
  );
}

final class _OrmAuthUserDeletionDomain implements AuthUserDeletionDomain {
  const _OrmAuthUserDeletionDomain();
}

final class _OrmUserDeletionCoordinator
    implements
        AuthUserDeletionCoordinator,
        AuthHistoricalUserDeletionNamespaceCoordinator {
  _OrmUserDeletionCoordinator(this.root);

  final OrmAuthStore root;
  @override
  final AuthUserDeletionDomain domain = const _OrmAuthUserDeletionDomain();
  List<AuthUserDeletionPlanContributor> _contributors = const [];
  Set<String> _historical = const {};
  bool _bound = false;
  bool _historicalBound = false;

  @override
  Set<String> get requiredUserDeletionNamespaces => {
    for (final contributor in _contributors)
      contributor.userDataNamespace.trim().toLowerCase(),
  };

  void bind(Iterable<AuthUserDeletionPlanContributor> contributors) {
    if (_bound) {
      throw StateError('Auth deletion contributors are already bound.');
    }
    final values = contributors.toList(growable: false);
    final namespaces = <String>{};
    for (final contributor in values) {
      final namespace = contributor.userDataNamespace;
      final normalized = namespace.trim().toLowerCase();
      if (normalized != namespace ||
          normalized.isEmpty ||
          normalized.length > 64 ||
          normalized.contains(RegExp(r'[\u0000-\u001f\u007f]')) ||
          !namespaces.add(normalized)) {
        throw StateError(
          'Auth deletion contributor namespaces must be unique, bounded, and '
          'canonical.',
        );
      }
    }
    _contributors = List<AuthUserDeletionPlanContributor>.unmodifiable(values);
    _bound = true;
  }

  @override
  void bindHistoricalUserDeletionNamespaces(Iterable<String> namespaces) {
    if (!_bound || _historicalBound) {
      throw StateError('Auth deletion topology is already bound or not ready.');
    }
    final values = <String>{};
    for (final value in namespaces) {
      final normalized = value.trim().toLowerCase();
      if (normalized != value ||
          normalized.isEmpty ||
          normalized.length > 64 ||
          normalized.contains(RegExp(r'[\u0000-\u001f\u007f]')) ||
          !values.add(normalized)) {
        throw ArgumentError.value(
          namespaces,
          'historicalUserDataNamespaces',
          'must contain unique, bounded, canonical namespace values',
        );
      }
    }
    _historical = Set<String>.unmodifiable(values);
    _historicalBound = true;
  }

  @override
  Future<List<AuthUserDeletionPlan>> plansForUser(AuthUser user) async {
    if (!_bound) {
      throw StateError('Auth deletion contributor topology is not bound.');
    }
    return List<AuthUserDeletionPlan>.unmodifiable([
      for (final contributor in _contributors)
        await contributor.createUserDeletionPlan(user),
    ]);
  }

  @override
  Future<bool> deleteUser(
    String userId, {
    Iterable<AuthUserDeletionPlan>? plans,
  }) => _delete(userId: userId, plans: plans, token: null);

  @override
  Future<bool> confirmAndDeleteUser({
    required String userId,
    required String token,
    Iterable<AuthUserDeletionPlan>? plans,
    DateTime? now,
  }) => _delete(userId: userId, plans: plans, token: token);

  Future<bool> _delete({
    required String userId,
    required Iterable<AuthUserDeletionPlan>? plans,
    required String? token,
  }) async {
    final id = userId.trim();
    if (id.isEmpty || !_bound || (token != null && token.trim().isEmpty)) {
      return false;
    }
    final activeNamespaces = {
      for (final contributor in _contributors)
        contributor.userDataNamespace.trim().toLowerCase(),
    };
    if (!activeNamespaces.containsAll(_historical)) return false;
    final existing = await root.users.findById(id);
    if (existing == null) return false;
    // Contributor plan construction may validate through its typed store.
    // Build plans before entering the shared operation gate; transactional
    // drivers apply them atomically, while D1 applies them in order.
    final resolved = plans == null
        ? await plansForUser(existing)
        : plans.toList();
    return root.runDeletionTransaction(() async {
      final row = await root._findKey(_userKey(id));
      if (row == null) return false;
      final validated = AuthUserDeletionPreflight.validate(
        userId: id,
        plans: resolved,
        requiredNamespaces: requiredUserDeletionNamespaces,
        domain: domain,
        isSupported: (plan) => plan is AuthDurableUserDeletionPlan,
      );
      if (token != null &&
          !await root.consumeDeletionTokenInTransaction(id, token)) {
        return false;
      }
      for (final plan in validated.cast<AuthDurableUserDeletionPlan>()) {
        await plan.apply();
      }
      return root._deleteCore(id);
    });
  }
}
