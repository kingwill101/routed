/// Routed integration for storage disks and declarative static files.
library;

import 'package:file/file.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/src/static_provider.dart';
import 'package:server_storage/server_storage.dart';

export 'package:server_storage/server_storage.dart';

export 'src/engine_static_file_sink.dart';
export 'src/static_files.dart';
export 'src/static_provider.dart';

/// Adds storage-manager accessors to a Routed request context.
extension StorageEngineContext on EngineContext {
  /// Returns the storage manager registered for this request.
  ///
  /// Throws [StateError] when the storage provider has not been configured.
  StorageManager get storageManager {
    if (container.has<StorageManager>()) {
      return container.get<StorageManager>();
    }
    throw StateError('Storage manager not configured');
  }

  /// Returns the named storage disk, or the manager's default disk.
  StorageDisk storageDisk([String? name]) => storageManager.disk(name);

  /// Whether a [StorageManager] is registered for this request.
  bool get hasStorageManager => container.has<StorageManager>();
}

/// Creates middleware that makes [manager] available to request handlers.
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
  /// Creates a local disk definition.
  ///
  /// [root] overrides the storage configuration root for this disk. When
  /// [fileSystem] is omitted, the storage manager's default file system is
  /// used.
  const LocalStorageDiskConfig({this.root, this.fileSystem});

  /// Optional directory used as the disk root.
  final String? root;

  /// Optional file system used by the disk.
  final FileSystem? fileSystem;
}

/// Immutable configuration for [RoutedStorageProvider].
class StorageConfig implements ValidatableConfiguration {
  /// Creates typed storage configuration.
  ///
  /// If [disks] is omitted, a `local` disk rooted at [root] is created.
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

  /// Name of the disk used when no disk is specified.
  final String defaultDisk;

  /// Root used by the default local disk.
  final String root;

  /// Named local disk definitions.
  final Map<String, LocalStorageDiskConfig> disks;

  @override
  void validate(ConfigValidationContext context) {
    context
      ..require(
        defaultDisk.trim().isNotEmpty,
        'defaultDisk',
        'default disk name cannot be empty',
      )
      ..require(
        root.trim().isNotEmpty,
        'root',
        'default storage root cannot be empty',
      )
      ..require(
        disks.isNotEmpty,
        'disks',
        'at least one storage disk must be configured',
      )
      ..require(
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

/// Registers storage disks and their [StorageManager] with a Routed app.
class RoutedStorageProvider extends ServiceProvider
    with ProvidesTypedConfiguration<StorageConfig> {
  /// Defaults to a [StorageManager] with a local `storage/app` disk.
  RoutedStorageProvider({StorageConfig? configuration, StorageManager? manager})
    : configuration = configuration ?? StorageConfig(),
      manager = manager ?? StorageManager(),
      _configureManager = manager == null;

  /// Typed storage configuration used when [manager] is not supplied.
  @override
  final StorageConfig configuration;

  /// Storage manager registered with the application container.
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
