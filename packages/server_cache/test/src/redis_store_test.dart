// These ignores cover private test doubles that mirror the Redis client API.
// ignore_for_file: unused_element, non_constant_identifier_names
import 'dart:async';

import 'package:redis/redis.dart';
import 'package:server_cache/server_cache.dart';
import 'package:test/test.dart';

void main() {
  group('RedisStore', () {
    test('factory parses config with url and overrides', () {
      final factory = RedisStoreFactory();
      final store = factory.create(
        RedisStoreConfiguration(
          url: Uri.parse('redis://:secret@localhost:6380/5'),
          database: 2,
          host: 'override',
        ),
      );
      expect(store, isA<RedisStore>());
      final redisStore = store as RedisStore;
      expect(redisStore.host, equals('override'));
      expect(redisStore.port, equals(6380));
      expect(redisStore.password, equals('secret'));
      expect(redisStore.db, equals(2));
    });

    test('typed configuration parses url and overrides', () {
      final store =
          RedisStoreFactory().create(
                RedisStoreConfiguration(
                  url: Uri.parse('redis://secret@cache-host:6381/3?db=4'),
                  host: 'override',
                  port: 6382,
                  database: 6,
                ),
              )
              as RedisStore;
      expect(store.host, equals('override'));
      expect(store.port, equals(6382));
      expect(store.password, equals('secret'));
      expect(store.db, equals(6));
    });

    test('typed configuration accepts numeric values', () {
      final store =
          RedisStoreFactory().create(
                const RedisStoreConfiguration(
                  host: 'local',
                  port: 6383,
                  database: 5,
                ),
              )
              as RedisStore;
      expect(store.host, equals('local'));
      expect(store.port, equals(6383));
      expect(store.db, equals(5));
    });

    test('typed configuration parses password without colon', () {
      final store =
          RedisStoreFactory().create(
                RedisStoreConfiguration(
                  url: Uri.parse('redis://secret@localhost:6379'),
                ),
              )
              as RedisStore;
      expect(store.password, equals('secret'));
    });

    test('operations use send override', () async {
      final backend = _FakeRedisBackend();
      final store = RedisStore('localhost', 6379, sendOverride: backend.send);
      expect(store.getPrefix(), isEmpty);
      await store.put('key', 'value', 10);
      await store.put('flag', true, 0);
      await store.put('payload', {'a': 1}, 0);
      await store.put('count', 1, 0);
      await store.put('nothing', null, 0);
      backend.expiries['count'] = 1000;
      expect(await store.get('key'), equals('value'));
      expect(await store.get('flag'), isTrue);
      expect(await store.get('payload'), equals({'a': 1}));
      expect(await store.get('nothing'), isNull);
      backend.values['raw-json'] = 'json:{oops';
      backend.values['float'] = '12.5';
      backend.values['int'] = '7';
      backend.values['false'] = 'bool:0';
      backend.values['string'] = 'str:hello';
      expect(await store.get('raw-json'), equals('{oops'));
      expect(await store.get('float'), equals(12.5));
      expect(await store.get('int'), equals(7));
      expect(await store.get('false'), isFalse);
      expect(await store.get('string'), equals('hello'));
      await store.putMany({'one': 1, 'two': 'second'}, 0);
      expect(
        await store.many(['one', 'two', 'missing']),
        equals({'one': 1, 'two': 'second', 'missing': null}),
      );
      expect(await store.increment('count', 2), equals(3));
      expect(await store.decrement('count'), equals(2));
      expect(await store.forget('key'), isTrue);
      expect(await store.forget('missing'), isFalse);
      expect(await store.get('key'), isNull);
    });

    test('lock uses redis', () async {
      final backend = _FakeRedisBackend();
      final store = RedisStore('localhost', 6379, sendOverride: backend.send);
      final lock = await store.lock('my-lock', 10);
      expect(lock, isA<RedisLock>());
    });
  });

  group('RedisStoreFactory', () {
    test('creates RedisStore from typed configuration', () {
      final factory = RedisStoreFactory();
      final store = factory.create(
        const RedisStoreConfiguration(host: '127.0.0.1', port: 6379),
      );
      expect(store, isA<RedisStore>());
    });
  });
}

class _FakeRedisBackend {
  final Map<String, String> values = {};
  final Map<String, int> expiries = {};
  Future<dynamic> send(List<dynamic> args) async {
    final cmd = args[0].toString().toUpperCase();
    if (cmd == 'SET') {
      final key = args[1].toString();
      final val = args[2].toString();
      values[key] = val;
      if (args.length > 3 && args[3] == 'EX') {
        expiries[key] = int.tryParse(args[4].toString()) ?? 0;
      }
      return 'OK';
    }
    if (cmd == 'GET') return values[args[1].toString()];
    if (cmd == 'MGET') {
      return args.sublist(1).map((k) => values[k.toString()]).toList();
    }
    if (cmd == 'DEL') {
      final existed = values.containsKey(args[1].toString());
      values.remove(args[1].toString());
      return existed ? 1 : 0;
    }
    if (cmd == 'INCRBY' || cmd == 'DECRBY') {
      final key = args[1].toString();
      final delta = int.parse(args[2].toString());
      final cur = int.tryParse(values[key] ?? '0') ?? 0;
      final next = cmd == 'INCRBY' ? cur + delta : cur - delta;
      values[key] = next.toString();
      return next;
    }
    return 'OK';
  }
}

class _TestRedisConnection extends RedisConnection {
  _TestRedisConnection(this.commandFactory);
  final Command Function(RedisConnection connection) commandFactory;
  int connectCount = 0;
  @override
  Future<Command> connect(dynamic host, dynamic port) async {
    connectCount += 1;
    return commandFactory(this);
  }
}

class _TestRedisCommand extends Command {
  _TestRedisCommand(this.connection, this.onSend) : super(connection);
  final RedisConnection connection;
  final FutureOr<dynamic> Function(List<dynamic>) onSend;
  @override
  Future<dynamic> send_object(Object obj) {
    final args = obj is List ? List<dynamic>.from(obj) : <dynamic>[obj];
    return Future.sync(() => onSend(args));
  }
}
