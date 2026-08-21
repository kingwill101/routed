import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:sqlite3/sqlite3.dart';

/// A Dart IO [AuthStore] backed by a SQLite database.
///
/// The store inherits the typed plugin capabilities of the SQL auth adapter,
/// while this package supplies the local SQLite binding needed by Dart IO.
/// Call [open] or one of its convenience constructors before using a new
/// database so the adapter migrations are applied.
class SqliteAuthStore extends CloudflareD1AuthStore {
  /// Creates a store over an already-open SQLite database.
  ///
  /// Prefer [open], [openPath], or [openInMemory] for new databases. The
  /// caller owns [database] and must call [close] when the store is no longer
  /// needed.
  SqliteAuthStore(
    Database database, {
    super.schema = const CloudflareD1AuthSchema(),
    super.scimReplayTtl = const Duration(days: 1),
    super.anonymousReplayTtl = const Duration(days: 1),
    super.anonymousMaxReceipts = 10000,
    super.apiKeyMaxRecords = 10000,
    super.webAuthnChallengeMaxRecords = 10000,
    super.webAuthnAuthenticatorMaxRecords = 10000,
    super.phoneNumberMaxVerifications = 2048,
    super.historicalAuthenticationMethodNamespaces = const [],
    super.clock,
  }) : _database = database,
       super(_SqliteD1Database(database)) {
    _database.execute('PRAGMA foreign_keys = ON');
  }

  /// Opens [database], applies migrations, and returns a ready store.
  static Future<SqliteAuthStore> open(
    Database database, {
    CloudflareD1AuthSchema schema = const CloudflareD1AuthSchema(),
    Duration scimReplayTtl = const Duration(days: 1),
    Duration anonymousReplayTtl = const Duration(days: 1),
    int anonymousMaxReceipts = 10000,
    int apiKeyMaxRecords = 10000,
    int webAuthnChallengeMaxRecords = 10000,
    int webAuthnAuthenticatorMaxRecords = 10000,
    int phoneNumberMaxVerifications = 2048,
    Iterable<String> historicalAuthenticationMethodNamespaces = const [],
    DateTime Function()? clock,
  }) async {
    final sql = _SqliteD1Database(database);
    await schema.migrate(sql);
    return SqliteAuthStore(
      database,
      schema: schema,
      scimReplayTtl: scimReplayTtl,
      anonymousReplayTtl: anonymousReplayTtl,
      anonymousMaxReceipts: anonymousMaxReceipts,
      apiKeyMaxRecords: apiKeyMaxRecords,
      webAuthnChallengeMaxRecords: webAuthnChallengeMaxRecords,
      webAuthnAuthenticatorMaxRecords: webAuthnAuthenticatorMaxRecords,
      phoneNumberMaxVerifications: phoneNumberMaxVerifications,
      historicalAuthenticationMethodNamespaces:
          historicalAuthenticationMethodNamespaces,
      clock: clock,
    );
  }

