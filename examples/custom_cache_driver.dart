// ignore_for_file: unnecessary_import

import 'package:routed/routed.dart';
import 'package:server_cache/server_cache.dart';

const String filesystemCacheDriver = 'filesystem';

void registerFilesystemCacheDriver() {
  final manager = CacheManager();
  manager.registerStoreFactory(
    filesystemCacheDriver,
    FilesystemCacheStoreFactory(),
  );
  return;
}

class FilesystemCacheStoreFactory extends StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    final directory = config['cache_dir'] as String;
    throw UnimplementedError(
      'Implement the filesystem cache store for "$directory".',
    );
  }
}

void main() {
  final manager = CacheManager();
  manager.registerStoreFactory(
    filesystemCacheDriver,
    FilesystemCacheStoreFactory(),
  );
  print(
    'Registered $filesystemCacheDriver cache driver: '
    '${manager.storeFactoryDrivers}',
  );
}
