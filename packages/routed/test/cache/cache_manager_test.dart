import 'dart:async';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/src/cache/array_store_factory.dart';
import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/cache/file_lock.dart';
import 'package:routed/src/cache/file_store.dart';
import 'package:routed/src/cache/file_store_factory.dart';
import 'package:routed/src/cache/lock.dart';
import 'package:routed/src/cache/null_lock.dart';
import 'package:routed/src/cache/null_store.dart';
import 'package:routed/src/cache/null_store_factory.dart';
import 'package:routed/src/cache/redis_lock.dart';
import 'package:routed/src/cache/redis_store.dart';
import 'package:routed/src/cache/redis_store_factory.dart';
import 'package:routed/src/cache/tag_set.dart';
import 'package:routed/src/cache/tagged_cache.dart';
import 'package:routed/src/contracts/cache/lock_timeout_exception.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:redis/redis.dart';
import 'package:test/test.dart';

void main() {
  group('CacheManager Tests', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
      cacheManager.registerStoreFactory('array', ArrayStoreFactory());
      cacheManager.registerStoreFactory('file', FileStoreFactory());
    });

    test('store and retrieve from array store', () async {
      cacheManager.registerStore('array', {'driver': 'array'});
      final repository = cacheManager.store('array');
      await repository.put('key', 'value', const Duration(seconds: 60));
      final value = await repository.pull('key');
      expect(value, 'value');
    });

    test('store and retrieve from file store', () async {
      final fs = MemoryFileSystem();
      final tempDir = fs.systemTempDirectory.createTempSync();
      cacheManager.registerStore('file', {
        'driver': 'file',
        'path': tempDir.path,
        'permission': null,
        'file_system': fs,
      });
      final repository = cacheManager.store('file');
      await repository.put('key', 'value', const Duration(seconds: 60));
      final value = await repository.pull('key');
      expect(value, 'value');
      tempDir.deleteSync(recursive: true);
    });

    test('increment and decrement in array store', () async {
      cacheManager.registerStore('array', {'driver': 'array'});
      final repository = cacheManager.store('array');
      await repository.put('counter', 1, const Duration(seconds: 60));
      await repository.increment('counter', 1);
      var value = await repository.pull('counter');
      expect(value, 2);

      await repository.put('counter', 1, const Duration(seconds: 60));
      await repository.decrement('counter', 1);
      value = await repository.pull('counter');
      expect(value, 0);
    });

    test('increment and decrement in file store', () async {
      final fs = MemoryFileSystem();
      final tempDir = fs.systemTempDirectory.createTempSync();
      cacheManager.registerStore('file', {
        'driver': 'file',
        'path': tempDir.path,
        'permission': null,
        'file_system': fs,
      });
      final repository = cacheManager.store('file');
      await repository.put('counter', 1, const Duration(seconds: 60));
      await repository.increment('counter', 1);
      var value = await repository.pull('counter');
      expect(value, 2);

      await repository.put('counter', 1, const Duration(seconds: 60));
      await repository.decrement('counter', 1);
      value = await repository.pull('counter');
      expect(value, 0);
      tempDir.deleteSync(recursive: true);
    });

    test('flush all items in array store', () async {
      cacheManager.registerStore('array', {'driver': 'array'});
      final repository = cacheManager.store('array');
      await repository.put('key1', 'value1', const Duration(seconds: 60));
      await repository.put('key2', 'value2', const Duration(seconds: 60));
      await repository.getStore().flush();
      final value1 = await repository.pull('key1');
      final value2 = await repository.pull('key2');
      expect(value1, isNull);
      expect(value2, isNull);
    });

    test('flush all items in file store', () async {
      final fs = MemoryFileSystem();
      final tempDir = fs.systemTempDirectory.createTempSync();
      cacheManager.registerStore('file', {
        'driver': 'file',
        'path': tempDir.path,
        'permission': null,
        'file_system': fs,
      });
      final repository = cacheManager.store('file');
      await repository.put('key1', 'value1', const Duration(seconds: 60));
      await repository.put('key2', 'value2', const Duration(seconds: 60));
      await repository.getStore().flush();
      final value1 = await repository.pull('key1');
      final value2 = await repository.pull('key2');
      expect(value1, isNull);
      expect(value2, isNull);
      tempDir.deleteSync(recursive: true);
    });

    test('registerDriver wires custom cache store', () async {
      CacheManager.registerDriver('custom', () => ArrayStoreFactory());
      addTearDown(() {
        CacheManager.unregisterDriver('custom');
      });

      final manager = CacheManager();
      manager.registerStore('custom-store', {'driver': 'custom'});
      final repository = manager.store('custom-store');
      await repository.put('key', 'value', const Duration(seconds: 60));
      expect(await repository.pull('key'), equals('value'));
    });

    test('custom driver override takes precedence over built-in', () async {
      var invoked = false;
      CacheManager.unregisterDriver('array');
      CacheManager.registerDriver('array', () {
        invoked = true;
        return ArrayStoreFactory();
      }, overrideExisting: true);
      addTearDown(() {
        CacheManager.unregisterDriver('array');
        CacheManager.registerDriver(
          'array',
          () => ArrayStoreFactory(),
          overrideExisting: true,
        );
      });

      final manager = CacheManager();
      manager.registerStore('override', {'driver': 'array'});
      await manager
          .store('override')
          .put('x', 'y', const Duration(seconds: 60));

      expect(invoked, isTrue);
    });
  });

  group('Cache tagging and locks', () {
    test('taggable store creates tagged cache', () {
      final store = NullStore();
      final tagged = store.tags(['user', 'session']);

      expect(tagged, isA<TaggedCache>());
      expect(tagged.getStore(), same(store));
      expect(tagged.getTags().getNames(), equals(['user', 'session']));
    });

    test('tag set manages tag identifiers', () {
      final store = _SyncStore();
      final tags = TagSet(store, ['alpha', 'beta']);

      tags.reset();
      final alphaId = tags.tagId('alpha');
      final betaId = tags.tagId('beta');

      expect(alphaId, isNotEmpty);
      expect(betaId, isNotEmpty);
      expect(tags.tagIds(), equals([alphaId, betaId]));
      expect(tags.getNamespace(), equals('$alphaId|$betaId'));
      expect(tags.tagKey('alpha'), equals('tag:alpha:key'));
      expect(tags.getNames(), equals(['alpha', 'beta']));

      tags.flush();
      expect(store.get('tag:alpha:key'), isNull);
      expect(store.get('tag:beta:key'), isNull);

      final refreshed = tags.resetTag('alpha');
      expect(store.get('tag:alpha:key'), equals(refreshed));
    });

    test('tagged cache operations flow through store', () async {
      final store = _SyncStore();
      final tagSet = TagSet(store, ['feature']);
      final cache = TaggedCache(store, tagSet);

      await cache.put('key', 'value', const Duration(seconds: 30));
      expect(await cache.get('key'), equals('value'));
      expect(await cache.add('key', 'other'), isFalse);
      expect(await cache.increment('count', 2), equals(2));
      expect(await cache.decrement('count', 1), equals(1));
      expect(await cache.pull('key'), equals('value'));
      expect(await cache.pull('key', 'default'), equals('default'));

      final remembered = await cache.remember(
        'remember',
        const Duration(seconds: 10),
        () async => 'computed',
      );
      expect(remembered, equals('computed'));
      expect(
        await cache.remember('remember', const Duration(seconds: 10), () async {
          return 'skip';
        }),
        equals('computed'),
      );

      final forever = await cache.sear('forever', () async => 'stored');
      expect(forever, equals('stored'));
      expect(
        await cache.rememberForever('forever', () async => 'skip'),
        equals('stored'),
      );

      expect(cache.getStore(), same(store));
      expect(cache.getTags(), same(tagSet));
    });

    test('null store exposes defaults and locks', () async {
      final store = NullStore();

      expect(await store.get('missing'), isNull);
      expect(await store.put('k', 'v', 30), isTrue);
      expect(await store.putMany({'a': 1}, 5), isTrue);
      expect(await store.increment('count', 4), equals(4));
      expect(await store.decrement('count', 2), equals(-2));
      expect(await store.forever('forever', 'value'), isTrue);
      expect(await store.forget('forever'), isTrue);
      expect(await store.flush(), isTrue);
      expect(await store.many(['a', 'b']), isEmpty);
      expect(await store.getAllKeys(), isEmpty);
      expect(store.getPrefix(), isEmpty);

      final lock = await store.lock('null-lock', 1, 'owner');
      expect(lock, isA<NullLock>());
      expect(await lock.acquire(), isTrue);
      expect(await lock.getCurrentOwner(), equals('owner'));
      expect(await lock.release(), isTrue);
      lock.forceRelease();
      expect(await lock.getCurrentOwner(), isNull);

      final restored = await store.restoreLock('null-lock', 'restored');
      expect(await restored.getCurrentOwner(), equals('restored'));
    });

    test('null store factory creates store', () {
      final factory = NullStoreFactory();

      expect(factory.create(const {}), isA<NullStore>());
    });

    test('redis store factory parses config', () {
      final factory = RedisStoreFactory();
      final store = factory.create({
        'url': 'redis://:secret@localhost:6380/5',
        'db': '2',
        'host': 'override',
      });

      expect(store, isA<RedisStore>());
      final redisStore = store as RedisStore;
      expect(redisStore.host, equals('override'));
      expect(redisStore.port, equals(6380));
      expect(redisStore.password, equals('secret'));
      expect(redisStore.db, equals(2));
    });

    test('redis store parses url and overrides', () {
      final store = RedisStore.fromConfig({
        'url': 'redis://secret@cache-host:6381/3?db=4',
        'host': 'override',
        'port': '6382',
        'database': '7',
        'db': 6,
      });

      expect(store.host, equals('override'));
      expect(store.port, equals(6382));
      expect(store.password, equals('secret'));
      expect(store.db, equals(6));
    });

    test('redis store accepts numeric config values', () {
      final store = RedisStore.fromConfig({
        'host': 'local',
        'port': 6383,
        'database': 5,
      });

      expect(store.host, equals('local'));
      expect(store.port, equals(6383));
      expect(store.db, equals(5));
    });

    test('redis store parses password without colon', () {
      final store = RedisStore.fromConfig({
        'url': 'redis://secret@localhost:6379',
      });

      expect(store.password, equals('secret'));
    });

    test('redis store operations use send override', () async {
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
      expect(await store.decrement('count', 1), equals(2));

      expect(await store.forget('key'), isTrue);
      expect(await store.forget('missing'), isFalse);
      expect(await store.get('key'), isNull);

      final keys = await store.getAllKeys();
      expect(keys, containsAll(['flag', 'payload', 'count', 'one', 'two']));

      await store.flush();
      expect(await store.getAllKeys(), isEmpty);
    });

    test('redis store ensures command initialization', () async {
      final sent = <List<dynamic>>[];
      final connection = _TestRedisConnection((connection) {
        return _TestRedisCommand(connection, (args) {
          sent.add(args);
          if (args.first == 'GET') {
            return 'str:hello';
          }
          return 'OK';
        });
      });
      final store = RedisStore(
        'localhost',
        6379,
        password: 'secret',
        db: 3,
        connection: connection,
      );

      expect(await store.get('greeting'), equals('hello'));
      expect(connection.connectCount, equals(1));
      expect(sent, contains(equals(['AUTH', 'secret'])));
      expect(sent, contains(equals(['SELECT', 3])));
      expect(sent, contains(equals(['GET', 'greeting'])));

      await store.get('greeting');
      expect(connection.connectCount, equals(1));
    });

    test('redis store retries after send error', () async {
      var shouldThrow = true;
      final connection = _TestRedisConnection((connection) {
        return _TestRedisCommand(connection, (args) {
          if (shouldThrow && args.first == 'GET') {
            shouldThrow = false;
            throw StateError('boom');
          }
          return 'str:ok';
        });
      });
      final store = RedisStore('localhost', 6379, connection: connection);

      await expectLater(store.get('key'), throwsA(isA<StateError>()));
      expect(await store.get('key'), equals('ok'));
      expect(connection.connectCount, equals(2));
    });

    test('redis lock delegates to store', () async {
      final backend = _FakeRedisBackend();
      final store = RedisStore('localhost', 6379, sendOverride: backend.send);
      final lock = await store.lock('resource', 1, 'owner');

      expect(lock, isA<RedisLock>());
      expect(await lock.acquire(), isTrue);
      expect(await lock.acquire(), isFalse);
      expect(await lock.getCurrentOwner(), equals('owner'));
      expect(await lock.release(), isTrue);
      expect(await lock.getCurrentOwner(), isNull);

      lock.forceRelease();
      await Future<void>.delayed(Duration.zero);
      expect(await lock.getCurrentOwner(), isNull);
    });

    test('file lock enforces ownership and callbacks', () async {
      final fs = MemoryFileSystem();
      final dir = fs.systemTempDirectory.createTempSync();
      addTearDown(() => dir.deleteSync(recursive: true));

      final store = FileStore(dir, null, null, fs);
      final lock = FileLock(store, 'resource', 1, 'owner');
      expect(await lock.acquire(), isTrue);
      expect(await lock.getCurrentOwner(), equals('owner'));
      expect(await lock.owner(), equals('owner'));
      expect(await lock.isOwnedByCurrentProcess(), isTrue);
      expect(await lock.get(() async => 'result'), equals('result'));
      expect(await lock.release(), isFalse);

      expect(await lock.acquire(), isTrue);
      final other = FileLock(store, 'resource', 1, 'other');
      expect(await other.release(), isFalse);
      expect(await lock.release(), isTrue);

      lock.forceRelease();
      expect(await lock.getCurrentOwner(), isNull);
    });

    test('file lock block throws timeout', () async {
      final fs = MemoryFileSystem();
      final dir = fs.systemTempDirectory.createTempSync();
      addTearDown(() => dir.deleteSync(recursive: true));

      final store = _FailingFileStore(dir, fs);
      final lock = FileLock(store, 'resource', 1, 'owner');

      await expectLater(lock.block(0), throwsA(isA<LockTimeoutException>()));
    });

    test('cache lock get behavior matches base class', () async {
      final lock = _ScriptedLock([true], owner: 'owner');

      expect(lock.owner(), equals('owner'));
      expect(await lock.get(() async => 'done'), equals('done'));
      expect(lock.released, isTrue);
      expect(await lock.getCurrentOwner(), isNull);
      expect(lock.acquireCount, equals(1));
    });

    test('cache lock returns false when acquire fails', () async {
      final lock = _ScriptedLock([false], owner: 'owner');

      expect(await lock.get(), isFalse);
      expect(lock.released, isFalse);
      expect(await lock.isOwnedByCurrentProcess(), isFalse);
    });

    test('cache lock block retries until acquired', () async {
      final lock = _ScriptedLock([false, false, true], owner: 'owner');
      lock.betweenBlockedAttemptsSleepFor(0);

      expect(await lock.block(1, () async => 'ok'), equals('ok'));
      expect(lock.released, isTrue);
      expect(lock.acquireCount, equals(3));
    });

    test('cache lock block throws on timeout', () async {
      final lock = _ScriptedLock([false, false], owner: 'owner');
      lock.betweenBlockedAttemptsSleepFor(0);

      await expectLater(lock.block(0), throwsA(isA<LockTimeoutException>()));
    });
  });
}

