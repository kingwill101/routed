library;

import 'package:routed/providers.dart' show ProviderRegistry;
import 'package:routed/routed.dart';
import 'package:server_storage/server_storage.dart';

export 'package:server_storage/server_storage.dart';
export 'src/engine_static_file_sink.dart';
export 'src/static_files.dart';

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

class RoutedStorageProvider extends ServiceProvider {
  /// Defaults to a [StorageManager] with a local `storage/app` disk.
  RoutedStorageProvider([StorageManager? manager])
      : manager = manager ?? _defaultManager();

  final StorageManager manager;

  static StorageManager _defaultManager() {
    final m = StorageManager();
    m.registerDisk(
      'local',
      LocalStorageDisk(root: 'storage/app'),
    );
    m.setDefault('local');
    return m;
  }

  @override
  void register(Container container) {
    container.singleton<StorageManager>((_) async => manager);
    container.instance<dynamic>(manager);
  }

  @override
  Future<void> boot(Container container) async {}
}

/// Registers `routed.storage` for `http.providers` resolution.
void registerRoutedStorageProviders() {
  ProviderRegistry.instance.register(
    'routed.storage',
    factory: RoutedStorageProvider.new,
    description: 'Storage disks and static file helpers.',
  );
}
