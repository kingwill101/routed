library;

import 'package:file/file.dart';
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

/// A named local storage disk definition.
final class LocalStorageDiskConfig {
  const LocalStorageDiskConfig({this.root, this.fileSystem});

  final String? root;
  final FileSystem? fileSystem;
}

/// Immutable configuration for [RoutedStorageProvider].
class StorageConfig implements ValidatableConfiguration {
  StorageConfig({
    this.defaultDisk = 'local',
    this.root = 'storage/app',
    Map<String, LocalStorageDiskConfig>? disks,
  }) : disks = Map<String, LocalStorageDiskConfig>.unmodifiable(
         disks ??
             <String, LocalStorageDiskConfig>{
               'local': LocalStorageDiskConfig(root: root),
             },
       );

  final String defaultDisk;
  final String root;
  final Map<String, LocalStorageDiskConfig> disks;

  @override
  void validate(ConfigValidationContext context) {
    context.require(
      defaultDisk.trim().isNotEmpty,
      'defaultDisk',
      'default disk name cannot be empty',
    );
    context.require(
      root.trim().isNotEmpty,
      'root',
      'default storage root cannot be empty',
    );
    context.require(
      disks.isNotEmpty,
      'disks',
      'at least one storage disk must be configured',
    );
    context.require(
      disks.containsKey(defaultDisk),
      'defaultDisk',
      'default disk must name a configured disk',
    );
    for (final entry in disks.entries) {
      final name = entry.key;
      final disk = entry.value;
      context.require(
        name.trim().isNotEmpty,
        'disks.$name',
        'disk names cannot be empty',
      );
      if (disk.root != null) {
        context.require(
          disk.root!.trim().isNotEmpty,
          'disks.$name.root',
          'disk roots cannot be empty',
        );
      }
    }
  }
}

class RoutedStorageProvider extends ServiceProvider
    with ProvidesTypedConfiguration<StorageConfig> {
  /// Defaults to a [StorageManager] with a local `storage/app` disk.
  RoutedStorageProvider({StorageConfig? configuration, StorageManager? manager})
    : configuration = configuration ?? StorageConfig(),
      manager = manager ?? StorageManager(),
      _configureManager = manager == null;

  @override
  final StorageConfig configuration;

  final StorageManager manager;
  final bool _configureManager;

  @override
  void register(Container container) {
    container.instance<StorageManager>(manager);
  }

  @override
  Future<void> boot(Container container) async {
    if (_configureManager) {
      _applyConfig(configuration);
    }
  }

  void _applyConfig(StorageConfig config) {
    manager.clear();
    for (final entry in config.disks.entries) {
      final diskConfig = entry.value;
      final root =
          diskConfig.root ??
          (entry.key == 'local' ? config.root : 'storage/${entry.key}');
      manager.registerDisk(
        entry.key,
        LocalStorageDisk(
          root: root,
          fileSystem: diskConfig.fileSystem ?? manager.defaultFileSystem,
        ),
      );
    }

    manager.setDefault(config.defaultDisk);
  }
}

/// Registers storage and static provider factories in the shared registry.
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
