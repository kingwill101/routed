library;

import 'package:routed_core/providers.dart' show ProviderRegistry;
import 'package:routed_core/routed_core.dart';
import 'package:server_storage/server_storage.dart';

import 'src/static_provider.dart';

export 'package:server_storage/server_storage.dart';
export 'src/engine_static_file_sink.dart';
export 'src/static_files.dart';
export 'src/static_provider.dart';

extension StorageEngineContext on EngineContext {
  StorageManager get storageManager {
    if (container.has<StorageManager>()) {
      return container.get<StorageManager>();
    }
    if (container.has<dynamic>()) {
      final dynamic m = container.get<dynamic>();
      if (m is StorageManager) return m;
    }
    throw StateError('Storage manager not configured');
  }

  StorageDisk storageDisk([String? name]) => storageManager.disk(name);
  bool get hasStorageManager => container.has<StorageManager>();
}

Middleware storageMiddleware(StorageManager manager) {
  return (ctx, next) {
    // ensure request-scoped access falls back to container singleton
    if (!ctx.container.has<StorageManager>()) {
      ctx.container.instance<StorageManager>(manager);
    }
    return next();
  };
}

class RoutedStorageProvider extends ServiceProvider with ProvidesDefaultConfig {
  /// Defaults to a [StorageManager] with a local `storage/app` disk.
  RoutedStorageProvider([StorageManager? manager])
    : manager = manager ?? _defaultManager(),
      _configureManager = manager == null;

  final StorageManager manager;
  final bool _configureManager;

  static StorageManager _defaultManager() {
    final m = StorageManager();
    m.registerDisk('local', LocalStorageDisk(root: 'storage/app'));
    m.setDefault('local');
    return m;
  }

  @override
  void register(Container container) {
    container.singleton<StorageManager>((_) async => manager);
    container.instance<dynamic>(manager);
  }

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    values: {
      'storage': {
        'default': 'local',
        'root': 'storage/app',
        'disks': {
          'local': {'driver': 'local', 'root': 'storage/app'},
        },
      },
    },
    docs: const [
      ConfigDocEntry(
        path: 'storage.default',
        type: 'string',
        description: 'Default storage disk name.',
      ),
      ConfigDocEntry(
        path: 'storage.disks',
        type: 'map',
        description: 'Named storage disk definitions.',
      ),
      ConfigDocEntry(
        path: 'storage.root',
        type: 'string',
        description: 'Root for the default local disk.',
      ),
    ],
  );

  @override
  Future<void> boot(Container container) async {
    if (container.has<Config>()) {
      _applyConfig(container.get<Config>());
    }
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _applyConfig(config);
  }

  void _applyConfig(Config config) {
    if (!_configureManager) return;

    final disks = parseNestedMap(
      config.get<Object?>('storage.disks'),
      context: 'storage.disks',
    );
    if (disks.isEmpty) {
      manager.clear();
      manager.registerDisk(
        'local',
        LocalStorageDisk(
          root: config.getString('storage.root', defaultValue: 'storage/app'),
          fileSystem: manager.defaultFileSystem,
        ),
      );
    } else {
      manager.clear();
      for (final entry in disks.entries) {
        final driver = parseStringLike(
          entry.value['driver'],
          context: 'storage.disks.${entry.key}.driver',
        );
        if (driver != null && driver.toLowerCase() != 'local') {
          throw ProviderConfigException(
            'storage.disks.${entry.key}.driver only supports local disks '
            'until a storage driver is registered',
          );
        }
        final root =
            parseStringLike(
              entry.value['root'],
              context: 'storage.disks.${entry.key}.root',
              allowEmpty: false,
            ) ??
            (entry.key == 'local'
                ? config.getString('storage.root', defaultValue: 'storage/app')
                : 'storage/${entry.key}');
        manager.registerDisk(
          entry.key,
          LocalStorageDisk(root: root, fileSystem: manager.defaultFileSystem),
        );
      }
    }

    final defaultDisk = parseStringLike(
      config.get<Object?>('storage.default'),
      context: 'storage.default',
    );
    if (defaultDisk != null) {
      manager.setDefault(defaultDisk);
    }
  }
}

/// Registers `routed.storage` for `http.providers` resolution.
void registerRoutedStorageProviders() {
  ProviderRegistry.instance.register(
    'routed.storage',
    factory: RoutedStorageProvider.new,
    description: 'Storage disks and static file helpers.',
  );
  ProviderRegistry.instance.register(
    'routed.static',
    factory: RoutedStaticProvider.new,
    description: 'Declarative static mounts backed by storage disks.',
  );
}
