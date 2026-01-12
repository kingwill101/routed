import 'dart:async';
import 'dart:convert';

import 'package:redis/redis.dart';
import 'package:routed/src/cache/taggable_store.dart';
import 'package:routed/src/contracts/cache/lock.dart';
import 'package:routed/src/contracts/cache/lock_provider.dart';
import 'package:routed/src/contracts/cache/store.dart';

import 'redis_lock.dart';

class RedisStore extends TaggableStore implements Store, LockProvider {
  RedisStore(
    this.host,
    this.port, {
    this.password,
    this.db,
    RedisConnection? connection,
    Future<dynamic> Function(List<dynamic>)? sendOverride,
  }) : _connection = connection ?? RedisConnection(),
       _sendOverride = sendOverride;

  factory RedisStore.fromConfig(Map<String, dynamic> config) {
    String? url;
    if (config['url'] != null) {
      url = config['url'].toString();
    }

    String host = '127.0.0.1';
    int port = 6379;
    String? password;
    int? db;

    if (url != null && url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        host = uri.host;
      }
      if (uri.port != 0) {
        port = uri.port;
      }
      if (uri.userInfo.isNotEmpty) {
        final parts = uri.userInfo.split(':');
        if (parts.isNotEmpty) {
          password = parts.length > 1 ? parts[1] : parts[0];
        }
      }
      if (uri.pathSegments.isNotEmpty) {
        final parsed = int.tryParse(uri.pathSegments.last);
        if (parsed != null) {
          db = parsed;
        }
      }
      if (uri.queryParameters.containsKey('db')) {
        db = int.tryParse(uri.queryParameters['db']!.toString());
      }
    }

