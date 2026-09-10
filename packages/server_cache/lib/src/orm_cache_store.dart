import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:server_cache/src/taggable_store.dart';
import 'package:server_contracts/server_contracts.dart';

/// A database-backed cache store built on Ormed's codegen-free table API.
///
/// The store only depends on [OrmDatabase], so the application chooses the
/// concrete Ormed driver. The same implementation can therefore be used with
/// SQLite, Cloudflare D1, or another driver supported by Ormed.
///
/// The [migration] entry creates the table used by the store. Applications
/// should register it with their normal Ormed migration registry rather than
/// having the store mutate the schema implicitly:
///
/// ```dart
/// final cache = OrmCacheStore(database);
/// await database.migrate([cache.migration]);
/// ```
///
/// Values are JSON encoded. Cache values must therefore be supported by
/// `jsonEncode`, just like the serializing in-memory store.
final class OrmCacheStore extends TaggableStore implements Store {
  /// Creates a store using [database] and [tableName].
  ///
  /// The table must already exist, or be created by registering [migration]
  /// before the store is used. [tableName] is intentionally restricted to
  /// simple SQL identifiers because Ormed must embed it in generated queries.
  OrmCacheStore(this.database, {this.tableName = 'cache_entries'}) {
    _validateIdentifier(tableName, 'tableName');
    if (!database.isOpen) {
      throw ArgumentError.value(database, 'database', 'must be open');
    }
  }

  static const List<AdHocColumn> _columns = <AdHocColumn>[
    AdHocColumn(
      name: 'key',
      dartType: 'String',
      columnType: 'TEXT',
      isNullable: false,
      isPrimaryKey: true,
    ),
    AdHocColumn(
      name: 'value',
      dartType: 'String',
      columnType: 'TEXT',
      isNullable: false,
    ),
    AdHocColumn(
      name: 'expires_at',
      dartType: 'int',
      columnType: 'INTEGER',
    ),
  ];

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Ormed database used for cache queries.
  final OrmDatabase database;

  /// Table containing cache keys, JSON values, and millisecond expirations.
  final String tableName;

  /// Migration entry that creates this store's table.
  ///
  /// Register this entry with the application's existing migration provider.
  /// The stable table-derived timestamp lets more than one custom cache table
  /// share the same database migration ledger.
  MigrationEntry get migration => MigrationEntry.named(
    'm_${_migrationTimestamp(tableName)}_create_${tableName}_cache',
    CreateOrmCacheTable(tableName),
  );

  Query<AdHocRow> _entries() => database.table(tableName, columns: _columns);

