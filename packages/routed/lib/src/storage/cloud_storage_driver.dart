import 'package:file/file.dart' as file;
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart';

/// Storage disk backed by an S3-compatible cloud filesystem.
class CloudStorageDisk implements StorageDisk {
  CloudStorageDisk({required CloudAdapter adapter, this.diskName})
    : _adapter = adapter;

  final CloudAdapter _adapter;

  /// Name associated with this disk inside the manager.
  final String? diskName;

  /// Exposes the underlying cloud adapter for advanced integrations.
  CloudAdapter get adapter => _adapter;

  @override
  file.FileSystem get fileSystem => _adapter.fileSystem;

  @override
  String resolve(String path) {
    final normalized = adapter.fileSystem.path.normalize(path);
    if (normalized.isEmpty || normalized == '.') {
      return '';
    }
    return normalized.startsWith('/') ? normalized.substring(1) : normalized;
  }
}

/// Builder responsible for configuring cloud-backed storage disks.
class CloudStorageDriver {
  const CloudStorageDriver();

  StorageDisk build(StorageDriverContext context) {
    final diskConfig = _diskConfigFor(context);
    final adapter = CloudAdapter.fromConfig(
      diskConfig,
    ).diskName(context.diskName);
    return CloudStorageDisk(adapter: adapter, diskName: context.diskName);
  }

  List<ConfigDocEntry> documentation(StorageDriverDocContext context) {
    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: context.path('options.endpoint'),
        type: 'string',
        description:
            'Hostname of the S3-compatible endpoint (e.g. s3.amazonaws.com).',
      ),
      ConfigDocEntry(
        path: context.path('options.key'),
        type: 'string',
        description: 'Access key for the S3-compatible account.',
      ),
      ConfigDocEntry(
        path: context.path('options.secret'),
        type: 'string',
        description: 'Secret key for the S3-compatible account.',
      ),
      ConfigDocEntry(
        path: context.path('options.bucket'),
        type: 'string',
        description: 'Bucket name used for storing files.',
      ),
      ConfigDocEntry(
        path: context.path('options.region'),
        type: 'string',
        description:
            'Optional region (defaults to us-east-1 for most providers).',
      ),
      ConfigDocEntry(
        path: context.path('options.use_ssl'),
        type: 'bool',
        description:
            'Enable HTTPS connections to the provider (defaults true).',
      ),
      ConfigDocEntry(
        path: context.path('prefix'),
        type: 'string',
        description:
            'Optional key prefix applied to all stored objects (no leading slash).',
      ),
    ];
  }

  DiskConfig _diskConfigFor(StorageDriverContext context) {
    final configuration = stringKeyedMap(
      context.configuration,
      'storage.disks.${context.diskName}',
    );
    final optionsNode = configuration['options'];
    if (optionsNode == null) {
      throw ProviderConfigException(
        'storage.disks.${context.diskName}.options is required for cloud disks',
      );
    }
    final options = stringKeyedMap(
      optionsNode as Object,
      'storage.disks.${context.diskName}.options',
    );

    final endpoint = parseStringLike(
      options['endpoint'],
      context: 'storage.disks.${context.diskName}.options.endpoint',
      coerceNonString: true,
    );
    final key = parseStringLike(
      options['key'],
      context: 'storage.disks.${context.diskName}.options.key',
      coerceNonString: true,
    );
    final secret = parseStringLike(
      options['secret'],
      context: 'storage.disks.${context.diskName}.options.secret',
      coerceNonString: true,
    );
    final bucket = parseStringLike(
      options['bucket'],
      context: 'storage.disks.${context.diskName}.options.bucket',
      coerceNonString: true,
    );

    if (endpoint == null || endpoint.isEmpty) {
      throw ProviderConfigException(
        'storage.disks.${context.diskName}.options.endpoint is required',
      );
    }
    if (key == null || key.isEmpty) {
      throw ProviderConfigException(
        'storage.disks.${context.diskName}.options.key is required',
      );
    }
    if (secret == null || secret.isEmpty) {
      throw ProviderConfigException(
        'storage.disks.${context.diskName}.options.secret is required',
      );
    }
    if (bucket == null || bucket.isEmpty) {
      throw ProviderConfigException(
        'storage.disks.${context.diskName}.options.bucket is required',
      );
    }

    final useSsl =
        parseBoolLike(
          options['use_ssl'],
          context: 'storage.disks.${context.diskName}.options.use_ssl',
          throwOnInvalid: false,
        ) ??
        true;
    final region = parseStringLike(
      options['region'],
      context: 'storage.disks.${context.diskName}.options.region',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );

    final sanitizedOptions = Map<String, dynamic>.from(options)
      ..['endpoint'] = endpoint
      ..['key'] = key
      ..['secret'] = secret
      ..['bucket'] = bucket
      ..['use_ssl'] = useSsl
      ..removeWhere((_, value) => value == null);

    if (region != null && region.isNotEmpty) {
      sanitizedOptions['region'] = region;
    }

    final prefix = parseStringLike(
      configuration['prefix'],
      context: 'storage.disks.${context.diskName}.prefix',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );

    final diskConfigMap = <String, dynamic>{
      'driver': configuration['driver'] ?? 's3',
      'options': sanitizedOptions,
      if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
      if (configuration.containsKey('throw')) 'throw': configuration['throw'],
      if (configuration.containsKey('visibility'))
        'visibility': configuration['visibility'],
      if (configuration.containsKey('url')) 'url': configuration['url'],
      if (configuration.containsKey('directory_separator'))
        'directory_separator': configuration['directory_separator'],
    };

    return DiskConfig.fromMap(diskConfigMap);
  }
}

const CloudStorageDriver cloudStorageDriver = CloudStorageDriver();