class _ScriptedLock extends CacheLock {
  _ScriptedLock(this.results, {String? owner}) : super('scripted', 1, owner);

  final List<bool> results;
  int acquireCount = 0;
  bool released = false;
  String? _currentOwner;

  @override
  Future<bool> acquire() async {
    final result = acquireCount < results.length
        ? results[acquireCount]
        : results.last;
    acquireCount += 1;
    if (result) {
      _currentOwner = ownerId;
    }
    return result;
  }

  @override
  Future<bool> release() async {
    released = true;
    _currentOwner = null;
    return true;
  }

  @override
  Future<String?> getCurrentOwner() async {
    return _currentOwner;
  }

  @override
  void forceRelease() {
    released = true;
    _currentOwner = null;
  }
}

class _TestRedisConnection extends RedisConnection {
  _TestRedisConnection(this.commandFactory);

  final Command Function(RedisConnection connection) commandFactory;
  int connectCount = 0;

  @override
  Future<Command> connect(host, port) async {
    connectCount += 1;
    return commandFactory(this);
  }
}

class _TestRedisCommand extends Command {
  _TestRedisCommand(this.connection, this.onSend) : super(connection);

  final RedisConnection connection;
  final FutureOr<dynamic> Function(List<dynamic>) onSend;

  // ignore: non_constant_identifier_names
  @override
  Future<dynamic> send_object(Object obj) {
    final args = obj is List ? List<dynamic>.from(obj) : <dynamic>[obj];
    return Future.sync(() => onSend(args));
  }
}

