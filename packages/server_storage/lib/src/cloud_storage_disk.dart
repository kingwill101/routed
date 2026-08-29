import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file_cloud/drivers.dart' show Minio, MinioCloudDriver;
import 'package:file_cloud/file_cloud.dart' show CloudFileSystem;
import 'package:server_storage/src/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart'
    show CloudAdapter, DiskConfig, Filesystem;

/// Resolves object keys through an S3-compatible cloud filesystem.
///
/// The adapter owns the cloud connection and filesystem implementation. This
/// wrapper gives it the [StorageDisk] contract so it can be selected by a
/// [StorageManager]. It does not create buckets, upload objects, or close the
/// adapter when the manager is cleared.
class CloudStorageDisk implements AsyncFilesystemStorageDisk {
  /// Creates a disk backed by [adapter].
  ///
  /// [diskName] is descriptive metadata for integrations; it does not alter
  /// key resolution or register the disk with a manager.
  CloudStorageDisk({required this.adapter, this.diskName});

  /// Optional name associated with this disk by an integration.
  final String? diskName;

  /// The underlying cloud adapter for storage operations and advanced setup.
  final CloudAdapter adapter;

  /// Unified Laravel-style storage operations backed by [adapter].
  @override
  CloudAdapter get storage => adapter;

  @override
  file.FileSystem get fileSystem => adapter.fileSystem;

  @override
  String resolve(String path) {
    // Cloud paths are object keys rather than local filesystem paths.
    if (path.isEmpty) {
      return '';
    }

    final pathContext = adapter.fileSystem.path;
    if (pathContext.isAbsolute(path)) {
      throw ArgumentError.value(path, 'path', 'Object keys must be relative.');
    }

    final normalized = pathContext.normalize(path);
    if (normalized.isEmpty || normalized == '.') {
      return '';
    }
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(
        path,
        'path',
        'Object key escapes the configured storage prefix.',
      );
    }
    return normalized;
  }

  /// Prepares the underlying cloud driver when it requires initialization.
  ///
  /// S3 disks only perform a network request here when bucket auto-creation is
  /// enabled. Ordinary S3 disks are ready to use immediately after
  /// construction and this method completes without contacting the service.
  Future<void> ensureReady() => adapter.driver.ensureReady();
}

