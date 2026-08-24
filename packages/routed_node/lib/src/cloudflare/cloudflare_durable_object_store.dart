import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:server_contracts/server_contracts.dart';

import 'cloudflare_types.dart';
import 'cloudflare_bindings_stub.dart'
    if (dart.library.js_interop) 'cloudflare_bindings_js.dart'
    as cloudflare_bindings;

Object? _decodeCloudflareResponse(CloudflareResponse response) {
  final body = response.body;
  final text = switch (body) {
    String value => value,
    List<int> bytes => utf8.decode(bytes),
    _ => throw StateError('Cloudflare store returned an unreadable body.'),
  };
  return jsonDecode(text);
}

/// A sharded, SQLite-backed [Store] implemented with Durable Objects.
///
/// Each key is routed to a stable Durable Object name. Values are encoded as
/// JSON because the cache contracts intentionally accept arbitrary Dart
/// values. The same object also provides distributed locks, allowing
/// `CacheRateLimiterBackend` to perform its read-modify-write operation
/// atomically across Worker isolates.
///
/// SQLite-backed Durable Objects are available on the Workers Free plan. A
/// small shard count avoids putting every cache key behind one globally hot
/// object while keeping the number of Durable Object requests predictable.
final class CloudflareDurableObjectStore implements Store, LockProvider {
  CloudflareDurableObjectStore({
    required CloudflareDurableObjectNamespace namespace,
    this.objectPrefix = 'routed-store',
    this.shardCount = 16,
  }) : _namespace = namespace {
    if (objectPrefix.trim().isEmpty) {
      throw ArgumentError.value(
        objectPrefix,
        'objectPrefix',
        'must not be empty',
      );
    }
    if (shardCount < 1 || shardCount > 256) {
      throw ArgumentError.value(
        shardCount,
        'shardCount',
        'must be between 1 and 256',
      );
    }
  }

  final CloudflareDurableObjectNamespace _namespace;

  /// Prefix used when deriving Durable Object names.
  final String objectPrefix;

  /// Number of independent Durable Object shards.
  final int shardCount;

  @override
  Future<dynamic> get(String key) async {
    final response = await _request('get', key: key);
    return response['found'] == true ? response['value'] : null;
  }

  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    if (keys.isEmpty) return <String, dynamic>{};
    final grouped = <int, List<String>>{};
    for (final key in keys) {
      grouped.putIfAbsent(_shardFor(key), () => <String>[]).add(key);
    }

