import 'dart:typed_data';

import 'package:routed_node/cloudflare.dart';
import 'package:sqlite3/sqlite3.dart';

/// Deterministic SQLite-backed implementation of the public D1 contract.
///
/// It executes the adapter's actual SQL and gives `batch()` the same
/// all-or-nothing behavior as Cloudflare D1. It is a local compatibility fake,
/// not evidence that the suite ran inside a deployed Worker.
final class FakeCloudflareD1Database implements CloudflareD1Database {
  FakeCloudflareD1Database() : _database = sqlite3.openInMemory() {
    _database.execute('PRAGMA foreign_keys = ON');
  }

  final Database _database;

  void close() => _database.close();

  List<Map<String, Object?>> select(
    String query, [
    List<Object?> values = const [],
  ]) => [
    for (final row in _database.select(query, values))
      <String, Object?>{for (final key in row.keys) key: row[key]},
  ];

  @override
  CloudflareD1PreparedStatement prepare(String query) =>
      _FakePreparedStatement(_database, query, const []);

  @override
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    final prepared = statements.toList(growable: false);
    if (prepared.any((statement) => statement is! _FakePreparedStatement)) {
      throw ArgumentError('Batch statements must belong to this fake D1.');
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      final results = <CloudflareD1Result<T>>[];
      for (final statement in prepared.cast<_FakePreparedStatement>()) {
        results.add(statement.runSync<T>(decode: decode));
      }
      _database.execute('COMMIT');
      return results;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<CloudflareD1ExecResult> exec(String query) async {
    _database.execute(query);
    return CloudflareD1ExecResult(count: _database.updatedRows, duration: 0);
  }

  @override
  Future<Uint8List> dump() async => Uint8List(0);

  @override
  CloudflareD1DatabaseSession withSession({String? bookmark}) =>
      _FakeD1Session(this, bookmark);
}

final class _FakePreparedStatement implements CloudflareD1PreparedStatement {
  const _FakePreparedStatement(this.database, this.query, this.values);

  final Database database;
  final String query;
  final List<Object?> values;

  @override
  CloudflareD1PreparedStatement bind([Iterable<Object?> values = const []]) =>
      _FakePreparedStatement(database, query, values.toList(growable: false));

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
    final result = await all<T>(decode: decode);
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

final class _FakeD1Session implements CloudflareD1DatabaseSession {
  const _FakeD1Session(this.database, this.bookmark);
  final FakeCloudflareD1Database database;
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
  Future<String?> getBookmark() async => bookmark ?? 'fake-primary';
}
