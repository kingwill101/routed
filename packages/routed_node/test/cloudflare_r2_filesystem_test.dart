import 'dart:convert';
import 'dart:typed_data';

import 'package:routed_node/cloudflare.dart';
import 'package:test/test.dart';

void main() {
  group('CloudflareR2Filesystem', () {
    late _MemoryR2Bucket bucket;
    late CloudflareR2Filesystem filesystem;

    setUp(() {
      bucket = _MemoryR2Bucket(pageSize: 2);
      filesystem = CloudflareR2Filesystem(
        bucket: bucket,
        prefix: '/tenant/assets/',
      );
    });

    test('scopes keys and exposes storage_fs operations', () async {
      expect(
        await filesystem.put(
          'documents/readme.txt',
          'hello',
          options: const {
            'contentType': 'text/plain',
            'customMetadata': {'source': 'routed'},
          },
        ),
        isTrue,
      );

      expect(bucket.keys, ['tenant/assets/documents/readme.txt']);
      expect(await filesystem.exists('documents/readme.txt'), isTrue);
      expect(await filesystem.missing('missing.txt'), isTrue);
      expect(await filesystem.get('documents/readme.txt'), 'hello');
      expect(await filesystem.size('documents/readme.txt'), 5);
      expect(await filesystem.mimeType('documents/readme.txt'), 'text/plain');
      expect(await filesystem.checksum('documents/readme.txt'), 'etag-5');
      expect(
        bucket.metadata('tenant/assets/documents/readme.txt'),
        containsPair('source', 'routed'),
      );
      expect(
        await filesystem
            .readStream('documents/readme.txt')
            .expand((e) => e)
            .toList(),
        utf8.encode('hello'),
      );
    });

    test('rejects paths that escape the configured prefix', () async {
      expect(filesystem.resolve('images/../logo.png'), 'logo.png');
      expect(() => filesystem.resolve('/absolute.txt'), throwsArgumentError);
      expect(() => filesystem.resolve('../outside.txt'), throwsArgumentError);
      expect(
        () => CloudflareR2Filesystem(bucket: bucket, prefix: '../outside'),
        throwsArgumentError,
      );
      expect(await filesystem.put('', 'invalid'), isFalse);
      expect(bucket.keys, isEmpty);
    });

    test('lists paginated files and emulated directories', () async {
      await filesystem.put('docs/a.txt', 'a');
      await filesystem.put('docs/b.txt', 'b');
      await filesystem.put('docs/nested/c.txt', 'c');
      await filesystem.put('images/logo.png', <int>[1, 2, 3]);

      expect(await filesystem.files('docs'), ['docs/a.txt', 'docs/b.txt']);
      expect(await filesystem.allFiles('docs'), [
        'docs/a.txt',
        'docs/b.txt',
        'docs/nested/c.txt',
      ]);
      expect(await filesystem.directories(), ['docs', 'images']);
      expect(await filesystem.allDirectories(), [
        'docs',
        'docs/nested',
        'images',
      ]);
      expect(await filesystem.allDirectories('docs'), ['docs/nested']);
    });

    test(
      'supports copy, move, directory markers, and recursive delete',
      () async {
        expect(await filesystem.makeDirectory('archive'), isTrue);
        await filesystem.put('archive/one.txt', 'one');
        expect(
          await filesystem.copy('archive/one.txt', 'archive/two.txt'),
          isTrue,
        );
        expect(
          await filesystem.move('archive/two.txt', 'archive/moved.txt'),
          isTrue,
        );
        expect(await filesystem.exists('archive/two.txt'), isFalse);
        expect(await filesystem.get('archive/moved.txt'), 'one');

        expect(await filesystem.deleteDirectory('archive'), isTrue);
        expect(await filesystem.allFiles('archive'), isEmpty);
        expect(
          bucket.keys,
          everyElement(isNot(startsWith('tenant/assets/archive/'))),
        );
      },
    );

    test('read-only mode blocks mutations', () async {
      final readOnly = CloudflareR2Filesystem(
        bucket: bucket,
        readOnly: true,
      );
      expect(await readOnly.put('file.txt', 'blocked'), isFalse);
      expect(bucket.keys, isEmpty);

      final throwing = CloudflareR2Filesystem(
        bucket: bucket,
        readOnly: true,
        throwOnError: true,
      );
      await expectLater(throwing.put('file.txt', 'blocked'), throwsStateError);
    });

    test('treats visibility as a bucket-scoped capability', () async {
      await filesystem.put('documents/private.txt', 'private');

      expect(
        await filesystem.getVisibility('documents/private.txt'),
        'private',
      );
      expect(
        await filesystem.setVisibility('documents/private.txt', 'private'),
        isTrue,
      );
      expect(
        await filesystem.setVisibility('documents/private.txt', 'public'),
        isFalse,
      );

      final throwing = CloudflareR2Filesystem(
        bucket: bucket,
        throwOnError: true,
      );
      await expectLater(
        throwing.setVisibility('documents/private.txt', 'public'),
        throwsUnsupportedError,
      );

      expect(
        await filesystem.put(
          'documents/public.txt',
          'not-public',
          options: const {'visibility': 'public'},
        ),
        isFalse,
      );
      expect(
        await filesystem.exists('documents/public.txt'),
        isFalse,
      );
      await expectLater(
        throwing.put(
          'documents/public.txt',
          'not-public',
          options: const {'visibility': 'public'},
        ),
        throwsUnsupportedError,
      );
    });

    test('append and prepend never overwrite after a read failure', () async {
      await filesystem.put('existing.txt', 'original');
      bucket.getFailure = Exception('transient read failure');

      expect(await filesystem.append('existing.txt', 'tail'), isFalse);
      expect(await filesystem.prepend('existing.txt', 'head'), isFalse);
      expect(
        bucket.bytes('tenant/assets/existing.txt'),
        utf8.encode('original'),
      );
    });

    test('append never overwrites text that cannot be decoded', () async {
      await filesystem.put('binary.dat', <int>[0xff]);

      expect(await filesystem.append('binary.dat', 'tail'), isFalse);
      expect(bucket.bytes('tenant/assets/binary.dat'), [0xff]);
    });

    test(
      'deleteDirectory reports a listing failure and keeps objects',
      () async {
        await filesystem.put('private/one.txt', 'one');
        bucket.listFailure = Exception('transient list failure');

        expect(await filesystem.deleteDirectory('private'), isFalse);
        expect(bucket.keys, contains('tenant/assets/private/one.txt'));
      },
    );
  });
}

