import 'package:routed_node/cloudflare.dart';

/// One immutable Cloudflare D1 auth schema migration.
final class CloudflareD1AuthMigration {
  const CloudflareD1AuthMigration({
    required this.version,
    required this.statements,
  });

  final int version;
  final List<String> statements;
}

/// Typed schema configuration for [CloudflareD1AuthStore].
final class CloudflareD1AuthSchema {
  const CloudflareD1AuthSchema({this.tablePrefix = 'routed_auth'});

  /// Prefix applied to every table owned by this adapter.
  ///
  /// Prefixes make deterministic and live conformance fixtures independently
  /// disposable without sharing rows. Only ASCII letters, digits, and
  /// underscores are accepted because SQLite cannot bind identifiers.
  final String tablePrefix;

  static const int currentVersion = 9;

  String table(String suffix) {
    final prefix = tablePrefix.trim();
    final identifier = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
    if (!identifier.hasMatch(prefix)) {
      throw ArgumentError.value(
        tablePrefix,
        'tablePrefix',
        'must start with a letter and contain only letters, digits, or _',
      );
    }
    if (!identifier.hasMatch(suffix)) {
      throw ArgumentError.value(
        suffix,
        'suffix',
        'must start with a letter and contain only letters, digits, or _',
      );
    }
    return '${prefix}_$suffix';
  }

  List<CloudflareD1AuthMigration> get migrations => [
    CloudflareD1AuthMigration(version: 1, statements: _versionOne),
    CloudflareD1AuthMigration(version: 2, statements: _versionTwo),
    CloudflareD1AuthMigration(version: 3, statements: _versionThree),
    CloudflareD1AuthMigration(version: 4, statements: _versionFour),
    CloudflareD1AuthMigration(version: 5, statements: _versionFive),
    CloudflareD1AuthMigration(version: 6, statements: _versionSix),
    CloudflareD1AuthMigration(version: 7, statements: _versionSeven),
    CloudflareD1AuthMigration(version: 8, statements: _versionEight),
    CloudflareD1AuthMigration(version: 9, statements: _versionNine),
  ];

  List<String> get _versionNine {
    final apiKeys = table('api_keys');
    return [
      '''CREATE TABLE IF NOT EXISTS $apiKeys (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        key_prefix TEXT NOT NULL,
        secret_hash TEXT NOT NULL UNIQUE,
        scopes TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        expires_at TEXT,
        last_used_at TEXT,
        revoked_at TEXT,
        rotation_marker TEXT UNIQUE
      )''',
      'CREATE INDEX IF NOT EXISTS ${apiKeys}_user '
          'ON $apiKeys(user_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS ${apiKeys}_active '
          'ON $apiKeys(user_id, revoked_at, expires_at)',
    ];
  }

  List<String> get _versionSeven {
    final guards = table('anonymous_mutation_guards');
    final receipts = table('anonymous_mutation_receipts');
    return [
      '''CREATE TABLE IF NOT EXISTS $guards (
        operation_id_hash TEXT PRIMARY KEY,
        fingerprint_hash TEXT NOT NULL,
        subject_user_id_hash TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS $receipts (
        operation_id_hash TEXT PRIMARY KEY,
        operation_type TEXT NOT NULL
          CHECK (operation_type IN ('create', 'delete', 'upgrade')),
        fingerprint_hash TEXT NOT NULL,
        subject_user_id_hash TEXT NOT NULL,
        target_user_id_hash TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        CHECK (
          (operation_type = 'upgrade' AND target_user_id_hash IS NOT NULL) OR
          (operation_type <> 'upgrade' AND target_user_id_hash IS NULL)
        )
      )''',
      'CREATE INDEX IF NOT EXISTS ${receipts}_subject '
          'ON $receipts(subject_user_id_hash)',
      'CREATE INDEX IF NOT EXISTS ${receipts}_expiry '
          'ON $receipts(expires_at, created_at)',
    ];
  }

