/// Storage-manager access, typed configuration, and static-file integration for
/// Routed applications.
///
/// Use [RoutedStorageProvider] to register a [StorageManager] and configure
/// local disks. Add [storageMiddleware] when a request context needs an
/// explicitly selected manager, or use the [StorageEngineContext] extension
/// to resolve the manager and disks from a handler.
library;

import 'package:file/file.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/src/static_provider.dart';
import 'package:server_storage/server_storage.dart';

export 'package:server_storage/server_storage.dart';

export 'src/engine_static_file_sink.dart';
export 'src/static_files.dart';
export 'src/static_provider.dart';

/// Adds accessors for the request's configured storage manager and disks.
extension StorageEngineContext on EngineContext {
  /// Returns the storage manager registered in this request's container.
  ///
  /// The manager is normally registered by [RoutedStorageProvider] or
  /// [storageMiddleware]. This getter does not create or configure a manager.
  ///
  /// Throws [StateError] when no [StorageManager] has been registered.
  StorageManager get storageManager {
    if (container.has<StorageManager>()) {
      return container.get<StorageManager>();
    }
    throw StateError('Storage manager not configured');
  }

  /// Returns the named storage disk, or the manager's default disk when [name]
  /// is omitted or empty.
  ///
  /// Throws [StateError] when the selected disk has not been registered.
  StorageDisk storageDisk([String? name]) => storageManager.disk(name);

  /// Returns unified asynchronous storage operations for a named disk.
  ///
  /// The manager's default disk is used when [name] is omitted or empty. This
  /// exposes the `storage_fs` API (`put`, `get`, `exists`, `delete`, streams,
  /// and metadata) without relying on its process-global [Storage] facade.
  Filesystem storage([String? name]) => storageManager.storage(name);

  /// Creates a time-limited download URL through the selected storage disk.
  ///
  /// The manager's default disk is used when [disk] is omitted. Authenticate
  /// and authorize the caller before returning the resulting capability URL.
  Future<String> temporaryStorageUrl(
    String path,
    DateTime expiration, {
    String? disk,
    Map<String, dynamic>? options,
  }) {
    return storageManager.temporaryUrl(
      path,
      expiration,
      disk: disk,
      options: options,
    );
  }

  /// Creates time-limited upload data through the selected storage disk.
  ///
  /// The result contains a `url`, required `headers`, and optional form
  /// `fields`. Authenticate and authorize the caller before returning it.
  Future<Map<String, dynamic>> temporaryStorageUploadUrl(
    String path,
    DateTime expiration, {
    String? disk,
    Map<String, dynamic>? options,
  }) {
    return storageManager.temporaryUploadUrl(
      path,
      expiration,
      disk: disk,
      options: options,
    );
  }

  /// Whether this request has a [StorageManager] in its container.
  bool get hasStorageManager => container.has<StorageManager>();
}

/// Creates middleware that makes [manager] available to request handlers.
///
/// The middleware registers the supplied instance only when the request
/// container does not already contain a [StorageManager]. This makes it safe
/// to compose with [RoutedStorageProvider] and preserves a more specific
/// request binding. It then calls `next` and returns its response; it does not
/// create disks or modify the manager's configuration.
Middleware storageMiddleware(StorageManager manager) {
  return (ctx, next) {
    // ensure request-scoped access falls back to container singleton
    if (!ctx.container.has<StorageManager>()) {
      ctx.container.instance<StorageManager>(manager);
    }
    return next();
  };
}

/// Optional settings for a named local storage disk.
///
/// These settings are consumed by [StorageConfig]. They do not create a disk
/// until [RoutedStorageProvider] boots.
final class LocalStorageDiskConfig {
  /// Creates settings for a local disk.
  ///
  /// When [root] is omitted, the provider derives `storage/app` for the
  /// `local` disk and `storage/<name>` for other disk names. When [fileSystem]
  /// is omitted, the manager's default file system is used when the disk is
  /// created.
  const LocalStorageDiskConfig({this.root, this.fileSystem});