    if (config['host'] != null) {
      host = config['host'].toString();
    }
    if (config['port'] != null) {
      final portValue = config['port'];
      if (portValue is num) {
        port = portValue.toInt();
      } else {
        port = int.tryParse(portValue.toString()) ?? port;
      }
    }
    if (config['password'] != null) {
      password = config['password'].toString();
    }
    if (config['database'] != null) {
      final dbValue = config['database'];
      if (dbValue is num) {
        db = dbValue.toInt();
      } else {
        db = int.tryParse(dbValue.toString()) ?? db;
      }
    }
    if (config['db'] != null) {
      final dbValue = config['db'];
      if (dbValue is num) {
        db = dbValue.toInt();
      } else {
        db = int.tryParse(dbValue.toString()) ?? db;
      }
    }
    return RedisStore(host, port, password: password, db: db);
  }

  final String host;
  final int port;
  final String? password;
  final int? db;

  final RedisConnection _connection;
  final Future<dynamic> Function(List<dynamic>)? _sendOverride;
  Command? _command;
  bool _connecting = false;

  String _lockKey(String name) => 'lock:$name';

  Future<Command> _ensureCommand() async {
    if (_command != null) {
      return _command!;
    }
    while (_connecting) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (_command != null) {
        return _command!;
      }
    }
    _connecting = true;
    try {
      final command = await _connection.connect(host, port);
      if (password?.isNotEmpty == true) {
        await command.send_object(['AUTH', password]);
      }
      if (db != null) {
        await command.send_object(['SELECT', db]);
      }
      _command = command;
      return command;
    } finally {
      _connecting = false;
    }
  }

  Future<dynamic> _send(List<dynamic> args) async {
    if (_sendOverride != null) {
      return _sendOverride!(args);
    }
    final cmd = await _ensureCommand();
    try {
      return await cmd.send_object(args);
    } catch (_) {
      _command = null;
      rethrow;
    }
  }

  @override
  Future<dynamic> get(String key) async {
    final value = await _send(['GET', key]);
    if (value == null) return null;
    if (value is String) return _decode(value);
    return value;
  }

  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    if (keys.isEmpty) return <String, dynamic>{};
    final response = await _send(['MGET', ...keys]);
    final results = <String, dynamic>{};
    if (response is List) {
      for (var i = 0; i < keys.length; i++) {
        final value = i < response.length ? response[i] : null;
        if (value == null) {
          results[keys[i]] = null;
        } else if (value is String) {
          results[keys[i]] = _decode(value);
        } else {
          results[keys[i]] = value;
        }
      }
    }
    return results;
  }

  @override
  Future<bool> put(String key, dynamic value, int seconds) async {
    final encoded = _encode(value);
    final args = ['SET', key, encoded];
    if (seconds > 0) {
      args
        ..add('EX')
        ..add(seconds.toString());
    }
    final reply = await _send(args);
    return reply == 'OK';
  }

  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    if (values.isEmpty) return true;
    for (final entry in values.entries) {
      await put(entry.key, entry.value, seconds);
    }
    return true;
  }

  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final incrementBy = value is num ? value.toInt() : 1;
    final ttl = await _send(['PTTL', key]);
    final result = await _send(['INCRBY', key, incrementBy]);
    if (ttl is int && ttl > 0) {
      await _send(['PEXPIRE', key, ttl]);
    }
    if (result is num) return result;
    return int.tryParse(result.toString()) ?? result;
  }

  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    final decrementBy = value is num ? value.toInt() : 1;
    final ttl = await _send(['PTTL', key]);
    final result = await _send(['DECRBY', key, decrementBy]);
    if (ttl is int && ttl > 0) {
      await _send(['PEXPIRE', key, ttl]);
    }
    if (result is num) return result;
    return int.tryParse(result.toString()) ?? result;
  }

  @override
  Future<bool> forever(String key, dynamic value) async {
    return put(key, value, 0);
  }

  @override
  Future<bool> forget(String key) async {
    final result = await _send(['DEL', key]);
    if (result is int) {
      return result > 0;
    }
    return false;
  }

  @override
  Future<bool> flush() async {
    await _send(['FLUSHDB']);
    return true;
  }

  @override
  String getPrefix() => '';

  @override
  Future<List<String>> getAllKeys() async {
    final keys = <String>[];
    var cursor = '0';
    do {
      final result = await _send(['SCAN', cursor]);
      if (result is List && result.length == 2) {
        cursor = result[0].toString();
        final items = result[1];
        if (items is List) {
          keys.addAll(items.map((e) => e.toString()));
        }
      } else {
        break;
      }
    } while (cursor != '0');
    return keys;
  }

  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async {
    return RedisLock(this, name, seconds, owner);
  }

  @override
  Future<Lock> restoreLock(String name, String owner) async {
    return RedisLock(this, name, 0, owner);
  }

  Future<bool> acquireLock(String name, String owner, int seconds) async {
    final ttl = seconds > 0 ? seconds : 10;
    final result = await _send([
      'SET',
      _lockKey(name),
      owner,
      'NX',
      'PX',
      (ttl * 1000).toString(),
    ]);
    return result == 'OK';
  }

  Future<bool> releaseLock(String name, String owner) async {
    final script =
        'if redis.call("GET", KEYS[1]) == ARGV[1] then return redis.call("DEL", KEYS[1]) else return 0 end';
    final result = await _send(['EVAL', script, '1', _lockKey(name), owner]);
    if (result is int) {
      return result > 0;
    }
    return false;
  }

  Future<String?> lockOwner(String name) async {
    final owner = await _send(['GET', _lockKey(name)]);
    if (owner == null) return null;
    return owner.toString();
  }

  void forceReleaseLock(String name) {
    unawaited(_send(['DEL', _lockKey(name)]));
  }

  String _encode(dynamic value) {
    if (value == null) return 'null';
    if (value is num) return value.toString();
    if (value is bool) return value ? 'bool:1' : 'bool:0';
    if (value is String) return 'str:$value';
    return 'json:${jsonEncode(value)}';
  }

  dynamic _decode(String value) {
    if (value == 'null') return null;
    if (value.startsWith('bool:')) {
      return value.substring(5) == '1';
    }
    if (value.startsWith('str:')) {
      return value.substring(4);
    }
    if (value.startsWith('json:')) {
      try {
        return jsonDecode(value.substring(5));
      } catch (_) {
        return value.substring(5);
      }
    }
    final parsed = num.tryParse(value);
    if (parsed != null) {
      if (parsed % 1 == 0) return parsed.toInt();
      return parsed;
    }
    return value;
  }
}