    final result = <String, dynamic>{};
    for (final entry in grouped.entries) {
      final response = await _requestOnShard(
        entry.key,
        'many',
        payload: <String, Object?>{'keys': entry.value},
      );
      final values = response['values'];
      if (values is Map) {
        for (final value in values.entries) {
          if (value.key is String) {
            result[value.key as String] = value.value;
          }
        }
      }
    }
    return result;
  }

  @override
  Future<bool> put(String key, dynamic value, int seconds) async {
    final response = await _request(
      'put',
      key: key,
      payload: <String, Object?>{'value': value, 'seconds': seconds},
    );
    return response['stored'] == true;
  }

  @override
  Future<bool> add(String key, dynamic value, int seconds) async {
    final response = await _request(
      'add',
      key: key,
      payload: <String, Object?>{'value': value, 'seconds': seconds},
    );
    return response['stored'] == true;
  }

  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    if (values.isEmpty) return true;
    final grouped = <int, Map<String, dynamic>>{};
    for (final entry in values.entries) {
      grouped.putIfAbsent(
        _shardFor(entry.key),
        () => <String, dynamic>{},
      )[entry.key] = entry.value;
    }
    for (final entry in grouped.entries) {
      await _requestOnShard(
        entry.key,
        'put_many',
        payload: <String, Object?>{'values': entry.value, 'seconds': seconds},
      );
    }
    return true;
  }

  @override
  Future<num> increment(String key, [int value = 1]) async {
    final response = await _request(
      'increment',
      key: key,
      payload: <String, Object?>{'value': value},
    );
    final result = response['value'];
    if (result is! num) {
      throw StateError('Cloudflare store returned a non-numeric value.');
    }
    return result;
  }

  @override
  Future<num> decrement(String key, [int value = 1]) => increment(key, -value);

  @override
  Future<bool> forever(String key, dynamic value) => put(key, value, 0);

  @override
  Future<bool> forget(String key) async {
    final response = await _request('forget', key: key);
    return response['removed'] == true;
  }

  @override
  Future<bool> flush() async {
    for (var shard = 0; shard < shardCount; shard++) {
      await _requestOnShard(shard, 'flush');
    }
    return true;
  }

  @override
  String getPrefix() => '';

  @override
  Future<List<String>> getAllKeys() async {
    final keys = <String>[];
    for (var shard = 0; shard < shardCount; shard++) {
      final response = await _requestOnShard(shard, 'keys');
      final values = response['keys'];
      if (values is Iterable) {
        keys.addAll(values.whereType<String>());
      }
    }
    return keys;
  }

  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async =>
      _CloudflareDurableObjectLock(this, name, seconds, owner);

  @override
  Future<Lock> restoreLock(String name, String owner) => lock(name, 0, owner);

  int _shardFor(String key) =>
      sha256.convert(utf8.encode(key)).bytes.first % shardCount;

  String _objectName(int shard) =>
      '$objectPrefix-${shard.toString().padLeft(3, '0')}';

  Future<Map<String, Object?>> _request(
    String operation, {
    String? key,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    final routingKey =
        key ??
        (payload['name'] is String ? payload['name'] as String : operation);
    final shard = _shardFor(routingKey);
    return _requestOnShard(shard, operation, key: key, payload: payload);
  }

  Future<Map<String, Object?>> _requestOnShard(
    int shard,
    String operation, {
    String? key,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    final body = <String, Object?>{...payload, if (key != null) 'key': key};
    final request = cloudflare_bindings.createCloudflareRequest(
      'https://routed.internal/$operation',
      method: 'POST',
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    final response = await _namespace
        .getByName(_objectName(shard))
        .fetch(request);
    final value = response.body == null
        ? null
        : _decodeCloudflareResponse(response);
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Cloudflare Durable Object store request failed.');
    }
    if (value is! Map) {
      throw StateError(
        'Cloudflare Durable Object store returned invalid data.',
      );
    }
    return Map<String, Object?>.from(value);
  }

  Future<Map<String, Object?>> _lockRequest(
    String operation, {
    required String name,
    required String owner,
    int seconds = 0,
  }) => _request(
    operation,
    key: name,
    payload: <String, Object?>{
      'name': name,
      'owner': owner,
      'seconds': seconds,
    },
  );
}

/// A SQLite-backed Durable Object that serves [CloudflareDurableObjectStore].
///
/// Register this class with `defineCloudflareDurableObjects` and bind the
/// corresponding Durable Object namespace in Wrangler. The implementation
/// uses synchronous SQLite operations inside one Durable Object request, so
/// a lock acquisition and its expiry cleanup are atomic.
class CloudflareDurableObjectStoreObject extends CloudflareDurableObject {
  CloudflareDurableObjectStoreObject(super.state, super.env);

  Future<void>? _schemaFuture;

  @override
  Future<CloudflareResponse> fetch(CloudflareRequest request) async {
    if (request.method.toUpperCase() != 'POST') {
      return _error('method_not_allowed', 405);
    }
    try {
      await _ensureSchema();
      final pathSegments = Uri.parse(request.url).pathSegments;
      final operation = pathSegments.isEmpty ? null : pathSegments.last;
      if (operation == null || operation.isEmpty) {
        return _error('operation_required', 400);
      }
      final decoded = await request.json<Object?>();
      if (decoded is! Map) return _error('invalid_request', 400);
      final payload = Map<String, Object?>.from(decoded);
      return _dispatch(operation, payload);
    } on FormatException {
      return _error('invalid_request', 400);
    } on ArgumentError {
      return _error('invalid_request', 400);
    } catch (error, stackTrace) {
      // Keep platform diagnostics in Worker logs while never returning the
      // exception text (which may contain deployment-specific details).
      print('Cloudflare Durable Object store failure: $error\n$stackTrace');
      return _error('store_unavailable', 500);
    }
  }

  Future<void> _ensureSchema() {
    return _schemaFuture ??= state.blockConcurrencyWhile(() async {
      final sql = _sql;
      sql.exec('''
        CREATE TABLE IF NOT EXISTS routed_store_entries (
          cache_key TEXT PRIMARY KEY NOT NULL,
          value_json TEXT NOT NULL,
          expires_at INTEGER NOT NULL DEFAULT 0
        )
      ''');
      sql.exec('''
        CREATE TABLE IF NOT EXISTS routed_store_locks (
          lock_name TEXT PRIMARY KEY NOT NULL,
          owner TEXT NOT NULL,
          expires_at INTEGER NOT NULL
        )
      ''');
    });
  }

  CloudflareDurableObjectSqlStorage get _sql =>
      state.storage.sql ??
      (throw StateError('SQLite-backed Durable Object storage is required.'));

  CloudflareResponse _dispatch(String operation, Map<String, Object?> payload) {
    switch (operation) {
      case 'get':
        return _get(_key(payload));
      case 'many':
        return _many(_keys(payload));
      case 'put':
        return _put(_key(payload), payload['value'], _seconds(payload));
      case 'add':
        return _add(_key(payload), payload['value'], _seconds(payload));
      case 'put_many':
        return _putMany(_values(payload), _seconds(payload));
      case 'increment':
        return _increment(_key(payload), _integer(payload, 'value', 1));
      case 'forget':
        return _forget(_key(payload));
      case 'flush':
        return _flush();
      case 'keys':
        return _keysResult();
      case 'lock_acquire':
        return _lockAcquire(_name(payload), _owner(payload), _seconds(payload));
      case 'lock_release':
        return _lockRelease(_name(payload), _owner(payload));
      case 'lock_force_release':
        return _lockForceRelease(_name(payload));
      case 'lock_owner':
        return _lockOwner(_name(payload));
      default:
        return _error('unknown_operation', 404);
    }
  }

  CloudflareResponse _get(String key) {
    final row = _sql.exec(
      'SELECT value_json, expires_at FROM routed_store_entries '
      'WHERE cache_key = ?',
      <Object?>[key],
    ).toArray();
    if (row.isEmpty) return _json(<String, Object?>{'found': false});
    final expiresAt = _number(row.single['expires_at']);
    if (_expired(expiresAt)) {
      _sql.exec(
        'DELETE FROM routed_store_entries WHERE cache_key = ?',
        <Object?>[key],
      );
      return _json(<String, Object?>{'found': false});
    }
    return _json(<String, Object?>{
      'found': true,
      'value': jsonDecode(row.single['value_json'] as String),
    });
  }

  CloudflareResponse _many(List<String> keys) {
    final values = <String, Object?>{};
    for (final key in keys) {
      final result = _getValue(key);
      if (result != null) values[key] = result;
    }
    return _json(<String, Object?>{'values': values});
  }

  Object? _getValue(String key) {
    final response = _get(key);
    if (response.body == null) return null;
    final value = _decodeCloudflareResponse(response);
    if (value is! Map || value['found'] != true) return null;
    return value['value'];
  }

  CloudflareResponse _put(String key, Object? value, int seconds) {
    _sql.exec(
      'INSERT INTO routed_store_entries(cache_key, value_json, expires_at) '
      'VALUES (?, ?, ?) ON CONFLICT(cache_key) DO UPDATE SET '
      'value_json = excluded.value_json, expires_at = excluded.expires_at',
      <Object?>[key, jsonEncode(value), _expiresAt(seconds)],
    );
    return _json(<String, Object?>{'stored': true});
  }

  CloudflareResponse _add(String key, Object? value, int seconds) {
    _deleteExpiredEntry(key);
    final inserted = _sql
        .exec(
          'INSERT INTO routed_store_entries(cache_key, value_json, expires_at) '
          'VALUES (?, ?, ?) ON CONFLICT(cache_key) DO NOTHING '
          'RETURNING cache_key',
          <Object?>[key, jsonEncode(value), _expiresAt(seconds)],
        )
        .toArray()
        .isNotEmpty;
    return _json(<String, Object?>{'stored': inserted});
  }

  CloudflareResponse _putMany(Map<String, Object?> values, int seconds) {
    final expiry = _expiresAt(seconds);
    for (final entry in values.entries) {
      _sql.exec(
        'INSERT INTO routed_store_entries(cache_key, value_json, expires_at) '
        'VALUES (?, ?, ?) ON CONFLICT(cache_key) DO UPDATE SET '
        'value_json = excluded.value_json, expires_at = excluded.expires_at',
        <Object?>[entry.key, jsonEncode(entry.value), expiry],
      );
    }
    return _json(<String, Object?>{'stored': true});
  }

  CloudflareResponse _increment(String key, int delta) {
    final row = _sql.exec(
      'SELECT value_json, expires_at FROM routed_store_entries '
      'WHERE cache_key = ?',
      <Object?>[key],
    ).toArray();
    num current = 0;
    var expiresAt = 0;
    if (row.isNotEmpty) {
      final existingExpiry = _number(row.single['expires_at']);
      if (!_expired(existingExpiry)) {
        final value = jsonDecode(row.single['value_json'] as String);
        if (value is! num) throw ArgumentError('value must be numeric');
        current = value;
        expiresAt = existingExpiry;
      }
    }
    final next = current + delta;
    _sql.exec(
      'INSERT INTO routed_store_entries(cache_key, value_json, expires_at) '
      'VALUES (?, ?, ?) ON CONFLICT(cache_key) DO UPDATE SET '
      'value_json = excluded.value_json, expires_at = excluded.expires_at',
      <Object?>[key, jsonEncode(next), expiresAt],
    );
    return _json(<String, Object?>{'value': next});
  }

  CloudflareResponse _forget(String key) {
    final removed = _sql
        .exec(
          'DELETE FROM routed_store_entries WHERE cache_key = ? '
          'RETURNING cache_key',
          <Object?>[key],
        )
        .toArray()
        .isNotEmpty;
    return _json(<String, Object?>{'removed': removed});
  }

  CloudflareResponse _flush() {
    _sql.exec('DELETE FROM routed_store_entries');
    return _json(<String, Object?>{'flushed': true});
  }

  CloudflareResponse _keysResult() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _sql.exec(
      'DELETE FROM routed_store_entries WHERE expires_at > 0 AND expires_at <= ?',
      <Object?>[now],
    );
    final keys = _sql
        .exec('SELECT cache_key FROM routed_store_entries')
        .toArray()
        .map((row) => row['cache_key'])
        .whereType<String>()
        .toList();
    return _json(<String, Object?>{'keys': keys});
  }

  CloudflareResponse _lockAcquire(String name, String owner, int seconds) {
    _deleteExpiredLock(name);
    final acquired = _sql
        .exec(
          'INSERT INTO routed_store_locks(lock_name, owner, expires_at) '
          'VALUES (?, ?, ?) ON CONFLICT(lock_name) DO NOTHING '
          'RETURNING lock_name',
          <Object?>[name, owner, _lockExpiresAt(seconds)],
        )
        .toArray()
        .isNotEmpty;
    return _json(<String, Object?>{'acquired': acquired});
  }

  CloudflareResponse _lockRelease(String name, String owner) {
    final released = _sql
        .exec(
          'DELETE FROM routed_store_locks WHERE lock_name = ? AND owner = ? '
          'RETURNING lock_name',
          <Object?>[name, owner],
        )
        .toArray()
        .isNotEmpty;
    return _json(<String, Object?>{'released': released});
  }

  CloudflareResponse _lockForceRelease(String name) {
    _sql.exec('DELETE FROM routed_store_locks WHERE lock_name = ?', <Object?>[
      name,
    ]);
    return _json(<String, Object?>{'released': true});
  }

  CloudflareResponse _lockOwner(String name) {
    _deleteExpiredLock(name);
    final rows = _sql.exec(
      'SELECT owner FROM routed_store_locks WHERE lock_name = ?',
      <Object?>[name],
    ).toArray();
    return _json(<String, Object?>{
      'owner': rows.isEmpty ? null : rows.single['owner'],
    });
  }

  void _deleteExpiredEntry(String key) {
    _sql.exec(
      'DELETE FROM routed_store_entries WHERE cache_key = ? AND '
      'expires_at > 0 AND expires_at <= ?',
      <Object?>[key, DateTime.now().millisecondsSinceEpoch],
    );
  }

  void _deleteExpiredLock(String name) {
    _sql.exec(
      'DELETE FROM routed_store_locks WHERE lock_name = ? AND expires_at > 0 '
      'AND expires_at <= ?',
      <Object?>[name, DateTime.now().millisecondsSinceEpoch],
    );
  }

  bool _expired(int expiresAt) =>
      expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch;

  int _expiresAt(int seconds) => seconds > 0
      ? DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch
      : 0;

  int _lockExpiresAt(int seconds) => _expiresAt(seconds);

  int _number(Object? value) => value is num ? value.toInt() : 0;

  String _key(Map<String, Object?> payload) => _requiredString(payload, 'key');

  List<String> _keys(Map<String, Object?> payload) {
    final value = payload['keys'];
    if (value is! Iterable) throw ArgumentError('keys must be a list');
    return value.map((entry) {
      if (entry is! String) throw ArgumentError('keys must be strings');
      return entry;
    }).toList();
  }

  Map<String, Object?> _values(Map<String, Object?> payload) {
    final value = payload['values'];
    if (value is! Map) throw ArgumentError('values must be a map');
    return Map<String, Object?>.from(value);
  }

  String _name(Map<String, Object?> payload) =>
      _requiredString(payload, 'name');

  String _owner(Map<String, Object?> payload) =>
      _requiredString(payload, 'owner');

  String _requiredString(Map<String, Object?> payload, String name) {
    final value = payload[name];
    if (value is! String || value.isEmpty || value.length > 512) {
      throw ArgumentError('$name must be a non-empty string');
    }
    return value;
  }

  int _seconds(Map<String, Object?> payload) => _integer(payload, 'seconds', 0);

  int _integer(Map<String, Object?> payload, String name, int fallback) {
    final value = payload[name];
    if (value == null) return fallback;
    if (value is! num || !value.isFinite) {
      throw ArgumentError('$name must be an integer');
    }
    final result = value.toInt();
    if (value != result || result < 0) {
      throw ArgumentError('$name must be a non-negative integer');
    }
    return result;
  }

  CloudflareResponse _json(Object? value) => CloudflareResponse.json(value);

  CloudflareResponse _error(String code, int status) =>
      CloudflareResponse.json(<String, String>{'error': code}, status: status);
}

