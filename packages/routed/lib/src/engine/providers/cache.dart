import 'dart:async';

import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/config/specs/cache.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/provider/provider.dart';

/// Provides cache infrastructure and default configuration hooks.
class CacheServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  static const CacheConfigSpec spec = CacheConfigSpec();
  CacheManager? _managedManager;
  bool _ownsManagedManager = false;

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: spec.docs(),
    values: spec.defaultsWithRoot(),
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
        _applyCachePrefixFromConfig(manager, config);
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
      _applyCachePrefixFromConfig(manager, config);
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
    final manager = CacheManager(container: container);
    final resolved = spec.resolve(config);
    final ordered = <String>{};
    final defaultStoreName = resolved.defaultStore;
    if (defaultStoreName != null &&
        resolved.stores.containsKey(defaultStoreName)) {
      ordered.add(defaultStoreName);
    }
    ordered.addAll(resolved.stores.keys);

    for (final name in ordered) {
      final storeConfig = resolved.stores[name];
      if (storeConfig != null) {
        manager.registerStore(name, storeConfig.toMap());
      }
    }

    _applyCachePrefix(manager, resolved);
    return manager;
  }

  void _applyCachePrefix(CacheManager manager, CacheConfig config) {
    final prefix = config.resolvePrefix();
    if (prefix != null) {
      manager.setPrefix(prefix);
      return;
    }
    if (manager.prefix.isNotEmpty) {
      manager.setPrefix('');
    }
  }

  void _applyCachePrefixFromConfig(CacheManager manager, Config config) {
    final resolved = spec.resolve(config);
    _applyCachePrefix(manager, resolved);
  }
}
