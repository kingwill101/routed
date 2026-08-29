import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:storage_fs/storage_fs.dart' show Filesystem;

import 'cloudflare_types.dart';

/// A `storage_fs` filesystem backed by a native Cloudflare R2 binding.
///
/// Unlike an S3 client, this adapter uses the [CloudflareR2Bucket] injected by
/// the Workers runtime and therefore needs no account ID or access-key pair.
/// Configure the binding in Wrangler, obtain it from
/// `environment.r2('FILES')`, and register this filesystem with the
/// application storage manager.
///
/// Object keys are scoped beneath [prefix]. Absolute paths and relative paths
/// that escape that prefix are rejected before the binding is called.
final class CloudflareR2Filesystem implements Filesystem {
  /// Creates a filesystem backed by [bucket].
  ///
  /// [prefix] is an optional object-key prefix without special R2 semantics;
  /// it is normalized to slash-separated relative segments. When [readOnly]
  /// is true, write operations return `false`, or throw when [throwOnError] is
  /// also true.
  CloudflareR2Filesystem({
    required this.bucket,
    String? prefix,
    this.readOnly = false,
    this.throwOnError = false,
  }) : prefix = _normalizePrefix(prefix);

  /// The native R2 bucket binding used by this filesystem.
  final CloudflareR2Bucket bucket;

  /// The normalized object-key prefix, or `null` for the bucket root.
  final String? prefix;

  /// Whether mutating operations are disabled.
  final bool readOnly;

  /// Whether operation failures are rethrown instead of converted to the
  /// fallback values used by `storage_fs`.
  final bool throwOnError;