/// A storage disk backed by an S3-compatible object-storage service.
///
/// The driver works with AWS S3 and compatible services such as Cloudflare R2,
/// DigitalOcean Spaces, and MinIO. [endpoint] accepts either a host (for
/// example, `s3.amazonaws.com`) or an HTTP(S) URL. A URL may include a custom
/// port, which is useful for a local MinIO service.
///
/// Construction does not contact the service. Set [autoCreateBucket] only for
/// services where this process is allowed to create the configured bucket,
/// then call [ensureReady] during application startup.
final class S3StorageDisk extends CloudStorageDisk {
  /// Creates an S3-compatible storage disk.
  ///
  /// [accessKey] and [secretKey] are used only to construct the underlying S3
  /// client; they are not retained in this object's public metadata or in the
  /// adapter's diagnostic configuration. Temporary credentials can include a
  /// [sessionToken].
  ///
  /// For an endpoint without a scheme, HTTPS is used unless [useSsl] is
  /// `false`. When [endpoint] includes a scheme, it is authoritative and a
  /// conflicting [useSsl] value is rejected. Endpoint paths, query strings,
  /// fragments, and embedded user information are rejected.
  ///
  /// [prefix] scopes every object operation to a key prefix. [pathStyle]
  /// controls S3 path-style addressing; when omitted, the underlying client
  /// selects its provider default. [publicUrl] is an optional CDN or public
  /// bucket base URL used by [CloudAdapter.url].
  factory S3StorageDisk({
    required String endpoint,
    required String accessKey,
    required String secretKey,
    required String bucket,
    bool? useSsl,
    String? region,
    String? sessionToken,
    bool? pathStyle,
    String? prefix,
    Uri? publicUrl,
    bool autoCreateBucket = false,
    bool throwOnError = false,
    String? diskName,
  }) {
    final target = _S3Endpoint.parse(endpoint, useSsl: useSsl);
    final normalizedAccessKey = _requireValue(accessKey, 'accessKey');
    final normalizedSecretKey = _requireValue(secretKey, 'secretKey');
    final normalizedBucket = _requireValue(bucket, 'bucket');
    final normalizedRegion = _optionalValue(region);
    final normalizedSessionToken = _optionalValue(sessionToken);
    final normalizedPrefix = _normalizePrefix(prefix);

    final client = Minio(
      endPoint: target.uri.host,
      port: target.uri.hasPort ? target.uri.port : null,
      accessKey: normalizedAccessKey,
      secretKey: normalizedSecretKey,
      useSSL: target.useSsl,
      sessionToken: normalizedSessionToken,
      region: normalizedRegion,
      pathStyle: pathStyle,
    );
    final cloudDriver = MinioCloudDriver(
      client: client,
      bucket: normalizedBucket,
      rootPrefix: normalizedPrefix,
      baseUrl: publicUrl,
      enforcePathStyle: pathStyle ?? false,
      autoCreateBucket: autoCreateBucket,
    );
    final fileSystem = CloudFileSystem(driver: cloudDriver);
    final diagnosticOptions = <String, dynamic>{
      'endpoint': target.uri.toString(),
      'bucket': normalizedBucket,
      'use_ssl': target.useSsl,
      'auto_create_bucket': autoCreateBucket,
    };
    if (normalizedRegion != null) {
      diagnosticOptions['region'] = normalizedRegion;
    }
    if (pathStyle != null) {
      diagnosticOptions['path_style'] = pathStyle;
    }
    final adapter = _PrivateS3CloudAdapter(
      fileSystem: fileSystem,
      config: DiskConfig(
        driver: 's3',
        url: publicUrl?.toString(),
        prefix: normalizedPrefix,
        throw_: throwOnError,
        options: diagnosticOptions,
      ),
    );

    return S3StorageDisk._(
      adapter: adapter,
      endpoint: target.uri,
      bucket: normalizedBucket,
      region: normalizedRegion,
      prefix: normalizedPrefix,
      publicUrl: publicUrl,
      pathStyle: pathStyle,
      autoCreateBucket: autoCreateBucket,
      diskName: diskName,
    );
  }

  S3StorageDisk._({
    required super.adapter,
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.prefix,
    required this.publicUrl,
    required this.pathStyle,
    required this.autoCreateBucket,
    required super.diskName,
  });

  /// Normalized HTTP(S) service endpoint, including a custom port when set.
  final Uri endpoint;

  /// Bucket used for all operations performed by this disk.
  final String bucket;

  /// Region override passed to the S3 client, when configured.
  final String? region;

  /// Object-key prefix that scopes this disk, without leading/trailing slashes.
  final String? prefix;

  /// Optional CDN or public bucket base URL.
  final Uri? publicUrl;

  /// Explicit path-style addressing choice, or `null` for client defaults.
  final bool? pathStyle;

  /// Whether [ensureReady] may create a missing bucket.
  final bool autoCreateBucket;

  /// Whether this disk connects to its service using TLS.
  bool get useSsl => endpoint.scheme == 'https';

  static String _requireValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Value cannot be empty.');
    }
    return normalized;
  }

  static String? _optionalValue(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _normalizePrefix(String? prefix) {
    final value = _optionalValue(prefix);
    if (value == null) {
      return null;
    }

    final segments = value.split('/');
    if (segments.contains('..')) {
      throw ArgumentError.value(
        prefix,
        'prefix',
        'Prefix cannot contain parent path segments.',
      );
    }

    final normalized = segments
        .where((segment) => segment.isNotEmpty && segment != '.')
        .join('/');
    return normalized.isEmpty ? null : normalized;
  }
}

final class _PrivateS3CloudAdapter extends CloudAdapter {
  _PrivateS3CloudAdapter({
    required super.fileSystem,
    required super.config,
  });

  Future<String> Function(
    String path,
    DateTime expiration,
    Map<String, dynamic> options,
  )?
  _temporaryUrlBuilder;
  Future<Map<String, dynamic>> Function(
    String path,
    DateTime expiration,
    Map<String, dynamic> options,
  )?
  _temporaryUploadUrlBuilder;

  @override
  void buildTemporaryUrlsUsing(
    FutureOr<String> Function(
      String path,
      DateTime expiration,
      Map<String, dynamic> options,
    )
    callback,
  ) {
    _temporaryUrlBuilder = (path, expiration, options) async =>
        callback(path, expiration, options);
  }