  List<String> get _versionSix {
    final connections = table('scim_connections');
    final credentials = table('scim_credentials');
    final replays = table('scim_replays');
    return [
      '''CREATE TABLE IF NOT EXISTS $connections (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        organization_id TEXT NOT NULL,
        provisioning_domain_id TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        name TEXT NOT NULL,
        scopes TEXT NOT NULL,
        scope_mask INTEGER NOT NULL CHECK (scope_mask > 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        disabled_at TEXT
      )''',
      'CREATE INDEX IF NOT EXISTS ${connections}_binding '
          'ON $connections(tenant_id, organization_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS ${connections}_subject '
          'ON $connections(subject_id)',
      'CREATE INDEX IF NOT EXISTS ${connections}_tenant '
          'ON $connections(tenant_id)',
      '''CREATE TABLE IF NOT EXISTS $credentials (
        id TEXT PRIMARY KEY,
        connection_id TEXT NOT NULL,
        tenant_id TEXT NOT NULL,
        organization_id TEXT NOT NULL,
        name TEXT NOT NULL,
        key_prefix TEXT NOT NULL,
        secret_digest TEXT NOT NULL UNIQUE,
        scopes TEXT NOT NULL,
        scope_mask INTEGER NOT NULL CHECK (scope_mask > 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        expires_at TEXT,
        last_used_at TEXT,
        revoked_at TEXT,
        FOREIGN KEY(connection_id) REFERENCES $connections(id)
          ON DELETE CASCADE
      )''',
      'CREATE INDEX IF NOT EXISTS ${credentials}_connection '
          'ON $credentials(connection_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS ${credentials}_binding '
          'ON $credentials(tenant_id, organization_id)',
      '''CREATE TABLE IF NOT EXISTS $replays (
        tenant_id TEXT NOT NULL,
        organization_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        credential_id TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        PRIMARY KEY(
          tenant_id,
          organization_id,
          operation,
          idempotency_key
        ),
        FOREIGN KEY(connection_id) REFERENCES $connections(id)
          ON DELETE CASCADE,
        FOREIGN KEY(credential_id) REFERENCES $credentials(id)
          ON DELETE CASCADE
      )''',
      'CREATE INDEX IF NOT EXISTS ${replays}_expiry ON $replays(expires_at)',
      'CREATE INDEX IF NOT EXISTS ${replays}_connection '
          'ON $replays(connection_id)',
    ];
  }

  List<String> get _versionFour {
    final clients = table('oauth_clients');
    final authorizationCodes = table('oauth_authorization_codes');
    final accessTokens = table('oauth_access_tokens');
    return [
      '''CREATE TABLE IF NOT EXISTS $clients (
        client_id TEXT PRIMARY KEY,
        client_secret_hash TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        redirect_uris TEXT NOT NULL,
        grant_types TEXT NOT NULL,
        scopes TEXT NOT NULL,
        token_endpoint_auth_method TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1))
      )''',
      '''CREATE TABLE IF NOT EXISTS $authorizationCodes (
        code_hash TEXT PRIMARY KEY,
        authorization_id TEXT NOT NULL UNIQUE,
        client_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        redirect_uri TEXT NOT NULL,
        scope TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        code_challenge TEXT,
        code_challenge_method TEXT,
        nonce TEXT,
        created_at TEXT,
        CHECK (
          (code_challenge IS NULL AND code_challenge_method IS NULL) OR
          (code_challenge IS NOT NULL AND code_challenge_method = 'S256')
        )
      )''',
      'CREATE INDEX IF NOT EXISTS ${authorizationCodes}_user '
          'ON $authorizationCodes(user_id)',
      'CREATE INDEX IF NOT EXISTS ${authorizationCodes}_client '
          'ON $authorizationCodes(client_id)',
      'CREATE INDEX IF NOT EXISTS ${authorizationCodes}_expiry '
          'ON $authorizationCodes(expires_at)',
      '''CREATE TABLE IF NOT EXISTS $accessTokens (
        token_hash TEXT PRIMARY KEY,
        authorization_id TEXT UNIQUE,
        client_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        scope TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        refresh_token_hash TEXT UNIQUE,
        refresh_token_expires_at TEXT,
        refresh_token_uses INTEGER NOT NULL DEFAULT 0
          CHECK (refresh_token_uses >= 0),
        issued_at TEXT
      )''',
      'CREATE INDEX IF NOT EXISTS ${accessTokens}_user '
          'ON $accessTokens(user_id)',
      'CREATE INDEX IF NOT EXISTS ${accessTokens}_client '
          'ON $accessTokens(client_id)',
      'CREATE INDEX IF NOT EXISTS ${accessTokens}_expiry '
          'ON $accessTokens(expires_at, refresh_token_expires_at)',
    ];
  }

