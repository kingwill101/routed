import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
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
    final driverValue = parseStringLike(
      map['driver'],
      context: '$context.driver',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final options = Map<String, dynamic>.from(map)..remove('driver');
    return CacheStoreConfig(driver: driverValue, options: options);
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
  Schema? get schema => ConfigSchema.object(
    title: 'Cache Configuration',
    description: 'Configuration for caching stores and default settings.',
    properties: {
      'default': ConfigSchema.string(
        description:
            'Name of the cache store to use when none is specified explicitly.',
        defaultValue: 'file',
      ).withMetadata({configDocMetaInheritFromEnv: 'CACHE_STORE'}),
      'prefix': ConfigSchema.string(
        description: 'Prefix prepended to every cache key.',
        defaultValue: '',
      ),
      'key_prefix': ConfigSchema.string(
        description:
            'Optional global prefix injected before the generated store prefix.',
      ),
      'stores':
          ConfigSchema.object(
            description: 'Configured cache stores keyed by store name.',
            additionalProperties: true, // Stores are dynamic
            // Provide default value for documentation
          ).withDefault({
            'array': {'driver': 'array'},
            'file': {'driver': 'file', 'path': 'storage/framework/cache'},
          }),
    },
  );

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return [
      ...super.docs(pathBase: base, context: context),
      ...CacheManager.driverDocumentation(pathBase: path('stores.*')),
    ];
  }

  @override
  CacheConfig fromMap(Map<String, dynamic> map, {ConfigSpecContext? context}) {
    final defaultValue = parseStringLike(
      map['default'],
      context: 'cache.default',
      allowEmpty: true,
      throwOnInvalid: true,
    );

    String? prefix;
    final config = context?.config;
    final hasPrefix = config?.has('cache.prefix') ?? map.containsKey('prefix');
    if (hasPrefix) {
      final value = config != null
          ? config.get<Object?>('cache.prefix')
          : map['prefix'];
      if (value == null) {
        prefix = '';
      } else {
        prefix =
            parseStringLike(
              value,
              context: 'cache.prefix',
              allowEmpty: true,
              throwOnInvalid: true,
            ) ??
            '';
      }
    }

    String? keyPrefix;
    final hasKeyPrefix =
        config?.has('cache.key_prefix') ?? map.containsKey('key_prefix');
    if (hasKeyPrefix) {
      final value = config != null
          ? config.get<Object?>('cache.key_prefix')
          : map['key_prefix'];
      if (value == null) {
        keyPrefix = '';
      } else {
        keyPrefix =
            parseStringLike(
              value,
              context: 'cache.key_prefix',
              allowEmpty: true,
              throwOnInvalid: true,
            ) ??
            '';
      }
    }

    String? appPrefix;
    if (config != null && config.has('app.cache_prefix')) {
      final value = config.get<Object?>('app.cache_prefix');
      if (value == null) {
        appPrefix = '';
      } else {
        appPrefix =
            parseStringLike(
              value,
              context: 'app.cache_prefix',
              allowEmpty: true,
              throwOnInvalid: true,
            ) ??
            '';
      }
    }

    final stores = <String, CacheStoreConfig>{};
    final rawStores = map['stores'];
    if (rawStores != null) {
      final storeEntries = parseNestedMap(
        rawStores,
        context: 'cache.stores',
        throwOnInvalid: true,
        allowNullEntries: false,
      );
      storeEntries.forEach((storeName, storeMap) {
        stores[storeName] = CacheStoreConfig.fromMap(
          Map<String, dynamic>.from(storeMap),
          context: 'cache.stores.$storeName',
        );
      });
    }
    return CacheConfig(
      stores: stores,
      defaultStore: defaultValue,
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
