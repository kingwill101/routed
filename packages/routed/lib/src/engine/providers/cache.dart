import 'dart:async';

import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/engine/storage_paths.dart';

/// Provides cache infrastructure and default configuration hooks.
class CacheServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  static final Map<String, Map<String, dynamic> Function(StorageDefaults)>
  _storageDefaultResolvers = {};

  CacheManager? _managedManager;
  bool _ownsManagedManager = false;

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: <ConfigDocEntry>[
      const ConfigDocEntry(
        path: 'cache.default',
        type: 'string',
        description:
            'Name of the cache store to use when none is specified explicitly.',
        defaultValue: 'file',
        metadata: {configDocMetaInheritFromEnv: 'CACHE_STORE'},
      ),
      const ConfigDocEntry(
        path: 'cache.prefix',
        type: 'string',
        description:
            'Prefix prepended to every cache key. Useful when sharing stores.',
        defaultValue: '',
      ),
      const ConfigDocEntry(
        path: 'cache.key_prefix',
        type: 'string',
        description:
            'Optional global prefix injected before the generated store prefix.',
        defaultValue: null,
      ),
      const ConfigDocEntry(
        path: 'cache.stores',
        type: 'map',
        description: 'Configured cache stores keyed by store name.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'cache.stores.*.driver',
        type: 'string',
        description: 'Driver identifier backing the cache store.',
        optionsBuilder: () => CacheManager.registeredDrivers,
      ),
      const ConfigDocEntry(
        path: 'http.features.cache.enabled',
        type: 'bool',
        description: 'Enable cache-related middleware and helpers.',
        defaultValue: true,
      ),
      ...CacheManager.driverDocumentation(pathTemplate: 'cache.stores.*'),
    ],
  );

  @override
  void register(Container container) {
    if (!container.has<Config>()) {
      return;
    }
    if (container.has<CacheManager>()) {
      _managedManager = null;
      _ownsManagedManager = false;
      return;
    }
    final manager = _buildManager(container, container.get<Config>());
    _managedManager = manager;
    container.instance<CacheManager>(manager);
    _ownsManagedManager = true;
  }

  @override
  Future<void> boot(Container container) async {
    EventManager? eventManager;
    if (container.has<EventManager>()) {
      eventManager = await container.make<EventManager>();
      if (_managedManager != null) {
        _managedManager!.attachEventManager(eventManager);
      } else if (container.has<CacheManager>()) {
        final existing = await container.make<CacheManager>();
        existing.attachEventManager(eventManager);
        _managedManager = existing;
        _ownsManagedManager = false;
      }
    }

    if (container.has<Config>()) {
      final config = container.get<Config>();
      final manager =
          _managedManager ??
          (container.has<CacheManager>()
              ? await container.make<CacheManager>()
              : null);
      if (manager != null) {
        _applyCachePrefix(manager, config);
      }
      if (_managedManager != null &&
          _ownsManagedManager &&
          identical(manager, _managedManager)) {
        _managedManager = _applyCacheConfig(
          container,
          config,
          eventManager: eventManager,
        );
      }
    }
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    EventManager? eventManager;
    if (container.has<EventManager>()) {
      eventManager = await container.make<EventManager>();
    }

    if (_ownsManagedManager) {
      _managedManager = _applyCacheConfig(
        container,
        config,
        eventManager: eventManager,
      );
      return;
    }
    if (container.has<CacheManager>()) {
      final manager = await container.make<CacheManager>();
      _applyCachePrefix(manager, config);
    }
  }

  CacheManager _applyCacheConfig(
    Container container,
    Config config, {
    EventManager? eventManager,
  }) {
    final manager = _buildManager(container, config);
    if (eventManager != null) {
      manager.attachEventManager(eventManager);
    }
    _managedManager = manager;
    container.instance<CacheManager>(manager);
    _ownsManagedManager = true;
    return manager;
  }

  CacheManager _buildManager(Container container, Config config) {
    final manager = CacheManager();
    final storageDefaults = container.has<StorageDefaults>()
        ? container.get<StorageDefaults>()
        : null;
    final cacheNode = config.get('cache');
    if (cacheNode != null && cacheNode is! Map) {
      throw ProviderConfigException('cache must be a map');
    }

    final storesMap = _readMap(config.get('cache.stores'), 'cache.stores');

    final defaultNode = config.get('cache.default');
    String? defaultStoreName;
    if (defaultNode != null) {
      if (defaultNode is! String) {
        throw ProviderConfigException('cache.default must be a string');
      }
      final trimmed = defaultNode.trim();
      if (trimmed.isEmpty) {
        throw ProviderConfigException('cache.default must be a string');
      }
      defaultStoreName = trimmed;
    }

    final normalizedStores = <String, Map<String, dynamic>>{};
    storesMap.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        normalizedStores[key] = Map<String, dynamic>.from(value);
      } else if (value is Map) {
        normalizedStores[key] = value.map((k, v) => MapEntry(k.toString(), v));
      } else {
        throw ProviderConfigException('cache.stores.$key must be a map');
      }
    });

    if (normalizedStores.isEmpty) {
      normalizedStores['file'] = <String, dynamic>{'driver': 'file'};
    }

    final ordered = <String>{};
    if (defaultStoreName != null &&
        normalizedStores.containsKey(defaultStoreName)) {
      ordered.add(defaultStoreName);
    }
    ordered.addAll(normalizedStores.keys);

    for (final name in ordered) {
      final storeConfig = normalizedStores[name];
      if (storeConfig != null) {
        final normalized = Map<String, dynamic>.from(storeConfig);
        final driver = normalized['driver']?.toString();
        if (driver == 'file') {
          final pathValue = normalized['path'];
          if (pathValue is String && pathValue.trim().isNotEmpty) {
            normalized['path'] = storageDefaults != null
                ? storageDefaults.resolve(pathValue)
                : normalizeStoragePath(config, pathValue);
          } else {
            normalized['path'] = storageDefaults != null
                ? storageDefaults.frameworkPath('cache')
                : resolveFrameworkStoragePath(config, child: 'cache');
          }
        }
        manager.registerStore(name, normalized);
      }
    }

    _applyCachePrefix(manager, config);
    return manager;
  }

  Map<String, dynamic> _readMap(Object? source, String context) {
    if (source == null) {
      return const {};
    }
    if (source is Map<String, dynamic>) {
      return Map<String, dynamic>.from(source);
    }
    if (source is Map) {
      return source.map((key, value) => MapEntry(key.toString(), value));
    }
    throw ProviderConfigException('$context must be a map');
  }

  void _applyCachePrefix(CacheManager manager, Config config) {
    final prefix = _resolveCachePrefix(config);
    if (prefix != null) {
      manager.setPrefix(prefix);
      return;
    }
    if (manager.prefix.isNotEmpty) {
      manager.setPrefix('');
    }
  }

  String? _resolveCachePrefix(Config config) {
    if (config.has('cache.prefix')) {
      final value = config.get('cache.prefix');
      if (value == null) {
        return '';
      }
      if (value is String) {
        return value;
      }
      throw ProviderConfigException('cache.prefix must be a string');
    }
    if (config.has('cache.key_prefix')) {
      final value = config.get('cache.key_prefix');
      if (value == null) {
        return '';
      }
      if (value is String) {
        return value;
      }
      throw ProviderConfigException('cache.key_prefix must be a string');
    }
    if (config.has('app.cache_prefix')) {
      final value = config.get('app.cache_prefix');
      if (value == null) {
        return '';
      }
      if (value is String) {
        return value;
      }
      throw ProviderConfigException('app.cache_prefix must be a string');
    }
    return null;
  }
}
