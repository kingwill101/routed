import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

class CacheStoreConfig {
  CacheStoreConfig({this.driver, Map<String, dynamic>? options})
    : options = options ?? const <String, dynamic>{};

  final String? driver;
  final Map<String, dynamic> options;

  factory CacheStoreConfig.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    final driverValue = map['driver'];
    if (driverValue != null && driverValue is! String) {
      throw ProviderConfigException('$context.driver must be a string');
    }
    final options = Map<String, dynamic>.from(map)..remove('driver');
    return CacheStoreConfig(
      driver: driverValue as String?,
      options: options,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{...options};
    if (driver != null) {
      map['driver'] = driver;
    }
    return map;
  }
}

class CacheConfig {
  CacheConfig({
    required this.stores,
    this.defaultStore,
    this.prefix,
    this.keyPrefix,
    this.appPrefix,
  });

  final Map<String, CacheStoreConfig> stores;
  final String? defaultStore;
  final String? prefix;
  final String? keyPrefix;
  final String? appPrefix;

  String? resolvePrefix() {
    if (prefix != null) return prefix;
    if (keyPrefix != null) return keyPrefix;
    if (appPrefix != null) return appPrefix;
    return null;
  }
}

class CacheConfigSpec extends ConfigSpec<CacheConfig> {
  const CacheConfigSpec();

  @override
  String get root => 'cache';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'default': 'file',
      'prefix': '',
      'key_prefix': null,
      'stores': {
        'array': {'driver': 'array'},
        'file': {'driver': 'file'},
      },
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('default'),
        type: 'string',
        description:
            'Name of the cache store to use when none is specified explicitly.',
        defaultValue: 'file',
        metadata: {configDocMetaInheritFromEnv: 'CACHE_STORE'},
      ),
      ConfigDocEntry(
        path: path('prefix'),
        type: 'string',
        description:
            'Prefix prepended to every cache key. Useful when sharing stores.',
        defaultValue: '',
      ),
      ConfigDocEntry(
        path: path('key_prefix'),
        type: 'string',
        description:
            'Optional global prefix injected before the generated store prefix.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: path('stores'),
        type: 'map',
        description: 'Configured cache stores keyed by store name.',
        defaultValueBuilder: () {
          return {
            'array': {'driver': 'array'},
            'file': {'driver': 'file'},
          };
        },
      ),
      ConfigDocEntry(
        path: path('stores.*.driver'),
        type: 'string',
        description: 'Driver identifier backing the cache store.',
        optionsBuilder: () => CacheManager.registeredDrivers,
      ),
      ...CacheManager.driverDocumentation(pathBase: path('stores.*')),
    ];
  }

  @override
  CacheConfig fromMap(Map<String, dynamic> map, {ConfigSpecContext? context}) {
    final defaultValue = map['default'];
    if (defaultValue != null && defaultValue is! String) {
      throw ProviderConfigException('cache.default must be a string');
    }

    String? prefix;
    if (map.containsKey('prefix')) {
      final value = map['prefix'];
      if (value == null) {
        prefix = '';
      } else if (value is String) {
        prefix = value;
      } else {
        throw ProviderConfigException('cache.prefix must be a string');
      }
    }

    String? keyPrefix;
    if (map.containsKey('key_prefix')) {
      final value = map['key_prefix'];
      if (value == null) {
        keyPrefix = '';
      } else if (value is String) {
        keyPrefix = value;
      } else {
        throw ProviderConfigException('cache.key_prefix must be a string');
      }
    }

    String? appPrefix;
    final config = context?.config;
    if (config != null && config.has('app.cache_prefix')) {
      final value = config.get<Object?>('app.cache_prefix');
      if (value == null) {
        appPrefix = '';
      } else if (value is String) {
        appPrefix = value;
      } else {
        throw ProviderConfigException('app.cache_prefix must be a string');
      }
    }

    final stores = <String, CacheStoreConfig>{};
    final rawStores = map['stores'];
    if (rawStores != null) {
      if (rawStores is! Map) {
        throw ProviderConfigException('cache.stores must be a map');
      }
      rawStores.forEach((key, value) {
        final storeName = key.toString();
        if (value == null || value is! Map) {
          throw ProviderConfigException('cache.stores.$storeName must be a map');
        }
        final storeMap = value.map(
          (entryKey, entryValue) =>
              MapEntry(entryKey.toString(), entryValue),
        );
        stores[storeName] = CacheStoreConfig.fromMap(
          Map<String, dynamic>.from(storeMap),
          context: 'cache.stores.$storeName',
        );
      });
    }
    return CacheConfig(
      stores: stores,
      defaultStore: defaultValue as String?,
      prefix: prefix,
      keyPrefix: keyPrefix,
      appPrefix: appPrefix,
    );
  }

  @override
  Map<String, dynamic> toMap(CacheConfig value) {
    final result = <String, dynamic>{};
    if (value.defaultStore != null) {
      result['default'] = value.defaultStore;
    }
    if (value.prefix != null) {
      result['prefix'] = value.prefix;
    }
    if (value.keyPrefix != null) {
      result['key_prefix'] = value.keyPrefix;
    }
    if (value.stores.isNotEmpty) {
      final stores = <String, dynamic>{};
      value.stores.forEach((key, store) {
        stores[key] = store.toMap();
      });
      result['stores'] = stores;
    }
    return result;
  }

  // Parsing kept inline to keep the spec reading like a JSON model.
}
