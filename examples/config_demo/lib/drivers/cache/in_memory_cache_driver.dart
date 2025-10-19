import 'dart:async';

import 'package:routed/routed.dart';

const String inMemoryCacheDriverName = 'in_memory';

class _Entry {
  _Entry(this.value, this.expiresAt);

  dynamic value;
  DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

class _InMemoryCacheStore implements Store {
  _InMemoryCacheStore({required this.prefix, required this.defaultTtl});

  final String prefix;
  final int defaultTtl;
  final Map<String, _Entry> _store = <String, _Entry>{};

  String _wrap(String key) => '$prefix$key';

  void _purgeExpired() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    _store.forEach((key, entry) {
      if (entry.expiresAt != null && now.isAfter(entry.expiresAt!)) {
        expiredKeys.add(key);
      }
    });
    for (final key in expiredKeys) {
      _store.remove(key);
    }
  }

  _Entry _createEntry(dynamic value, int seconds) {
    final effectiveSeconds = seconds > 0 ? seconds : defaultTtl;
    final expiresAt = effectiveSeconds > 0
        ? DateTime.now().add(Duration(seconds: effectiveSeconds))
        : null;
    return _Entry(value, expiresAt);
  }

  @override
  FutureOr<dynamic> get(String key) {
    _purgeExpired();
    return _store[_wrap(key)]?.value;
  }

  @override
  FutureOr<Map<String, dynamic>> many(List<String> keys) {
    _purgeExpired();
    final result = <String, dynamic>{};
    for (final key in keys) {
      result[key] = _store[_wrap(key)]?.value;
    }
    return result;
  }

  @override
  FutureOr<bool> put(String key, dynamic value, int seconds) {
    _store[_wrap(key)] = _createEntry(value, seconds);
    return true;
  }

  @override
  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds) {
    for (final entry in values.entries) {
      _store[_wrap(entry.key)] = _createEntry(entry.value, seconds);
    }
    return true;
  }

  @override
  FutureOr<dynamic> increment(String key, [int value = 1]) {
    _purgeExpired();
    final wrapped = _wrap(key);
    final current = _store[wrapped]?.value;
    final asInt = current is num ? current.toInt() : 0;
    final next = asInt + value;
    _store[wrapped] = _createEntry(next, defaultTtl);
    return next;
  }

  @override
  FutureOr<dynamic> decrement(String key, [int value = 1]) {
    return increment(key, -value);
  }

  @override
  FutureOr<bool> forever(String key, dynamic value) {
    _store[_wrap(key)] = _Entry(value, null);
    return true;
  }

  @override
  FutureOr<bool> forget(String key) {
    _store.remove(_wrap(key));
    return true;
  }

  @override
  FutureOr<bool> flush() {
    _store.clear();
    return true;
  }

  @override
  String getPrefix() => prefix;

  @override
  FutureOr<List<String>> getAllKeys() {
    _purgeExpired();
    return _store.keys
        .map(
          (key) => key.startsWith(prefix) ? key.substring(prefix.length) : key,
        )
        .toList(growable: false);
  }
}

class InMemoryCacheStoreFactory extends StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    final ttl = _intFrom(config['ttl']) ?? 300;
    final namespace = config['namespace']?.toString() ?? 'config-demo:';
    return _InMemoryCacheStore(prefix: namespace, defaultTtl: ttl);
  }

  int? _intFrom(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value.trim());
    if (value is num) return value.toInt();
    return null;
  }
}

void registerInMemoryCacheDriver() {
  CacheManager.registerDriver(
    inMemoryCacheDriverName,
    () => InMemoryCacheStoreFactory(),
    documentation: (ctx) => <ConfigDocEntry>[
      ConfigDocEntry(
        path: ctx.path('ttl'),
        type: 'int',
        description:
            'Default TTL (seconds) applied when cache writes omit a duration.',
      ),
      ConfigDocEntry(
        path: ctx.path('namespace'),
        type: 'string',
        description: 'Prefix applied to cache keys stored by this driver.',
      ),
    ],
  );
}
