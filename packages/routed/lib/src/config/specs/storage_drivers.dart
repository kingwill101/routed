import 'package:file/file.dart' as file;
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

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'root': null,
      'file_system': null,
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) =>
        base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('root'),
        type: 'string',
        description:
            'Filesystem path used as the disk root (defaults to storage/app for the local disk, or storage/<name> for other disks).',
      ),
      ConfigDocEntry(
        path: path('file_system'),
        type: 'FileSystem',
        description:
            'Optional file system override used when operating the local disk.',
      ),
    ];
  }

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
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'driver': 's3',
      'options': const <String, Object?>{},
      'prefix': null,
      'visibility': null,
      'url': null,
      'throw': null,
      'report': null,
      'directory_separator': null,
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) =>
        base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('options.endpoint'),
        type: 'string',
        description:
            'Hostname of the S3-compatible endpoint (e.g. s3.amazonaws.com).',
      ),
      ConfigDocEntry(
        path: path('options.key'),
        type: 'string',
        description: 'Access key for the S3-compatible account.',
      ),
      ConfigDocEntry(
        path: path('options.secret'),
        type: 'string',
        description: 'Secret key for the S3-compatible account.',
      ),
      ConfigDocEntry(
        path: path('options.bucket'),
        type: 'string',
        description: 'Bucket name used for storing files.',
      ),
      ConfigDocEntry(
        path: path('options.region'),
        type: 'string',
        description:
            'Optional region (defaults to us-east-1 for most providers).',
      ),
      ConfigDocEntry(
        path: path('options.use_ssl'),
        type: 'bool',
        description:
            'Enable HTTPS connections to the provider (defaults true).',
      ),
      ConfigDocEntry(
        path: path('prefix'),
        type: 'string',
        description:
            'Optional key prefix applied to all stored objects (no leading slash).',
      ),
      ConfigDocEntry(
        path: path('visibility'),
        type: 'string',
        description: 'Default visibility applied to objects on this disk.',
      ),
      ConfigDocEntry(
        path: path('url'),
        type: 'string',
        description: 'Public base URL used when generating links.',
      ),
      ConfigDocEntry(
        path: path('throw'),
        type: 'bool',
        description: 'Throw exceptions on storage errors when enabled.',
      ),
      ConfigDocEntry(
        path: path('report'),
        type: 'bool',
        description: 'Report storage errors when enabled.',
      ),
      ConfigDocEntry(
        path: path('directory_separator'),
        type: 'string',
        description: 'Directory separator used when joining storage paths.',
      ),
    ];
  }

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