  List<String> get _versionFive {
    final guards = table('username_mutation_guards');
    return [
      '''CREATE TABLE IF NOT EXISTS $guards (
        operation_key TEXT PRIMARY KEY,
        operation TEXT NOT NULL,
        user_id TEXT NOT NULL,
        credential_id TEXT NOT NULL,
        expected_username TEXT,
        target_username TEXT,
        created_at TEXT NOT NULL
      )''',
    ];
  }

  List<String> get _versionEight {
    final magicLinks = table('magic_links');
    final emailOtps = table('email_otps');
    return [
      '''CREATE TABLE IF NOT EXISTS $magicLinks (
        provider_id TEXT NOT NULL,
        email TEXT COLLATE NOCASE NOT NULL,
        token_hash TEXT NOT NULL,
        issued_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        consumption_marker TEXT,
        PRIMARY KEY(provider_id, email)
      )''',
      'CREATE INDEX IF NOT EXISTS ${magicLinks}_expiry ON $magicLinks(expires_at)',
      'ALTER TABLE $emailOtps ADD COLUMN verification_marker TEXT',
    ];
  }

  List<String> get _versionThree {
    final deviceAuthorizations = table('device_authorizations');
    return [
      'ALTER TABLE $deviceAuthorizations ADD COLUMN issuance_lease_digest TEXT',
      'ALTER TABLE $deviceAuthorizations ADD COLUMN issuance_lease_expires_at TEXT',
      'ALTER TABLE $deviceAuthorizations ADD COLUMN consumed_at TEXT',
      'CREATE INDEX IF NOT EXISTS ${deviceAuthorizations}_issuance_lease '
          'ON $deviceAuthorizations(issuance_lease_expires_at)',
    ];
  }

  List<String> get _versionTwo {
    final deletionReceipts = table('deletion_receipts');
    return [
      '''CREATE TABLE IF NOT EXISTS $deletionReceipts (
        user_id_hash TEXT PRIMARY KEY,
        deleted_at TEXT NOT NULL
      )''',
    ];
  }

  List<String> get _versionOne {
    final users = table('users');
    final credentials = table('credentials');
    final accounts = table('accounts');
    final sessions = table('sessions');
    final oauthChallenges = table('oauth_challenges');
    final passwordResetTokens = table('password_reset_tokens');
    final jwtVersions = table('jwt_versions');
    final verificationTokens = table('verification_tokens');
    final emailChangeTokens = table('email_change_tokens');
    final deviceAuthorizations = table('device_authorizations');
    final emailOtps = table('email_otps');
    return [
      '''CREATE TABLE IF NOT EXISTS $users (
        id TEXT PRIMARY KEY,
        email TEXT COLLATE NOCASE UNIQUE,
        payload TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS $credentials (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        identifier TEXT COLLATE NOCASE NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $users(id) ON DELETE CASCADE
      )''',
      'CREATE INDEX IF NOT EXISTS ${credentials}_user ON $credentials(user_id)',
      '''CREATE TABLE IF NOT EXISTS $accounts (
        provider_id TEXT NOT NULL,
        provider_account_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY(provider_id, provider_account_id)
      )''',
      'CREATE INDEX IF NOT EXISTS ${accounts}_user ON $accounts(user_id)',
      '''CREATE TABLE IF NOT EXISTS $sessions (
        id TEXT NOT NULL UNIQUE,
        token_hash TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        last_used_at TEXT NOT NULL,
        revoked_at TEXT,
        payload TEXT NOT NULL
      )''',
      'CREATE INDEX IF NOT EXISTS ${sessions}_user ON $sessions(user_id)',
      '''CREATE TABLE IF NOT EXISTS $oauthChallenges (
        provider_id TEXT NOT NULL,
        state_hash TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY(provider_id, state_hash)
      )''',
      '''CREATE TABLE IF NOT EXISTS $passwordResetTokens (
        user_id TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS $jwtVersions (
        user_id TEXT PRIMARY KEY,
        version INTEGER NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS $verificationTokens (
        identifier TEXT NOT NULL,
        token_hash TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        metadata TEXT NOT NULL,
        PRIMARY KEY(identifier, token_hash)
      )''',
      '''CREATE TABLE IF NOT EXISTS $emailChangeTokens (
        user_id TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        new_email TEXT COLLATE NOCASE NOT NULL,
        expires_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS $deviceAuthorizations (
        device_code_hash TEXT PRIMARY KEY,
        user_code_hash TEXT NOT NULL UNIQUE,
        user_id TEXT,
        status TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        payload TEXT NOT NULL
      )''',
      'CREATE INDEX IF NOT EXISTS ${deviceAuthorizations}_user ON $deviceAuthorizations(user_id)',
      '''CREATE TABLE IF NOT EXISTS $emailOtps (
        email TEXT COLLATE NOCASE NOT NULL,
        type TEXT NOT NULL,
        code_hash TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY(email, type)
      )''',
    ];
  }

