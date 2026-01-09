import 'dart:io' show HttpStatus;
import 'dart:typed_data';

import 'package:file/file.dart' as file;
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('upload guardrails', () {
    test(
      'rejects uploads that exceed disk quota and cleans up partial files',
      () async {
        final fs = MemoryFileSystem();
        final uploadDir = fs.directory('/quota')..createSync(recursive: true);

        final engine = testEngine(
          config: EngineConfig(
            fileSystem: fs,
            multipart: MultipartConfig(uploadDirectory: uploadDir.path),
          ),
          configItems: {
            'uploads': {
              'max_file_size': 1024,
              'max_disk_usage': 12,
              'directory': uploadDir.path,
              'allowed_extensions': ['gif'],
              'file_permissions': 448,
            },
          },
        );

        engine.post('/upload', (ctx) async {
          try {
            await ctx.formFile('document');
            return ctx.response
              ..statusCode = HttpStatus.ok
              ..write('ok');
          } on FileQuotaExceededException catch (error) {
            ctx.response
              ..statusCode = HttpStatus.requestEntityTooLarge
              ..write(error.toString());
            return ctx.response;
          }
        });

        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.multipart('/upload', (request) {
          request.addFileFromBytes(
            name: 'document',
            filename: 'huge.gif',
            bytes: Uint8List.fromList(List<int>.filled(20, 1)),
            contentType: MediaType.parse('text/plain'),
          );
        });

        response.assertStatus(HttpStatus.requestEntityTooLarge);
        final files = uploadDir
            .listSync(recursive: true)
            .whereType<file.File>()
            .where((file) => file.existsSync())
            .toList();
        expect(files, isEmpty);
      },
    );

    test('disallowed extensions leave no residual files', () async {
      final fs = MemoryFileSystem();
      final uploadDir = fs.directory('/extensions')
        ..createSync(recursive: true);

      final engine = testEngine(
        config: EngineConfig(
          fileSystem: fs,
          multipart: MultipartConfig(uploadDirectory: uploadDir.path),
        ),
        configItems: {
          'uploads': {
            'directory': uploadDir.path,
            'allowed_extensions': ['jpg'],
            'file_permissions': 448,
          },
        },
      );

      engine.post('/upload', (ctx) async {
        try {
          await ctx.formFile('document');
          return ctx.response
            ..statusCode = HttpStatus.ok
            ..write('ok');
        } on FileExtensionNotAllowedException catch (error) {
          ctx.response
            ..statusCode = HttpStatus.unsupportedMediaType
            ..write(error.toString());
          return ctx.response;
        }
      });

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final response = await client.multipart('/upload', (request) {
        request.addFileFromBytes(
          name: 'document',
          filename: 'payload.exe',
          bytes: Uint8List.fromList(List<int>.filled(10, 1)),
          contentType: MediaType.parse('application/octet-stream'),
        );
      });

      response.assertStatus(HttpStatus.unsupportedMediaType);
      final files = uploadDir
          .listSync(recursive: true)
          .whereType<file.File>()
          .where((file) => file.existsSync())
          .toList();
      expect(files, isEmpty);
    });

    test(
      'accepts whitelisted uploads and leaves artifacts for application',
      () async {
        final fs = MemoryFileSystem();
        final uploadDir = fs.directory('/accept')..createSync(recursive: true);

        final engine = testEngine(
          config: EngineConfig(
            fileSystem: fs,
            multipart: MultipartConfig(uploadDirectory: uploadDir.path),
          ),
          configItems: {
            'uploads': {
              'directory': uploadDir.path,
              'allowed_extensions': ['txt'],
              'max_file_size': 1024,
              'max_disk_usage': 4096,
              'file_permissions': 448,
            },
          },
        );

        engine.post('/upload', (ctx) async {
          final file = await ctx.formFile('document');
          return ctx.string(file?.path ?? 'missing');
        });

        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.multipart('/upload', (request) {
          request.addFileFromBytes(
            name: 'document',
            filename: 'note.txt',
            bytes: Uint8List.fromList(List<int>.filled(10, 42)),
            contentType: MediaType.parse('text/plain'),
          );
        });

        response.assertStatus(HttpStatus.ok);
        final files = uploadDir
            .listSync(recursive: true)
            .whereType<file.File>()
            .where((file) => file.existsSync())
            .toList();
        expect(files.length, 1);
        expect(files.first.lengthSync(), 10);
      },
    );
  });
}
