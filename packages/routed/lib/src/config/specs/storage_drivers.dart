import 'package:file/file.dart' as file;
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

class StorageDriverSpecContext extends ConfigSpecContext {
  const StorageDriverSpecContext({
    required this.diskName,
    required this.pathBase,
    super.config,
  });

  final String diskName;
  final String pathBase;

  String path(String segment) =>
      pathBase.isEmpty ? segment : '$pathBase.$segment';
}

String _pathFor(ConfigSpecContext? context, String fallbackBase, String segment) {
  final base =
      context is StorageDriverSpecContext ? context.pathBase : fallbackBase;
  return base.isEmpty ? segment : '$base.$segment';
}

class LocalStorageDiskConfig {
  const LocalStorageDiskConfig({required this.root, this.fileSystem});

  final String? root;
  final file.FileSystem? fileSystem;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (root != null) {
      map['root'] = root;
    }
    if (fileSystem != null) {
      map['file_system'] = fileSystem;
    }
    return map;
  }
}

class LocalStorageDiskSpec extends ConfigSpec<LocalStorageDiskConfig> {
  const LocalStorageDiskSpec();

  @override
  String get root => 'storage.disks.*';

  @overridee
  Schema? get schema => ConfigSchema.object(
    title: 'Local Storage Disk',
    description: 'Stores files on the local filesystem.',
    properties: {
      'root': ConfigSchema.stringdescription:
            'Filesystem path used as the disk root (defaults to storage/app for the local disk, or storage/<name> for other disks).',
      ),
          'file_system': ConfigSchema.object(
        description:
            'Optional file system override used when operating the local disk.',
      ),
        },
      );

  @override
  LocalStorageDiskConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final rootValue = parseStringLike(
      map['root'],
      context: _pathFor(context, root, 'root'),
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );

    final fileSystemValue = map['file_system'];
    if (fileSystemValue != null && fileSystemValue is! file.FileSystem) {
      throw ProviderConfigException(
        '${_pathFor(context, root, 'file_system')} must be a FileSystem',
      );
    }

    return LocalStorageDiskConfig(
      root: rootValue,
      fileSystem: fileSystemValue as file.FileSystem?,
    );
  }

  @override
  Map<String, dynamic> toMap(LocalStorageDiskConfig value) => value.toMap();
}

class CloudStorageOptions {
  const CloudStorageOptions({
    required this.endpoint,
    required this.key,
    required this.secret,
    required this.bucket,
    this.region,
    required this.useSsl,
  });

  final String endpoint;
  final String key;
  final String secret;
  final String bucket;
  final String? region;
  final bool useSsl;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'endpoint': endpoint,
      'key': key,
      'secret': secret,
      'bucket': bucket,
      'use_ssl': useSsl,
    };
    if (region != null && region!.isNotEmpty) {
      map['region'] = region;
    }
    return map;
  }
}

class CloudStorageDiskConfig {
  const CloudStorageDiskConfig({
    required this.driver,
    required this.options,
    this.prefix,
    this.visibility,
    this.url,
    this.throwOnError,
    this.report,
    this.directorySeparator,
  });

  final String driver;
  final CloudStorageOptions options;
  final String? prefix;
  final String? visibility;
  final String? url;
  final bool? throwOnError;
  final bool? report;
  final String? directorySeparator;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'driver': driver,
      'options': options.toMap(),
    };
    if (prefix != null && prefix!.isNotEmpty) {
      map['prefix'] = prefix;
    }
    if (visibility != null && visibility!.isNotEmpty) {
      map['visibility'] = visibility;
    }
    if (url != null && url!.isNotEmpty) {
      map['url'] = url;
    }
    if (throwOnError != null) {
      map['throw'] = throwOnError;
    }
    if (report != null) {
      map['report'] = report;
    }
    if (directorySeparator != null && directorySeparator!.isNotEmpty) {
      map['directory_separator'] = directorySeparator;
    }
    return map;
  }
}

class CloudStorageDiskSpec extends ConfigSpec<CloudStorageDiskConfig> {
  const CloudStorageDiskSpec();

  @override
  String get root => 'storage.disks.*';