  /// Opens a SQLite database at [path] and applies adapter migrations.
  static Future<SqliteAuthStore> openPath(
    String path, {
    CloudflareD1AuthSchema schema = const CloudflareD1AuthSchema(),
    Duration scimReplayTtl = const Duration(days: 1),
    Duration anonymousReplayTtl = const Duration(days: 1),
    int anonymousMaxReceipts = 10000,
    int apiKeyMaxRecords = 10000,
    int webAuthnChallengeMaxRecords = 10000,
    int webAuthnAuthenticatorMaxRecords = 10000,
    int phoneNumberMaxVerifications = 2048,
    Iterable<String> historicalAuthenticationMethodNamespaces = const [],
    DateTime Function()? clock,
  }) async {
    final database = sqlite3.open(p.normalize(path));
    try {
      return await open(
        database,
        schema: schema,
        scimReplayTtl: scimReplayTtl,
        anonymousReplayTtl: anonymousReplayTtl,
        anonymousMaxReceipts: anonymousMaxReceipts,
        apiKeyMaxRecords: apiKeyMaxRecords,
        webAuthnChallengeMaxRecords: webAuthnChallengeMaxRecords,
        webAuthnAuthenticatorMaxRecords: webAuthnAuthenticatorMaxRecords,
        phoneNumberMaxVerifications: phoneNumberMaxVerifications,
        historicalAuthenticationMethodNamespaces:
            historicalAuthenticationMethodNamespaces,
        clock: clock,
      );
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  /// Opens an isolated in-memory SQLite database and applies migrations.
  static Future<SqliteAuthStore> openInMemory({
    CloudflareD1AuthSchema schema = const CloudflareD1AuthSchema(),
    Duration scimReplayTtl = const Duration(days: 1),
    Duration anonymousReplayTtl = const Duration(days: 1),
    int anonymousMaxReceipts = 10000,
    int apiKeyMaxRecords = 10000,
    int webAuthnChallengeMaxRecords = 10000,
    int webAuthnAuthenticatorMaxRecords = 10000,
    int phoneNumberMaxVerifications = 2048,
    Iterable<String> historicalAuthenticationMethodNamespaces = const [],
    DateTime Function()? clock,
  }) async {
    final database = sqlite3.openInMemory();
    try {
      return await open(
        database,
        schema: schema,
        scimReplayTtl: scimReplayTtl,
        anonymousReplayTtl: anonymousReplayTtl,
        anonymousMaxReceipts: anonymousMaxReceipts,
        apiKeyMaxRecords: apiKeyMaxRecords,
        webAuthnChallengeMaxRecords: webAuthnChallengeMaxRecords,
        webAuthnAuthenticatorMaxRecords: webAuthnAuthenticatorMaxRecords,
        phoneNumberMaxVerifications: phoneNumberMaxVerifications,
        historicalAuthenticationMethodNamespaces:
            historicalAuthenticationMethodNamespaces,
        clock: clock,
      );
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  /// The underlying SQLite connection for advanced local administration.
  Database get database => _database;

  /// Closes the caller-owned SQLite connection.
  void close() => _database.close();

  final Database _database;
}

final class _SqliteD1Database implements CloudflareD1Database {
  const _SqliteD1Database(this.database);

  final Database database;

  @override
  CloudflareD1PreparedStatement prepare(String query) =>
      _SqliteD1PreparedStatement(database, query, const []);

  @override
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    final prepared = statements.toList(growable: false);
    if (prepared.any((statement) => statement is! _SqliteD1PreparedStatement)) {
      throw ArgumentError('Batch statements must belong to this SQLite store.');
    }

    database.execute('BEGIN IMMEDIATE');
    try {
      final results = <CloudflareD1Result<T>>[];
      for (final statement in prepared.cast<_SqliteD1PreparedStatement>()) {
        results.add(statement.runSync(decode: decode));
      }
      database.execute('COMMIT');
      return results;
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<CloudflareD1ExecResult> exec(String query) async {
    database.execute(query);
    return CloudflareD1ExecResult(count: database.updatedRows, duration: 0);
  }

  @override
  Future<Uint8List> dump() async => Uint8List(0);

  @override
  CloudflareD1DatabaseSession withSession({String? bookmark}) =>
      _SqliteD1Session(this, bookmark);
}

final class _SqliteD1PreparedStatement
    implements CloudflareD1PreparedStatement {
  const _SqliteD1PreparedStatement(this.database, this.query, this.values);

  final Database database;
  final String query;
  final List<Object?> values;

  @override
  CloudflareD1PreparedStatement bind([Iterable<Object?> values = const []]) =>
      _SqliteD1PreparedStatement(
        database,
        query,
        values.toList(growable: false),
      );

  @override
  Future<CloudflareD1Result<T>> all<T>({
    CloudflareD1RowDecoder<T>? decode,
  }) async => allSync(decode: decode);

  CloudflareD1Result<T> allSync<T>({CloudflareD1RowDecoder<T>? decode}) {
    final rows = database.select(query, values);
    return CloudflareD1Result<T>(
      success: true,
      results: [for (final row in rows) _decode(row, decode)],
      meta: CloudflareD1Meta(
        rowsRead: rows.length,
        changes: database.updatedRows,
        lastRowId: database.lastInsertRowId,
      ),
    );
  }

  @override
  Future<T?> first<T>({
    String? column,
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    final result = allSync<T>(decode: decode);
    if (result.results.isEmpty) return null;
    if (column == null) return result.results.first;
    final row = database.select(query, values).firstOrNull;
    return row?[column] as T?;
  }

  @override
  Future<CloudflareD1Result<T>> run<T>({
    CloudflareD1RowDecoder<T>? decode,
  }) async => runSync(decode: decode);

  CloudflareD1Result<T> runSync<T>({CloudflareD1RowDecoder<T>? decode}) {
    if (_returnsRows(query)) return allSync<T>(decode: decode);
    database.execute(query, values);
    return CloudflareD1Result<T>(
      success: true,
      meta: CloudflareD1Meta(
        rowsWritten: database.updatedRows,
        changes: database.updatedRows,
        lastRowId: database.lastInsertRowId,
      ),
    );
  }

  @override
  Future<List<T>> raw<T>({CloudflareD1RowDecoder<T>? decode}) async =>
      (await all<T>(decode: decode)).results;

  T _decode<T>(Row row, CloudflareD1RowDecoder<T>? decode) {
    final value = <String, Object?>{
      for (final column in row.keys) column: row[column],
    };
    return decode == null ? value as T : decode(value);
  }

  static bool _returnsRows(String sql) {
    final normalized = sql.trimLeft().toUpperCase();
    return normalized.startsWith('SELECT') ||
        normalized.startsWith('WITH') ||
        normalized.contains(' RETURNING ');
  }
}

final class _SqliteD1Session implements CloudflareD1DatabaseSession {
  const _SqliteD1Session(this.database, this.bookmark);

  final _SqliteD1Database database;
  final String? bookmark;

  @override
  CloudflareD1PreparedStatement prepare(String query) =>
      database.prepare(query);

  @override
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  }) => database.batch(statements, decode: decode);

  @override
  Future<String?> getBookmark() async => bookmark ?? 'sqlite-primary';
}
