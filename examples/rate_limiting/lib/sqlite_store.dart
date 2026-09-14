import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:server_contracts/server_contracts.dart';

/// Small Ormed-backed key/value store used by the rate-limit example.
final class SqliteRateLimitStore implements Store {
  SqliteRateLimitStore(this.database);

  static const _columns = <AdHocColumn>[
    AdHocColumn(
      name: 'key',
      dartType: 'String',
      columnType: 'TEXT',
      isNullable: false,
      isPrimaryKey: true,
    ),
    AdHocColumn(name: 'value', dartType: 'String', isNullable: false),
    AdHocColumn(
      name: 'expires_at',
      dartType: 'int',
      columnType: 'INTEGER',
      isNullable: true,
    ),
  ];

  final OrmDatabase database;

  Query<AdHocRow> _entries() =>
      database.table('rate_limit_entries', columns: _columns);

  @override
  Future<dynamic> get(String key) async {
    final rows = await _entries().whereEquals('key', key).limit(1).get();
    if (rows.isEmpty) return null;
    final expiresAt = (rows.first['expires_at'] as num?)?.toInt();
    if (expiresAt != null &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      await forget(key);
      return null;
    }
    return jsonDecode(rows.first['value']!.toString());
  }

  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    final values = <String, dynamic>{};
    for (final key in keys) {
      final value = await get(key);
      if (value != null) values[key] = value;
    }
    return values;
  }

  @override
  Future<bool> put(String key, dynamic value, int seconds) async {
    await _replace(key, value, seconds);
    return true;
  }

  @override
  Future<bool> add(String key, dynamic value, int seconds) async {
    return database.transaction(() async {
      final existing = await get(key);
      if (existing != null) return false;
      await _entries().insertManyInputs([
        _payload(key, value, seconds),
      ], returning: false);
      return true;
    });
  }

  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    return database.transaction(() async {
      for (final entry in values.entries) {
        await _replace(entry.key, entry.value, seconds);
      }
      return true;
    });
  }

  @override
  Future<dynamic> increment(String key, [int value = 1]) async {
    return database.transaction(() async {
      final current = (await get(key) as num?)?.toInt() ?? 0;
      final next = current + value;
      await _replace(key, next, 0);
      return next;
    });
  }

  @override
  Future<dynamic> decrement(String key, [int value = 1]) async {
    return increment(key, -value);
  }

  @override
  Future<bool> forever(String key, dynamic value) => put(key, value, 0);

  @override
  Future<bool> forget(String key) async =>
      (await _entries().whereEquals('key', key).delete()) > 0;

  @override
  Future<bool> flush() async {
    await _entries().delete();
    return true;
  }

  @override
  String getPrefix() => '';

  @override
  Future<List<String>> getAllKeys() async {
    final rows = await _entries().get();
    final keys = <String>[];
    for (final row in rows) {
      final key = row['key']?.toString();
      if (key == null || key.isEmpty) continue;
      final expiresAt = (row['expires_at'] as num?)?.toInt();
      if (expiresAt != null &&
          expiresAt <= DateTime.now().millisecondsSinceEpoch) {
        await forget(key);
      } else {
        keys.add(key);
      }
    }
    return keys;
  }

  Future<void> _replace(String key, dynamic value, int seconds) async {
    await _entries().whereEquals('key', key).delete();
    await _entries().insertManyInputs([
      _payload(key, value, seconds),
    ], returning: false);
  }

  Map<String, Object?> _payload(String key, dynamic value, int seconds) => {
    'key': key,
    'value': jsonEncode(value),
    'expires_at': seconds > 0
        ? DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch
        : null,
  };
}