  /// Optional directory used as this disk's root.
  ///
  /// The value must be non-empty when supplied. Relative roots are resolved
  /// by the selected file system when the disk is created.
  final String? root;

  /// Optional file system used by the disk.
  ///
  /// When omitted, [StorageManager.defaultFileSystem] is used.
  final FileSystem? fileSystem;
}

/// Immutable typed configuration for [RoutedStorageProvider].
///
/// With the default constructor, the provider creates one `local` disk rooted
/// at `storage/app` and selects it as the default. Supplying [disks] replaces
/// that generated disk map, so include the [defaultDisk] entry explicitly when
/// providing custom disks.
class StorageConfig implements ValidatableConfiguration {
  /// Creates typed storage configuration with local-disk defaults.
  ///
  /// [defaultDisk] defaults to `local`, [root] defaults to `storage/app`, and
  /// [disks] defaults to a single `local` disk using [root]. If [disks] is
  /// supplied, it is copied into an unmodifiable map and is not merged with
  /// the default disk.
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
  ///
  /// Validation requires this name to be non-empty and present in [disks].
  final String defaultDisk;

  /// Root used by the generated `local` disk.
  ///
  /// The value defaults to `storage/app` and is used only when the `local`
  /// disk does not provide its own [LocalStorageDiskConfig.root].
  final String root;

  /// Named disk definitions copied from the constructor input.
  ///
  /// The map is unmodifiable. Each entry is validated for a non-empty name;
  /// supplied disk roots must also be non-empty.
  final Map<String, LocalStorageDiskConfig> disks;

  /// Records configuration errors in [context].
  ///
  /// Validation runs while typed provider configuration is assembled. It
  /// records all of the following issues instead of throwing immediately:
  /// empty default names or roots, an empty disk map, a missing default disk,
  /// empty disk names, and empty explicitly supplied disk roots. A later
  /// [ConfigValidationException] contains the collected issues.
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

/// Registers storage disks and a [StorageManager] with a Routed app.
///
/// The provider registers [manager] during the provider registration phase.
/// During boot, it applies [configuration] only when no manager was injected
/// into the constructor: existing disks are cleared, configured local disks
/// are created, and [StorageConfig.defaultDisk] is selected. An injected
/// manager is registered as-is and is not cleared or reconfigured.
class RoutedStorageProvider extends ServiceProvider
    with ProvidesTypedConfiguration<StorageConfig> {
  /// Creates a storage provider with local-disk defaults.
  ///
  /// When [configuration] is omitted, [StorageConfig]'s `local` disk rooted at
  /// `storage/app` is used. When [manager] is supplied, that exact manager is
  /// registered and [configuration] is not applied during boot.
  RoutedStorageProvider({StorageConfig? configuration, StorageManager? manager})
    : configuration = configuration ?? StorageConfig(),
      manager = manager ?? StorageManager(),
      _configureManager = manager == null;

  /// Typed storage configuration used when [manager] is not supplied.
  @override
  final StorageConfig configuration;

  /// Storage manager registered with the application container.
  ///
  /// The same instance is made available to the container during [register].
  /// It is rebuilt from [configuration] during [boot] only when it was created
  /// by this provider rather than injected by the caller.
  final StorageManager manager;
  final bool _configureManager;

  /// Registers [manager] in [container] without creating request state.
  @override
  void register(Container container) {
    container.instance<StorageManager>(manager);
  }

  /// Applies typed disk configuration when this provider owns [manager].
  ///
  /// An injected manager is left unchanged. Configuration validation is
  /// expected to have completed before boot; disk-construction failures from
  /// the underlying storage package propagate to the application bootstrap.
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
///
/// Registration targets [ProviderRegistry.instance] and stores factories, not
/// provider instances. Repeated calls are safe: the registry keeps an existing
/// registration for either identifier rather than replacing it. Call this
/// before resolving providers from the registry.
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