class _SyncStore implements Store {
  final Map<String, dynamic> data = {};

  @override
  dynamic get(String key) => data[key];

  @override
  Map<String, dynamic> many(List<String> keys) {
    return {for (final key in keys) key: data[key]};
  }

  @override
  bool put(String key, dynamic value, int seconds) {
    data[key] = value;
    return true;
  }

  @override
  bool putMany(Map<String, dynamic> values, int seconds) {
    data.addAll(values);
    return true;
  }

  @override
  dynamic increment(String key, [int value = 1]) {
    final current = data[key] ?? 0;
    final next =
        (current is num ? current : int.parse(current.toString())) + value;
    data[key] = next;
    return next;
  }

  @override
  dynamic decrement(String key, [int value = 1]) {
    return increment(key, -value);
  }

  @override
  bool forever(String key, dynamic value) {
    return put(key, value, 0);
  }

  @override
  bool forget(String key) {
    return data.remove(key) != null;
  }

  @override
  bool flush() {
    data.clear();
    return true;
  }

  @override
  String getPrefix() => '';

  @override
  List<String> getAllKeys() => data.keys.toList();
}

class _FailingFileStore extends FileStore {
  _FailingFileStore(Directory directory, FileSystem fileSystem)
    : super(directory, null, null, fileSystem);