  /// Applies all adapter-owned migrations atomically, one version at a time.
  Future<void> migrate(CloudflareD1Database database) async {
    final migrationTable = table('migrations');
    final bootstrap = await database.prepare(
      '''CREATE TABLE IF NOT EXISTS $migrationTable (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
          )''',
    ).run<Object?>();
    if (!bootstrap.success) {
      throw StateError(
        'Creating D1 auth migration table failed: ${bootstrap.error}',
      );
    }
    final appliedResult = await database
        .prepare('SELECT version FROM $migrationTable')
        .all<int>(decode: (row) => (row['version'] as num).toInt());
    if (!appliedResult.success) {
      throw StateError(
        'Reading D1 auth migrations failed: ${appliedResult.error}',
      );
    }
    final applied = appliedResult.results.toSet();
    for (final migration in migrations) {
      if (applied.contains(migration.version)) continue;
      final statements = <CloudflareD1PreparedStatement>[
        for (final sql in migration.statements) database.prepare(sql),
        database
            .prepare(
              'INSERT OR IGNORE INTO $migrationTable '
              '(version, applied_at) VALUES (?, ?)',
            )
            .bind([
              migration.version,
              DateTime.now().toUtc().toIso8601String(),
            ]),
      ];
      final results = await database.batch<Object?>(statements);
      final failed = results.where((result) => !result.success).firstOrNull;
      if (failed != null) {
        throw StateError(
          'D1 auth migration ${migration.version} failed: ${failed.error}',
        );
      }
    }
  }

  /// Drops every table owned by this schema prefix.
  ///
  /// This exists for isolated test fixtures. Production applications should
  /// retain migration history and never call it during normal operation.
  Future<void> dropAll(CloudflareD1Database database) async {
    final suffixes = [
      'api_keys',
      'anonymous_mutation_guards',
      'anonymous_mutation_receipts',
      'scim_replays',
      'scim_credentials',
      'scim_connections',
      'oauth_access_tokens',
      'oauth_authorization_codes',
      'oauth_clients',
      'username_mutation_guards',
      'deletion_receipts',
      'magic_links',
      'email_otps',
      'device_authorizations',
      'email_change_tokens',
      'verification_tokens',
      'jwt_versions',
      'password_reset_tokens',
      'oauth_challenges',
      'sessions',
      'accounts',
      'credentials',
      'users',
      'migrations',
    ];
    final results = await database.batch<Object?>([
      for (final suffix in suffixes)
        database.prepare('DROP TABLE IF EXISTS ${table(suffix)}'),
    ]);
    final failed = results.where((result) => !result.success).firstOrNull;
    if (failed != null) {
      throw StateError('Dropping D1 auth schema failed: ${failed.error}');
    }
  }
}