  @override
  Future<dynamic> get(String key) async {
    final row = await _find(key);
    if (row == null) return null;
    if (_isExpired(row['expires_at'])) {
      await _removeExpired(key, row['expires_at']);
      return null;
    }
    return jsonDecode(row['value']!.toString());
  }

  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    final values = <String, dynamic>{};
    for (final key in keys) {
      values[key] = await get(key);
    }
    return values;
  }

  @override
  Future<bool> put(String key, dynamic value, int seconds) async {
    await _upsert(_payload(key, value, _expiration(seconds)));
    return true;
  }

  @override
  Future<bool> add(String key, dynamic value, int seconds) async {
    return _write(() async {
      final payload = _payload(key, value, _expiration(seconds));
      var result = await _entries().insertManyInputsRaw(
        [payload],
        ignoreConflicts: true,
      );
      if (result.affectedRows > 0) return true;

      // An expired row still occupies the primary key. Remove it and retry;
      // the unique constraint plus insert-or-ignore keeps the final write
      // atomic when another worker races this operation.
      final existing = await _find(key);
      if (existing == null || !_isExpired(existing['expires_at'])) {
        return false;
      }
      await _removeExpired(key, existing['expires_at']);
      result = await _entries().insertManyInputsRaw(
        [payload],
        ignoreConflicts: true,
      );
      return result.affectedRows > 0;
    });
  }

  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    if (values.isEmpty) return true;
    final expiresAt = _expiration(seconds);
    await _entries().upsertInputs(
      values.entries
          .map((entry) => _payload(entry.key, entry.value, expiresAt))
          .toList(growable: false),
      uniqueBy: const ['key'],
      updateColumns: const ['value', 'expires_at'],
    );
    return true;
  }

  @override
  Future<dynamic> increment(String key, [int value = 1]) async {
    return _write(() async {
      final row = await _find(key);
      final expired = row == null || _isExpired(row['expires_at']);
      final current = expired ? 0 : _decodeNumber(row['value']);
      final next = current + value;
      final expiresAt = expired ? null : _expiryValue(row['expires_at']);
      await _upsert(_payload(key, next, expiresAt));
      return next;
    });
  }

  @override
  Future<dynamic> decrement(String key, [int value = 1]) {
    return increment(key, -value);
  }

  @override
  Future<bool> forever(String key, dynamic value) => put(key, value, 0);

  @override
  Future<bool> forget(String key) async {
    return (await _entries().whereEquals('key', key).delete()) > 0;
  }

  @override
  Future<bool> flush() async {
    await _entries().delete();
    return true;
  }

  @override
  String getPrefix() => '';

  @override
  Future<List<String>> getAllKeys() async {
    final keys = <String>[];
    final rows = await _entries().get();
    for (final row in rows) {
      final key = row['key']?.toString();
      if (key == null) continue;
      if (_isExpired(row['expires_at'])) {
        await _removeExpired(key, row['expires_at']);
      } else {
        keys.add(key);
      }
    }
    return keys;
  }

  Future<AdHocRow?> _find(String key) {
    return _entries().whereEquals('key', key).limit(1).first();
  }

  Future<void> _upsert(Map<String, Object?> payload) async {
    await _entries().upsertInputs(
      [payload],
      uniqueBy: const ['key'],
      updateColumns: const ['value', 'expires_at'],
    );
  }

  Future<void> _removeExpired(String key, Object? expiresAt) async {
    final timestamp = _expiryValue(expiresAt);
    if (timestamp == null) return;
    await _entries()
        .whereEquals('key', key)
        .whereEquals('expires_at', timestamp)
        .delete();
  }

  Future<T> _write<T>(Future<T> Function() action) {
    if (database.driver.metadata.supportsTransactions) {
      return database.transaction(action);
    }
    return action();
  }

  Map<String, Object?> _payload(String key, dynamic value, int? expiresAt) => {
    'key': key,
    'value': jsonEncode(value),
    'expires_at': expiresAt,
  };

  int? _expiration(int seconds) => seconds > 0
      ? DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch
      : null;

  int? _expiryValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool _isExpired(Object? value) {
    final expiresAt = _expiryValue(value);
    return expiresAt != null &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch;
  }

  num _decodeNumber(Object? encoded) {
    final decoded = jsonDecode(encoded!.toString());
    if (decoded is num) return decoded;
    return num.parse(decoded.toString());
  }

  static void _validateIdentifier(String value, String name) {
    if (!_identifier.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        name,
        'must be a simple SQL identifier',
      );
    }
  }

  static String _migrationTimestamp(String table) {
    var hash = 2166136261;
    for (final codeUnit in table.codeUnits) {
      hash = (hash ^ codeUnit) * 16777619 & 0x7fffffff;
    }
    final seconds = hash % Duration.secondsPerDay;
    final hour = seconds ~/ Duration.secondsPerHour;
    final minute =
        (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final second = seconds % Duration.secondsPerMinute;
    return '20260909${hour.toString().padLeft(2, '0')}'
        '${minute.toString().padLeft(2, '0')}'
        '${second.toString().padLeft(2, '0')}';
  }
}

/// Ormed migration for the table used by [OrmCacheStore].
final class CreateOrmCacheTable extends Migration {
  /// Creates a migration for [tableName].
  CreateOrmCacheTable(this.tableName) {
    OrmCacheStore._validateIdentifier(tableName, 'tableName');
  }

  /// Name of the cache table to create.
  final String tableName;

  @override
  void up(SchemaBuilder schema) {
    schema.create(tableName, (table) {
      table.text('key').primaryKey();
      table.text('value');
      table.bigInteger('expires_at').nullable();
      table.index(['expires_at'], name: '${tableName}_expires_at_index');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop(tableName, ifExists: true);
  }
}
