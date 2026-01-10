import 'package:routed/drivers.dart' as drivers;
import 'package:routed/routed.dart' as routed;

const String filesystemCacheDriver = 'filesystem';

void registerFilesystemCacheDriver() {
  routed.CacheManager.registerDriver(
    filesystemCacheDriver,
    () => FilesystemCacheStoreFactory(),
    configBuilder: (drivers.DriverConfigContext context) {
      final config = Map<String, dynamic>.from(context.userConfig);
      config['cache_dir'] ??=
          context.get<routed.StorageDefaults>()?.frameworkPath(
            'cache/filesystem',
          ) ??
          'storage/framework/cache/filesystem';
      return config;
    },
    validator: (config, driver) {
      final directory = config['cache_dir'];
      if (directory is! String || directory.trim().isEmpty) {
        throw drivers.ConfigurationException(
          'Cache driver "$driver" requires a non-empty `cache_dir` value.',
        );
      }
    },
    documentation: (drivers.CacheDriverDocContext ctx) =>
        <routed.ConfigDocEntry>[
          routed.ConfigDocEntry(
            path: ctx.path('cache_dir'),
            type: 'string',
            description: 'Directory used to persist filesystem cache entries.',
            metadata: const {
              'default_note': 'Computed from StorageDefaults when omitted.',
              'validation': 'Must point to a writable directory.',
            },
          ),
        ],
  );
}

class FilesystemCacheStoreFactory extends routed.StoreFactory {
  @override
  drivers.CacheStore create(Map<String, dynamic> config) {
    final directory = config['cache_dir'] as String;
    throw UnimplementedError(
      'Implement the filesystem cache store for "$directory".',
    );
  }
}

void main() {
  registerFilesystemCacheDriver();
  print('Registered $filesystemCacheDriver cache driver');
}
