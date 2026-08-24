import 'dart:async';
import 'dart:convert';

import 'package:routed_node/cloudflare.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late _FakeSql sql;
  late _FakeState state;
  late CloudflareDurableObjectStoreObject object;

  setUp(() {
    sql = _FakeSql();
    state = _FakeState(sql);
    object = CloudflareDurableObjectStoreObject(state, _FakeEnvironment());
  });

  tearDown(() => sql.close());

  test('stores JSON values and preserves add semantics', () async {
    expect(
      await _call(object, 'add', <String, Object?>{
        'key': 'account:1',
        'value': <String, Object?>{'enabled': true},
        'seconds': 30,
      }),
      <String, Object?>{'stored': true},
    );
    expect(
      await _call(object, 'add', <String, Object?>{
        'key': 'account:1',
        'value': false,
        'seconds': 30,
      }),
      <String, Object?>{'stored': false},
    );
    expect(
      await _call(object, 'get', <String, Object?>{'key': 'account:1'}),
      <String, Object?>{
        'found': true,
        'value': <String, Object?>{'enabled': true},
      },
    );
    expect(state.schemaInitializationCount, 1);
  });

  test('updates counters atomically in the Durable Object SQL store', () async {
    expect(
      await _call(object, 'increment', <String, Object?>{'key': 'bucket'}),
      <String, Object?>{'value': 1},
    );
    expect(
      await _call(object, 'increment', <String, Object?>{
        'key': 'bucket',
        'value': 2,
      }),
      <String, Object?>{'value': 3},
    );
    expect(
      await _call(object, 'get', <String, Object?>{'key': 'bucket'}),
      <String, Object?>{'found': true, 'value': 3},
    );
  });

  test('locks are owner-aware and release atomically', () async {
    expect(
      await _call(object, 'lock_acquire', <String, Object?>{
        'name': 'rate-limit:client',
        'owner': 'owner-a',
        'seconds': 30,
      }),
      <String, Object?>{'acquired': true},
    );
    expect(
      await _call(object, 'lock_acquire', <String, Object?>{
        'name': 'rate-limit:client',
        'owner': 'owner-b',
        'seconds': 30,
      }),
      <String, Object?>{'acquired': false},
    );
    expect(
      await _call(object, 'lock_release', <String, Object?>{
        'name': 'rate-limit:client',
        'owner': 'owner-b',
      }),
      <String, Object?>{'released': false},
    );
    expect(
      await _call(object, 'lock_owner', <String, Object?>{
        'name': 'rate-limit:client',
        'owner': 'owner-a',
      }),
      <String, Object?>{'owner': 'owner-a'},
    );
    expect(
      await _call(object, 'lock_release', <String, Object?>{
        'name': 'rate-limit:client',
        'owner': 'owner-a',
      }),
      <String, Object?>{'released': true},
    );
  });

  test('does not expose exception details in protocol errors', () async {
    final response = await object.fetch(
      _FakeRequest('/get', <String, Object?>{'key': ''}),
    );
    final body = _decode(response);
    expect(response.status, 400);
    expect(body, <String, Object?>{'error': 'invalid_request'});
    expect(jsonEncode(body), isNot(contains('must be a non-empty string')));
  });
}

Future<Map<String, Object?>> _call(
  CloudflareDurableObjectStoreObject object,
  String operation,
  Map<String, Object?> payload,
) async {
  final response = await object.fetch(_FakeRequest('/$operation', payload));
  expect(response.status, lessThan(300));
  return _decode(response);
}

Map<String, Object?> _decode(CloudflareResponse response) {
  final body = response.body;
  final text = body is String ? body : utf8.decode(body as List<int>);
  return Map<String, Object?>.from(jsonDecode(text) as Map);
}

final class _FakeRequest implements CloudflareRequest {
  _FakeRequest(this.path, this.payload);

  final String path;
  final Map<String, Object?> payload;

  @override
  final String method = 'POST';

  @override
  String get url => 'https://routed.internal$path';

  @override
  final Map<String, String> headers = const <String, String>{
    'content-type': 'application/json',
  };

  @override
  final Map<String, Object?> cf = const <String, Object?>{};

  @override
  Future<String> text() async => jsonEncode(payload);

  @override
  Future<T?> json<T>({CloudflareJsonDecoder<T>? decode}) async {
    final value = payload;
    return decode == null ? value as T? : decode(value);
  }
}

final class _FakeState implements CloudflareDurableObjectState {
  _FakeState(_FakeSql sql) : storage = _FakeStorage(sql);

  @override
  final CloudflareDurableObjectStorage storage;
  int schemaInitializationCount = 0;

  @override
  CloudflareDurableObjectId get id => _FakeId();

  @override
  CloudflareContainer? get container => null;

  @override
  void waitUntil(Future<void> future) {}

  @override
  Future<T> blockConcurrencyWhile<T>(Future<T> Function() callback) async {
    schemaInitializationCount++;
    return callback();
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

final class _FakeEnvironment implements CloudflareEnvironment {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by the Durable Object test');
}

final class _FakeId implements CloudflareDurableObjectId {
  @override
  String? get name => 'test-object';

  @override
  bool equals(CloudflareDurableObjectId other) => other.name == name;

  @override
  String toString() => name!;
}

final class _FakeStorage implements CloudflareDurableObjectStorage {
  _FakeStorage(this._sql);

  final _FakeSql _sql;

  @override
  CloudflareDurableObjectSqlStorage get sql => _sql;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('legacy Durable Object storage is not used');
}

final class _FakeSql implements CloudflareDurableObjectSqlStorage {
  _FakeSql() : database = sqlite3.openInMemory();

  final Database database;

  void close() => database.close();

  @override
  CloudflareDurableObjectSqlResult exec(
    String query, [
    Iterable<Object?> parameters = const <Object?>[],
  ]) {
    final values = parameters.toList(growable: false);
    if (query.trimLeft().toUpperCase().startsWith('SELECT')) {
      return _FakeSqlResult(database.select(query, values));
    }
    if (query.toUpperCase().contains('RETURNING')) {
      final rows = database.select(query, values);
      return _FakeSqlResult(rows);
    }
    database.execute(query, values);
    return const _FakeSqlResult(<Map<String, Object?>>[]);
  }
}

final class _FakeSqlResult implements CloudflareDurableObjectSqlResult {
  const _FakeSqlResult(this.rows);

  final List<Map<String, Object?>> rows;

  @override
  List<Map<String, Object?>> toArray() => [
    for (final row in rows)
      <String, Object?>{
        for (final entry in row.entries) entry.key: entry.value,
      },
  ];

  @override
  Map<String, Object?> one() => toArray().single;

  @override
  List<Object?> raw() => rows.isEmpty ? const [] : rows.single.values.toList();

  @override
  void run() {}
}