final class _CloudflareDurableObjectLock implements Lock {
  _CloudflareDurableObjectLock(
    this._store,
    this.name,
    this.seconds,
    String? owner,
  ) : _owner = owner ?? _newOwner();

  final CloudflareDurableObjectStore _store;
  final String name;
  final int seconds;
  final String _owner;

  // A rate-limit critical section spans several Durable Object requests
  // (acquire, read, write, release). Keep the lease longer than the caller's
  // acquisition timeout so normal network latency cannot expire it halfway
  // through the protected read-modify-write.
  int get _leaseSeconds => seconds > 0 ? max(seconds, 10) : 0;

  @override
  Future<dynamic> get([Function? callback]) async {
    final acquired = await acquire();
    if (!acquired || callback == null) return acquired;
    try {
      return await callback();
    } finally {
      await release();
    }
  }

  @override
  Future<bool> acquire() async {
    final response = await _store._lockRequest(
      'lock_acquire',
      name: name,
      owner: _owner,
      seconds: _leaseSeconds,
    );
    return response['acquired'] == true;
  }

  @override
  Future<dynamic> block(int timeoutSeconds, [Function? callback]) async {
    final timeout = max(0, timeoutSeconds) * 1000;
    final deadline = DateTime.now().millisecondsSinceEpoch + timeout;
    while (true) {
      if (await acquire()) {
        if (callback == null) return true;
        try {
          return await callback();
        } finally {
          await release();
        }
      }
      if (timeout == 0 || DateTime.now().millisecondsSinceEpoch >= deadline) {
        throw LockTimeoutException('Lock timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Future<bool> release() async {
    final response = await _store._lockRequest(
      'lock_release',
      name: name,
      owner: _owner,
    );
    return response['released'] == true;
  }

  @override
  String owner() => _owner;

  @override
  Future<String?> getCurrentOwner() async {
    final response = await _store._lockRequest(
      'lock_owner',
      name: name,
      owner: _owner,
    );
    final owner = response['owner'];
    return owner is String ? owner : null;
  }

  @override
  Future<bool> isOwnedByCurrentProcess() async =>
      await getCurrentOwner() == _owner;

  @override
  void forceRelease() {
    unawaited(
      _store._lockRequest('lock_force_release', name: name, owner: _owner),
    );
  }

  static String _newOwner() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
