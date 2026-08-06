import 'dart:async';

import 'package:server_contracts/server_contracts.dart';

void main() async {
  final config = InMemoryConfig({
    'cache': {'default': 'array'},
  });

  final repository = InMemoryRepository(InMemoryStore());
  await repository.put('health', 'ok', const Duration(seconds: 30));

  final translator = SimpleTranslator(locale: 'en', fallbackLocale: 'en')
    ..addLines({'welcome': 'Hello :name'}, 'en');

  print('cache.default = ${config.get<String>('cache.default')}');
  print('cache health = ${await repository.get('health')}');
  print(
    translator.translate('welcome', replacements: const {'name': 'contracts'}),
  );
}

class InMemoryConfig implements Config {
  InMemoryConfig(Map<String, dynamic> initial)
    : _values = Map<String, dynamic>.from(initial);

  final Map<String, dynamic> _values;

  @override
  Map<String, dynamic> all() => Map<String, dynamic>.from(_values);

  @override
  T? get<T>(String key, [T? defaultValue]) {
    final value = _read(key);
    if (value == null) return defaultValue;
    if (value is T) return value;
    return defaultValue;
  }

  @override
  T getOrThrow<T>(String key, {String? message}) {
    final value = get<T>(key);
    if (value == null) {
      throw StateError(message ?? 'Missing configuration key: $key');
    }
    return value;
  }

  @override
  bool has(String key) => _read(key) != null;

  @override
  void merge(Map<String, dynamic> values) {
    for (final entry in values.entries) {
      set(entry.key, entry.value);
    }
  }

  @override
  void mergeDefaults(Map<String, dynamic> values) {
    for (final entry in values.entries) {
      if (!has(entry.key)) {
        set(entry.key, entry.value);
      }
    }
  }

  @override
  void prepend(String key, dynamic value) {
    final list = (get<List<dynamic>>(key) ?? <dynamic>[])..insert(0, value);
    set(key, list);
  }

  @override
  void push(String key, dynamic value) {
    final list = (get<List<dynamic>>(key) ?? <dynamic>[])..add(value);
    set(key, list);
  }

  @override
  void set(String key, dynamic value) {
    final segments = key.split('.');
    Map<String, dynamic> current = _values;
    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      final existing = current[segment];
      if (existing is! Map<String, dynamic>) {
        final child = <String, dynamic>{};
        current[segment] = child;
        current = child;
      } else {
        current = existing;
      }
    }
    current[segments.last] = value;
  }

  dynamic _read(String key) {
    final segments = key.split('.');
    dynamic current = _values;
    for (final segment in segments) {
      if (current is! Map<String, dynamic>) return null;
      current = current[segment];
      if (current == null) return null;
    }
    return current;
  }
}

class InMemoryStore implements Store {
  final Map<String, dynamic> _values = <String, dynamic>{};

  @override
  FutureOr<dynamic> decrement(String key, [int value = 1]) {
    final current = (_values[key] as num?)?.toInt() ?? 0;
    final next = current - value;
    _values[key] = next;
    return next;
  }

  @override
  FutureOr<bool> flush() {
    _values.clear();
    return true;
  }

  @override
  FutureOr<bool> forget(String key) => _values.remove(key) != null;

  @override
  FutureOr<dynamic> get(String key) => _values[key];

  @override
  FutureOr<List<String>> getAllKeys() => _values.keys.toList(growable: false);

  @override
  String getPrefix() => '';

  @override
  FutureOr<dynamic> increment(String key, [int value = 1]) {
    final current = (_values[key] as num?)?.toInt() ?? 0;
    final next = current + value;
    _values[key] = next;
    return next;
  }

  @override
  FutureOr<Map<String, dynamic>> many(List<String> keys) {
    return {for (final key in keys) key: _values[key]};
  }

  @override
  FutureOr<bool> forever(String key, dynamic value) {
    _values[key] = value;
    return true;
  }

  @override
  FutureOr<bool> put(String key, dynamic value, int seconds) {
    _values[key] = value;
    return true;
  }

  @override
  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds) {
    _values.addAll(values);
    return true;
  }
}

