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

  static const int currentVersion = 2;

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
  ];

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
      'deletion_receipts',
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