final class _MemoryR2Bucket implements CloudflareR2Bucket {
  _MemoryR2Bucket({required this.pageSize});

  final int pageSize;
  final Map<String, _StoredObject> _objects = {};
  Exception? getFailure;
  Exception? listFailure;

  List<String> get keys => _objects.keys.toList()..sort();

  Map<String, String> metadata(String key) => _objects[key]!.customMetadata;

  List<int> bytes(String key) => _objects[key]!.bytes;

  @override
  Future<void> delete(Object keys) async {
    switch (keys) {
      case String key:
        _objects.remove(key);
        return;
      case Iterable<String> values:
        for (final key in values) {
          _objects.remove(key);
        }
        return;
      default:
        throw ArgumentError.value(keys, 'keys');
    }
  }

  @override
  Future<CloudflareR2Object?> get(String key) async {
    if (getFailure case final failure?) throw failure;
    return _objects[key]?.object(includeBody: true);
  }

  @override
  Future<CloudflareR2Object?> head(String key) async {
    return _objects[key]?.object(includeBody: false);
  }

  @override
  Future<CloudflareR2ListResult> list({
    CloudflareR2ListOptions? options,
  }) async {
    if (listFailure case final failure?) throw failure;
    final prefix = options?.prefix ?? '';
    final delimiter = options?.delimiter;
    final allKeys = keys.where((key) => key.startsWith(prefix)).toList();
    final directKeys = <String>[];
    final delimitedPrefixes = <String>{};
    for (final key in allKeys) {
      final remainder = key.substring(prefix.length);
      final delimiterIndex = delimiter == null
          ? -1
          : remainder.indexOf(delimiter);
      if (delimiterIndex >= 0) {
        delimitedPrefixes.add(
          '$prefix${remainder.substring(0, delimiterIndex + delimiter!.length)}',
        );
      } else {
        directKeys.add(key);
      }
    }

    final offset = int.tryParse(options?.cursor ?? '') ?? 0;
    final effectiveLimit = options?.limit == null
        ? pageSize
        : options!.limit! < pageSize
        ? options.limit!
        : pageSize;
    final end = offset + effectiveLimit < directKeys.length
        ? offset + effectiveLimit
        : directKeys.length;
    final page = directKeys.sublist(offset, end);
    final truncated = end < directKeys.length;
    return CloudflareR2ListResult(
      objects: page
          .map((key) => _objects[key]!.object(includeBody: false))
          .toList(),
      truncated: truncated,
      cursor: truncated ? '$end' : null,
      delimitedPrefixes: delimitedPrefixes.toList()..sort(),
    );
  }

  @override
  Future<CloudflareR2Object?> put(
    String key,
    Object? value, {
    CloudflareR2PutOptions? options,
  }) async {
    final bytes = switch (value) {
      String text => Uint8List.fromList(utf8.encode(text)),
      Uint8List bytes => bytes,
      List<int> bytes => Uint8List.fromList(bytes),
      _ => throw ArgumentError.value(value, 'value'),
    };
    final stored = _StoredObject(
      key: key,
      bytes: bytes,
      httpMetadata: options?.httpMetadata ?? const {},
      customMetadata: options?.customMetadata ?? const {},
    );
    _objects[key] = stored;
    return stored.object(includeBody: false);
  }
}

final class _StoredObject {
  const _StoredObject({
    required this.key,
    required this.bytes,
    required this.httpMetadata,
    required this.customMetadata,
  });

  final String key;
  final Uint8List bytes;
  final Map<String, String> httpMetadata;
  final Map<String, String> customMetadata;

  CloudflareR2Object object({required bool includeBody}) {
    return CloudflareR2Object(
      key: key,
      size: bytes.length,
      etag: 'etag-${bytes.length}',
      uploaded: DateTime.utc(2026, 8, 29),
      httpMetadata: httpMetadata,
      customMetadata: customMetadata,
      body: includeBody ? Stream.value(bytes) : null,
    );
  }
}