  @override
  void buildTemporaryUploadUrlsUsing(
    FutureOr<Map<String, dynamic>> Function(
      String path,
      DateTime expiration,
      Map<String, dynamic> options,
    )
    callback,
  ) {
    _temporaryUploadUrlBuilder = (path, expiration, options) async =>
        callback(path, expiration, options);
  }

  @override
  void clearTemporaryUrlCallbacks() {
    _temporaryUrlBuilder = null;
    _temporaryUploadUrlBuilder = null;
  }

  @override
  Future<String> getVisibility(String path) async {
    // S3-compatible ACL support is not available through the current driver.
    // Reporting public here would let routed static mounts expose a private
    // object, so visibility remains private unless an application uses a
    // separate, explicitly public adapter.
    return Filesystem.visibilityPrivate;
  }

  @override
  Future<bool> setVisibility(String path, String visibility) async {
    if (visibility == Filesystem.visibilityPrivate) return true;
    if (config.throw_) {
      throw UnsupportedError(
        'S3 object ACLs are unavailable; issue a temporary signed URL instead.',
      );
    }
    return false;
  }

  @override
  Future<bool> put(
    String path,
    dynamic contents, {
    Map<String, dynamic>? options,
  }) async {
    final visibility = options?['visibility'];
    if (visibility != null && visibility != Filesystem.visibilityPrivate) {
      if (config.throw_) {
        throw UnsupportedError(
          'S3 objects remain private; issue a temporary signed URL instead.',
        );
      }
      return false;
    }
    return super.put(path, contents, options: options);
  }

  @override
  Future<String> getTemporaryUrl(
    String path,
    DateTime expiration, {
    Map<String, dynamic>? options,
  }) async {
    final builder = _temporaryUrlBuilder;
    if (builder != null) {
      return builder(path, expiration, options ?? <String, dynamic>{});
    }
    final url = await driver.presignDownload(
      path,
      expiration.difference(DateTime.now()),
      options: options,
    );
    if (url == null) {
      throw UnsupportedError(
        'Temporary download URLs are not supported by this S3 driver.',
      );
    }
    return url;
  }

  @override
  Future<Map<String, dynamic>> getTemporaryUploadUrl(
    String path,
    DateTime expiration, {
    Map<String, dynamic>? options,
  }) async {
    final builder = _temporaryUploadUrlBuilder;
    if (builder != null) {
      return builder(path, expiration, options ?? <String, dynamic>{});
    }
    final upload = await driver.presignUpload(
      path,
      expiration.difference(DateTime.now()),
      options: options,
    );
    if (upload == null) {
      throw UnsupportedError(
        'Temporary upload URLs are not supported by this S3 driver.',
      );
    }
    return <String, dynamic>{
      'url': upload.url,
      'headers': upload.headers,
      if (upload.fields.isNotEmpty) 'fields': upload.fields,
    };
  }
}

final class _S3Endpoint {
  const _S3Endpoint(this.uri, {required this.useSsl});

  factory _S3Endpoint.parse(String endpoint, {required bool? useSsl}) {
    final raw = endpoint.trim();
    if (raw.isEmpty) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Value cannot be empty.');
    }

    final hasScheme = raw.contains('://');
    final defaultUseSsl = useSsl ?? true;
    final candidate = hasScheme
        ? raw
        : '${defaultUseSsl ? 'https' : 'http'}://$raw';
    final parsed = Uri.tryParse(candidate);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Expected an S3 host or an HTTP(S) URL.',
      );
    }

    final parsedUseSsl = parsed.scheme == 'https';
    if (hasScheme && useSsl != null && useSsl != parsedUseSsl) {
      throw ArgumentError.value(
        useSsl,
        'useSsl',
        'Value conflicts with the endpoint scheme.',
      );
    }
    if (parsed.userInfo.isNotEmpty ||
        (parsed.path.isNotEmpty && parsed.path != '/') ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Endpoint cannot contain user info, a path, query, or fragment.',
      );
    }

    return _S3Endpoint(
      Uri(
        scheme: parsedUseSsl ? 'https' : 'http',
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
      ),
      useSsl: parsedUseSsl,
    );
  }

  final Uri uri;
  final bool useSsl;
}