class InMemoryRepository implements Repository {
  InMemoryRepository(this._store);

  final Store _store;

  @override
  FutureOr<bool> add(String key, dynamic value, [Duration? ttl]) async {
    if (await _store.get(key) != null) {
      return false;
    }
    return put(key, value, ttl);
  }

  @override
  FutureOr<dynamic> decrement(String key, [dynamic value = 1]) {
    return _store.decrement(key, value is int ? value : 1);
  }

  @override
  FutureOr<bool> forever(String key, dynamic value) =>
      _store.forever(key, value);

  @override
  FutureOr<bool> forget(String key) => _store.forget(key);

  @override
  FutureOr<dynamic> get(String key) => _store.get(key);

  @override
  Store getStore() => _store;

  @override
  FutureOr<dynamic> increment(String key, [dynamic value = 1]) {
    return _store.increment(key, value is int ? value : 1);
  }

  @override
  FutureOr<bool> put(String key, dynamic value, [Duration? ttl]) {
    return _store.put(key, value, ttl?.inSeconds ?? 0);
  }

  @override
  FutureOr<dynamic> pull(dynamic key, [dynamic defaultValue]) async {
    final keyString = key.toString();
    final value = await _store.get(keyString);
    if (value == null) return defaultValue;
    await _store.forget(keyString);
    return value;
  }

  @override
  FutureOr<dynamic> remember(String key, dynamic ttl, Function callback) async {
    final existing = await _store.get(key);
    if (existing != null) return existing;
    final value = await callback();
    final seconds = ttl is Duration
        ? ttl.inSeconds
        : ttl is int
        ? ttl
        : 0;
    await _store.put(key, value, seconds);
    return value;
  }

  @override
  FutureOr<dynamic> rememberForever(String key, Function callback) async {
    return remember(key, 0, callback);
  }

  @override
  FutureOr<dynamic> sear(String key, Function callback) {
    return rememberForever(key, callback);
  }
}

class SimpleTranslator implements TranslatorContract {
  SimpleTranslator({required this.locale, this.fallbackLocale});

  final Map<String, Map<String, dynamic>> _lines =
      <String, Map<String, dynamic>>{};
  Object? Function(String key, String locale)? _missingHandler;

  @override
  String locale;

  @override
  String? fallbackLocale;

  @override
  void addLines(
    Map<String, dynamic> lines,
    String locale, {
    String namespace = '*',
  }) {
    final map = _lines.putIfAbsent(locale, () => <String, dynamic>{});
    map.addAll(lines);
  }

  @override
  String choice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  }) {
    final raw = translate(
      key,
      replacements: replacements,
      locale: locale,
    )?.toString();
    if (raw == null) return key;
    final parts = raw.split('|');
    if (parts.length < 2) return raw;
    return count == 1 ? parts.first : parts.last;
  }

  @override
  void handleMissingKeysUsing(
    Object? Function(String key, String locale)? callback,
  ) {
    _missingHandler = callback;
  }

  @override
  bool has(String key, {String? locale, bool fallback = true}) {
    final target = locale ?? this.locale;
    if (_resolve(target, key) != null) return true;
    if (!fallback) return false;
    final fb = fallbackLocale;
    if (fb == null || fb == target) return false;
    return _resolve(fb, key) != null;
  }

  @override
  bool hasForLocale(String key, String locale) => _resolve(locale, key) != null;

  @override
  Object? translate(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  }) {
    final target = locale ?? this.locale;
    var value = _resolve(target, key);
    if (value == null && fallback) {
      final fb = fallbackLocale;
      if (fb != null && fb != target) {
        value = _resolve(fb, key);
      }
    }
    if (value == null) {
      return _missingHandler?.call(key, target) ?? key;
    }
    if (value is! String || replacements == null || replacements.isEmpty) {
      return value;
    }
    var result = value;
    replacements.forEach((placeholder, replacement) {
      result = result.replaceAll(':$placeholder', replacement.toString());
    });
    return result;
  }

  Object? _resolve(String locale, String key) {
    final map = _lines[locale];
    if (map == null) return null;
    return map[key];
  }
}
