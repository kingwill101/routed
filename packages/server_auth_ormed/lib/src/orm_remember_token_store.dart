import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:server_auth/server_auth.dart';

import 'orm_auth_schema.dart';

/// Transactional Ormed persistence for Routed remember-me tokens.
///
/// Tokens are stored as digests in the auth records table and are consumed
/// inside an Ormed transaction. Use this with a transaction-capable driver
/// such as SQLite or Postgres; Cloudflare D1 applications should provide a
/// host-specific compare-and-delete implementation instead.
final class OrmRememberTokenStore implements RememberTokenStore {
  /// Creates a store over an open Ormed database.
  OrmRememberTokenStore(
    this.database, {
    this.schema = const OrmAuthSchema(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (!database.isOpen) {
      throw ArgumentError.value(database, 'database', 'must be open');
    }
  }

  /// Ormed database containing the auth records table.
  final OrmDatabase database;

  /// Schema used by the paired [OrmAuthStore].
  final OrmAuthSchema schema;
  final DateTime Function() _clock;

  @override
  Future<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  ) => database.transaction(() async {
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'must be non-empty');
    }
    if (principal.id.trim().isEmpty) {
      throw ArgumentError.value(
        principal.id,
        'principal.id',
        'must be non-empty',
      );
    }
    final now = _clock().toUtc();
    await _removeExpired(now);
    final expiry = expiresAt.toUtc();
    if (!now.isBefore(expiry)) return;
    final key = _key(token);
    await _table().whereEquals('record_key', key).delete();
    await _table().insertManyInputs([
      {
        'record_key': key,
        'kind': 'remember',
        'lookup': null,
        'owner_id': principal.id,
        'payload': jsonEncode(principal.toJson()),
        'created_at': now.toIso8601String(),
        'expires_at': expiry.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
    ], returning: false);
  });

  @override
  Future<AuthPrincipal?> read(String token) async {
    if (token.trim().isEmpty) return null;
    final rows = await _table().whereEquals('record_key', _key(token)).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    final expiresAt = DateTime.tryParse(row['expires_at']?.toString() ?? '');
    if (expiresAt == null || !_clock().toUtc().isBefore(expiresAt.toUtc())) {
      await remove(token);
      return null;
    }
    return _principal(row);
  }

  @override
  Future<AuthPrincipal?> consume(String token) => database.transaction(
    () async {
      if (token.trim().isEmpty) return null;
      final rows = await _table().whereEquals('record_key', _key(token)).get();
      if (rows.isEmpty) return null;
      final row = rows.first;
      final expiresAt = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      await _table().whereEquals('record_key', _key(token)).delete();
      if (expiresAt == null || !_clock().toUtc().isBefore(expiresAt.toUtc())) {
        return null;
      }
      return _principal(row);
    },
  );

  @override
  Future<void> remove(String token) async {
    if (token.trim().isEmpty) return;
    await _table().whereEquals('record_key', _key(token)).delete();
  }

  Query<AdHocRow> _table() =>
      database.table(schema.table('records'), columns: _columns);

  Future<void> _removeExpired(DateTime now) async {
    final rows = await _table().whereEquals('kind', 'remember').get();
    for (final row in rows) {
      final expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expiry == null || !now.isBefore(expiry.toUtc())) {
        await _table().whereEquals('record_key', row['record_key']).delete();
      }
    }
  }

  static AuthPrincipal _principal(AdHocRow row) => AuthPrincipal.fromJson(
    Map<String, dynamic>.from(jsonDecode(row['payload']!.toString()) as Map),
  );

  static String _key(String token) => 'remember:${hashOpaqueToken(token)}';
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