  /// Normalizes an application-relative object key.
  ///
  /// The returned key does not include [prefix].
  String resolve(String value) {
    if (value.isEmpty) return '';
    if (path.posix.isAbsolute(value)) {
      throw ArgumentError.value(value, 'path', 'R2 keys must be relative.');
    }
    final normalized = path.posix.normalize(value);
    if (normalized == '.') return '';
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(
        value,
        'path',
        'R2 key escapes the configured storage prefix.',
      );
    }
    return normalized;
  }

  @override
  Future<bool> exists(String path) {
    return _attempt(
      false,
      () async => await bucket.head(_objectKey(path)) != null,
    );
  }

  @override
  Future<bool> missing(String path) async => !(await exists(path));

  @override
  Future<String?> get(String path) {
    return _attempt<String?>(null, () async {
      final object = await bucket.get(_objectKey(path));
      return object?.readAsString();
    });
  }

  @override
  Stream<List<int>> readStream(String path) => _readStream(path);

  Stream<List<int>> _readStream(String path) async* {
    try {
      final object = await bucket.get(_objectKey(path));
      final body = object?.body;
      if (body != null) yield* body;
    } catch (error, stackTrace) {
      if (throwOnError) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  @override
  Future<bool> put(
    String path,
    dynamic contents, {
    Map<String, dynamic>? options,
  }) {
    return _write(() async {
      final value = await _uploadValue(contents);
      final object = await bucket.put(
        _objectKey(path),
        value,
        options: _putOptions(options),
      );
      return object != null;
    });
  }

  @override
  Future<bool> writeStream(
    String path,
    Stream<List<int>> resource, {
    Map<String, dynamic>? options,
  }) {
    return put(path, resource, options: options);
  }

  @override
  Future<String> getVisibility(String path) async {
    // R2 public access is configured at the bucket/custom-domain boundary;
    // there is no per-object ACL in the Workers binding API.
    return Filesystem.visibilityPrivate;
  }

  @override
  Future<bool> setVisibility(String path, String visibility) {
    return _write(() async {
      _objectKey(path);
      if (visibility == Filesystem.visibilityPrivate) return true;
      throw UnsupportedError(
        'Cloudflare R2 visibility is configured per bucket, not per object.',
      );
    });
  }

  @override
  Future<bool> prepend(
    String path,
    String data, {
    String separator = '\n',
  }) async {
    final read = await _readTextForMutation(path);
    if (!read.success) return false;
    final existing = read.contents;
    return put(path, existing == null ? data : '$data$separator$existing');
  }

  @override
  Future<bool> append(
    String path,
    String data, {
    String separator = '\n',
  }) async {
    final read = await _readTextForMutation(path);
    if (!read.success) return false;
    final existing = read.contents;
    return put(path, existing == null ? data : '$existing$separator$data');
  }

  @override
  Future<bool> delete(dynamic paths) {
    return _write(() async {
      final keys = switch (paths) {
        String value => <String>[_objectKey(value)],
        Iterable<String> values =>
          values.map(_objectKey).toList(growable: false),
        _ => throw ArgumentError.value(
          paths,
          'paths',
          'Expected a String or Iterable<String>.',
        ),
      };
      if (keys.isEmpty) return true;
      await _deleteKeys(keys);
      return true;
    });
  }

  @override
  Future<bool> copy(String from, String to) {
    return _write(() async {
      final source = await bucket.get(_objectKey(from));
      if (source == null) return false;

      // The storage_fs contract does not carry a stream length. Buffering here
      // gives R2 a fixed-size upload and avoids an unknown-length Worker stream.
      final bytes = await source.readAsBytes();
      final copied = await bucket.put(
        _objectKey(to),
        bytes,
        options: CloudflareR2PutOptions(
          httpMetadata: source.httpMetadata,
          customMetadata: source.customMetadata,
        ),
      );
      return copied != null;
    });
  }

  @override
  Future<bool> move(String from, String to) async {
    if (!await copy(from, to)) return false;
    return delete(from);
  }

  @override
  Future<int> size(String path) {
    return _attempt(
      0,
      () async => (await bucket.head(_objectKey(path)))?.size ?? 0,
    );
  }

  @override
  Future<String?> checksum(String path, {String algorithm = 'md5'}) {
    return _attempt<String?>(null, () async {
      final object = await bucket.head(_objectKey(path));
      if (object == null) return null;
      final normalized = algorithm.toLowerCase().replaceAll('-', '');
      final checksum = object.checksums[normalized];
      if (checksum != null) return checksum;
      return normalized == 'md5' ? object.etag : null;
    });
  }

  @override
  Future<String?> mimeType(String path) {
    return _attempt<String?>(null, () async {
      final metadata = (await bucket.head(_objectKey(path)))?.httpMetadata;
      return metadata?['contentType'] ?? metadata?['content-type'];
    });
  }

  @override
  Future<DateTime> lastModified(String path) {
    return _attempt(DateTime.now(), () async {
      return (await bucket.head(_objectKey(path)))?.uploaded ?? DateTime.now();
    });
  }

  @override
  Future<List<String>> files([
    String? directory,
    bool recursive = false,
  ]) async {
    final listing = await _list(
      prefix: _directoryKey(directory ?? ''),
      delimiter: recursive ? null : '/',
    );
    return listing.objects
        .map((object) => _relativeKey(object.key))
        .where((key) => key.isNotEmpty && !key.endsWith('/'))
        .toList(growable: false);
  }

  @override
  Future<List<String>> allFiles([String? directory]) {
    return files(directory, true);
  }

  @override
  Future<List<String>> directories([
    String? directory,
    bool recursive = false,
  ]) async {
    final listing = await _list(
      prefix: _directoryKey(directory ?? ''),
      delimiter: recursive ? null : '/',
    );
    if (!recursive) {
      final directories = listing.delimitedPrefixes
          .map(_relativeKey)
          .map(_trimTrailingSlash)
          .where((key) => key.isNotEmpty)
          .toList(growable: false);
      directories.sort();
      return directories;
    }

    final result = <String>{};
    final requestedDirectory = resolve(directory ?? '');
    for (final object in listing.objects) {
      final relative = _trimTrailingSlash(_relativeKey(object.key));
      if (relative.isEmpty) continue;
      final segments = relative.split('/');
      final directoryCount = object.key.endsWith('/')
          ? segments.length
          : segments.length - 1;
      for (var index = 1; index <= directoryCount; index++) {
        final candidate = segments.take(index).join('/');
        if (candidate != requestedDirectory) result.add(candidate);
      }
    }
    final sorted = result.toList()..sort();
    return sorted;
  }

  @override
  Future<List<String>> allDirectories([String? directory]) {
    return directories(directory, true);
  }

  @override
  Future<bool> makeDirectory(String path) {
    return _write(() async {
      if (resolve(path).isEmpty) return true;
      final key = _directoryKey(path);
      final object = await bucket.put(key, Uint8List(0));
      return object != null;
    });
  }

  @override
  Future<bool> deleteDirectory(String directory) {
    return _write(() async {
      final listing = await _list(
        prefix: _directoryKey(directory),
        suppressErrors: false,
      );
      final keys = listing.objects.map((object) => object.key).toList();
      await _deleteKeys(keys);
      return true;
    });
  }

  Future<void> _deleteKeys(List<String> keys) async {
    for (var offset = 0; offset < keys.length; offset += _maximumDeleteKeys) {
      final end = offset + _maximumDeleteKeys < keys.length
          ? offset + _maximumDeleteKeys
          : keys.length;
      final batch = keys.sublist(offset, end);
      await bucket.delete(batch.length == 1 ? batch.single : batch);
    }
  }

  Future<T> _attempt<T>(T fallback, Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (_) {
      if (throwOnError) rethrow;
      return fallback;
    }
  }

  Future<bool> _write(Future<bool> Function() operation) async {
    if (readOnly) {
      if (throwOnError) {
        throw StateError('Cloudflare R2 filesystem is read-only.');
      }
      return false;
    }
    return _attempt(false, operation);
  }

  Future<({bool success, String? contents})> _readTextForMutation(
    String path,
  ) async {
    try {
      final object = await bucket.get(_objectKey(path));
      return (
        success: true,
        contents: object == null ? null : await object.readAsString(),
      );
    } catch (error, stackTrace) {
      if (throwOnError) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      return (success: false, contents: null);
    }
  }

  Future<Object> _uploadValue(dynamic contents) async {
    if (contents is String || contents is Uint8List) return contents as Object;
    if (contents is List<int>) return Uint8List.fromList(contents);
    if (contents is Stream<List<int>>) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in contents) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
    throw ArgumentError.value(
      contents,
      'contents',
      'Expected a String, List<int>, Uint8List, or Stream<List<int>>.',
    );
  }

  CloudflareR2PutOptions _putOptions(Map<String, dynamic>? options) {
    final values = options ?? const <String, dynamic>{};
    final visibility = values['visibility'];
    if (visibility != null && visibility != Filesystem.visibilityPrivate) {
      throw UnsupportedError(
        'Cloudflare R2 objects remain private; issue a signed URL for '
        'temporary public access.',
      );
    }
    final httpMetadata = _stringMap(
      values['httpMetadata'] ?? values['http_metadata'],
    );
    final customMetadata = _stringMap(
      values['customMetadata'] ?? values['custom_metadata'],
    );
    final contentType = values['contentType'] ?? values['content_type'];
    if (contentType is String && contentType.isNotEmpty) {
      httpMetadata['contentType'] = contentType;
    }
    return CloudflareR2PutOptions(
      httpMetadata: httpMetadata,
      customMetadata: customMetadata,
    );
  }

  Future<_R2Listing> _list({
    required String prefix,
    String? delimiter,
    bool suppressErrors = true,
  }) {
    Future<_R2Listing> operation() async {
      final objects = <CloudflareR2Object>[];
      final prefixes = <String>{};
      String? cursor;
      var truncated = true;
      while (truncated) {
        final page = await bucket.list(
          options: CloudflareR2ListOptions(
            prefix: prefix.isEmpty ? null : prefix,
            delimiter: delimiter,
            cursor: cursor,
            limit: 1000,
          ),
        );
        objects.addAll(page.objects);
        prefixes.addAll(page.delimitedPrefixes);
        truncated = page.truncated;
        if (!truncated) continue;
        final next = page.cursor;
        if (next == null || next.isEmpty || next == cursor) {
          throw StateError('R2 returned a truncated list without a cursor.');
        }
        cursor = next;
      }
      return _R2Listing(objects: objects, delimitedPrefixes: prefixes);
    }

    return suppressErrors
        ? _attempt(const _R2Listing(), operation)
        : operation();
  }

  String _key(String value) {
    final relative = resolve(value);
    final root = prefix;
    if (root == null) return relative;
    if (relative.isEmpty) return root;
    return '$root/$relative';
  }

  String _objectKey(String value) {
    final relative = resolve(value);
    if (relative.isEmpty) {
      throw ArgumentError.value(
        value,
        'path',
        'R2 object key cannot be empty.',
      );
    }
    final root = prefix;
    return root == null ? relative : '$root/$relative';
  }

  String _directoryKey(String value) {
    final key = _key(value);
    if (key.isEmpty || key.endsWith('/')) return key;
    return '$key/';
  }

  String _relativeKey(String key) {
    final root = prefix;
    if (root == null) return key;
    if (key == root || key == '$root/') return '';
    final rootPrefix = '$root/';
    if (!key.startsWith(rootPrefix)) return '';
    return key.substring(rootPrefix.length);
  }

  static String? _normalizePrefix(String? prefix) {
    final value = prefix?.trim();
    if (value == null || value.isEmpty) return null;
    final segments = value.split('/');
    if (segments.contains('..')) {
      throw ArgumentError.value(
        prefix,
        'prefix',
        'Cannot escape the bucket root.',
      );
    }
    final normalized = segments
        .where((segment) => segment.isNotEmpty && segment != '.')
        .join('/');
    return normalized.isEmpty ? null : normalized;
  }

  static String _trimTrailingSlash(String value) {
    var result = value;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return <String, String>{};
    return value.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }
}

const _maximumDeleteKeys = 1000;

final class _R2Listing {
  const _R2Listing({
    this.objects = const <CloudflareR2Object>[],
    this.delimitedPrefixes = const <String>{},
  });

  final List<CloudflareR2Object> objects;
  final Set<String> delimitedPrefixes;
}