  @override
  Schema? get schema =>
      ConfigSchema.object(
        title: 'Cloud Storage Disk',
        description: 'Stores files on a cloud provider (S3 compatible).',
        properties: {
          'driver': ConfigSchema.string(
            description: 'Storage driver name.',
            defaultValue: 's3',
          ),
          'options': ConfigSchema.object(
            description: 'S3 connection options.',
            properties: {
              'endpoint': ConfigSchema.string(
                description:
                'Hostname of the S3-compatible endpoint (e.g. s3.amazonaws.com).',
              ),
              'key': ConfigSchema.string(
                description: 'Access key for the S3-compatible account.',
              ),
              'secret': ConfigSchema.string(
                description: 'Secret key for the S3-compatible account.',
              ),
              'bucket': ConfigSchema.string(
                description: 'Bucket name used for storing files.',
              ),
              'region': ConfigSchema.string(
                description:
                'Optional region (defaults to us-east-1 for most providers).',
              ),
              'use_ssl': ConfigSchema.boolean(
                description:
                'Enable HTTPS connections to the provider (defaults true).',
                defaultValue: true, // Note: manual logic used true default if missing
              ),
            },
            required: ['endpoint', 'key', 'secret', 'bucket'],
          ),
          'prefix': ConfigSchema.string(
        description:
            'Optional key prefix applied to all stored objects (no leading slash).',
      ),
          'visibility': ConfigSchema.string(
        description: 'Default visibility applied to objects on this disk.',
      ),
          'url': ConfigSchema.string(
        description: 'Public base URL used when generating links.',
      ),
          'throw': ConfigSchema.boolean(
        description: 'Throw exceptions on storage errors when enabled.',
      ),
          'report': ConfigSchema.boolean(
        description: 'Report storage errors when enabled.',
      ),
          'directory_separator': ConfigSchema.string(
        description: 'Directory separator used when joining storage paths.',
      ),
        },
      );

  @override
  CloudStorageDiskConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final driverRaw = parseStringLike(
      map['driver'],
      context: _pathFor(context, root, 'driver'),
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final driver = (driverRaw == null || driverRaw.isEmpty)
        ? 's3'
        : driverRaw.toLowerCase();

    final optionsRaw = map['options'];
    if (optionsRaw == null) {
      throw ProviderConfigException(
        '${_pathFor(context, root, 'options')} is required for cloud disks',
      );
    }
    final options = stringKeyedMap(
      optionsRaw as Object,
      _pathFor(context, root, 'options'),
    );

    final endpoint = parseStringLike(
      options['endpoint'],
      context: _pathFor(context, root, 'options.endpoint'),
      coerceNonString: true,
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final key = parseStringLike(
      options['key'],
      context: _pathFor(context, root, 'options.key'),
      coerceNonString: true,
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final secret = parseStringLike(
      options['secret'],
      context: _pathFor(context, root, 'options.secret'),
      coerceNonString: true,
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final bucket = parseStringLike(
      options['bucket'],
      context: _pathFor(context, root, 'options.bucket'),
      coerceNonString: true,
      allowEmpty: true,
      throwOnInvalid: true,
    );

    if (endpoint == null || endpoint.isEmpty) {
      throw ProviderConfigException(
        '${_pathFor(context, root, 'options.endpoint')} is required',
      );
    }
    if (key == null || key.isEmpty) {
      throw ProviderConfigException(
        '${_pathFor(context, root, 'options.key')} is required',
      );
    }
    if (secret == null || secret.isEmpty) {
      throw ProviderConfigException(
        '${_pathFor(context, root, 'options.secret')} is required',
      );
    }
    if (bucket == null || bucket.isEmpty) {
      throw ProviderConfigException(
        '${_pathFor(context, root, 'options.bucket')} is required',
      );
    }

    final useSsl =
        parseBoolLike(
          options['use_ssl'],
          context: _pathFor(context, root, 'options.use_ssl'),
          throwOnInvalid: false,
        ) ??
        true;
    final region = parseStringLike(
      options['region'],
      context: _pathFor(context, root, 'options.region'),
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );

    final prefix = parseStringLike(
      map['prefix'],
      context: _pathFor(context, root, 'prefix'),
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final visibility = parseStringLike(
      map['visibility'],
      context: _pathFor(context, root, 'visibility'),
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final url = parseStringLike(
      map['url'],
      context: _pathFor(context, root, 'url'),
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final throwOnError = parseBoolLike(
      map['throw'],
      context: _pathFor(context, root, 'throw'),
      throwOnInvalid: false,
    );
    final report = parseBoolLike(
      map['report'],
      context: _pathFor(context, root, 'report'),
      throwOnInvalid: false,
    );
    final directorySeparator = parseStringLike(
      map['directory_separator'],
      context: _pathFor(context, root, 'directory_separator'),
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );

    return CloudStorageDiskConfig(
      driver: driver,
      options: CloudStorageOptions(
        endpoint: endpoint,
        key: key,
        secret: secret,
        bucket: bucket,
        region: region,
        useSsl: useSsl,
      ),
      prefix: prefix,
      visibility: visibility,
      url: url,
      throwOnError: throwOnError,
      report: report,
      directorySeparator: directorySeparator,
    );
  }

  @override
  Map<String, dynamic> toMap(CloudStorageDiskConfig value) => value.toMap();
}