  @override
  bool put(String key, dynamic value, int seconds) {
    return false;
  }
}

class _FakeRedisBackend {
  final Map<String, String> values = {};
  final Map<String, int> expiries = {};

  Future<dynamic> send(List<dynamic> args) async {
    final command = args.first.toString();
    switch (command) {
      case 'GET':
        return values[args[1].toString()];
      case 'MGET':
        return args.skip(1).map((key) => values[key.toString()]).toList();
      case 'SET':
        final key = args[1].toString();
        final value = args[2].toString();
        final hasNx = args.contains('NX');
        if (hasNx && values.containsKey(key)) {
          return null;
        }
        values[key] = value;
        final exIndex = args.indexOf('EX');
        if (exIndex != -1 && exIndex + 1 < args.length) {
          expiries[key] = int.parse(args[exIndex + 1].toString()) * 1000;
        }
        return 'OK';
      case 'DEL':
        return values.remove(args[1].toString()) != null ? 1 : 0;
      case 'FLUSHDB':
        values.clear();
        expiries.clear();
        return 'OK';
      case 'PTTL':
        return expiries[args[1].toString()] ?? -1;
      case 'INCRBY':
        final key = args[1].toString();
        final incrementBy = int.parse(args[2].toString());
        final current = int.tryParse(values[key] ?? '0') ?? 0;
        final next = current + incrementBy;
        values[key] = next.toString();
        return next;
      case 'DECRBY':
        final key = args[1].toString();
        final decrementBy = int.parse(args[2].toString());
        final current = int.tryParse(values[key] ?? '0') ?? 0;
        final next = current - decrementBy;
        values[key] = next.toString();
        return next;
      case 'PEXPIRE':
        expiries[args[1].toString()] = int.parse(args[2].toString());
        return 1;
      case 'SCAN':
        return ['0', values.keys.toList()];
      case 'EVAL':
        final key = args[3].toString();
        final owner = args[4].toString();
        if (values[key] == owner) {
          values.remove(key);
          return 1;
        }
        return 0;
    }
    throw StateError('Unhandled command: $command');
  }
}
