// ignore_for_file: unnecessary_import

import 'package:routed/routed.dart';
import 'package:server_cache/server_cache.dart';

const String filesystemCacheDriver = 'filesystem';

void registerFilesystemCacheDriver() {
  final manager = CacheManager();
  manager.registerStoreFactory(
    filesystemCacheDriver,
    FilesystemCacheStoreFactory(),
    const FilesystemCacheConfiguration(cacheDirectory: 'cache'),
  );
}

class FilesystemCacheConfiguration implements StoreConfiguration {
  const FilesystemCacheConfiguration({required this.cacheDirectory});

  final String cacheDirectory;
}

class FilesystemCacheStoreFactory
    implements StoreFactory<FilesystemCacheConfiguration> {
  @override
  Store create(FilesystemCacheConfiguration configuration) {
    final directory = configuration.cacheDirectory;
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
    const FilesystemCacheConfiguration(cacheDirectory: 'cache'),
  );
  print(
    'Registered $filesystemCacheDriver cache driver: '
    '${manager.storeNames}',
  );
}
