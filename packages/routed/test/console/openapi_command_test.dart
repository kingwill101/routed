import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:routed/console.dart' show CliLogger;
import 'package:routed/routed.dart' as routed;

import 'package:routed/src/console/args/commands/openapi.dart';
import 'package:routed/src/console/args/runner.dart';
import 'package:routed/src/console/engine/introspector.dart';
import 'package:test/test.dart';

void main() {
  group('OpenApiGenerateCommand', () {
    late MemoryFileSystem memoryFs;
    late fs.Directory projectRoot;
    late RoutedCommandRunner runner;
    late _RecordingLogger logger;

    void writeFile(String relativePath, String contents) {
      final file = memoryFs.file(
        memoryFs.path.join(projectRoot.path, relativePath),
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    setUp(() {
      memoryFs = MemoryFileSystem();
      projectRoot = memoryFs.directory('/workspace/project')
        ..createSync(recursive: true);
      memoryFs.currentDirectory = projectRoot;

      writeFile('pubspec.yaml', 'name: demo\n');
      writeFile('tool/spec_manifest.dart', '// placeholder\n');

      final manifest = routed.RouteManifest(
        routes: [
          routed.RouteManifestEntry(
            method: 'GET',
            path: '/hello/{name}',
            constraints: {
              'openapi': {'summary': 'Say hello'},
            },
          ),
        ],
      );

      logger = _RecordingLogger();
      runner = RoutedCommandRunner(logger: logger)
        ..register([
          OpenApiCommand(
            logger: logger,
            fileSystem: memoryFs,
            loaderFactory: (root, log, usage, fileSystem) {
              return _FakeManifestLoader(
                root: root,
                logger: log,
                usage: usage,
                fileSystem: fileSystem,
                result: ManifestLoadResult(
                  manifest: manifest.toJson(),
                  source: ManifestSource.entry,
                  sourceDescription: 'tool/spec_manifest.dart',
                ),
              );
            },
          ),
        ]);
    });

    test('writes OpenAPI document to disk', () async {
      await _run(runner, [
        'openapi',
        'generate',
        '--title',
        'Demo API',
        '--version',
        '2.0.0',
        '--server',
        'https://api.example.com|Production',
      ]);

      final outputFile = memoryFs.file(
        memoryFs.path.join(
          projectRoot.path,
          '.dart_tool',
          'routed',
          'openapi.json',
        ),
      );
      expect(outputFile.existsSync(), isTrue);

      final document =
          jsonDecode(outputFile.readAsStringSync()) as Map<String, Object?>;
      expect(document['openapi'], equals('3.1.0'));

      final info = document['info'] as Map<String, Object?>;
      expect(info['title'], equals('Demo API'));
      expect(info['version'], equals('2.0.0'));

      final servers = document['servers'] as List<Object?>;
      expect(servers.length, equals(1));
      final server = servers.first as Map<String, Object?>;
      expect(server['url'], equals('https://api.example.com'));
      expect(server['description'], equals('Production'));

      final paths = document['paths'] as Map<String, Object?>;
      expect(paths, contains('/hello/{name}'));
    });
  });
}

Future<void> _run(RoutedCommandRunner runner, List<String> args) async {
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    fail('Command failed: $e');
  }
}

class _FakeManifestLoader extends ManifestLoader {
  _FakeManifestLoader({
    required fs.Directory root,
    required super.logger,
    required super.usage,
    required fs.FileSystem super.fileSystem,
    required this.result,
  }) : super(projectRoot: root);

  final ManifestLoadResult result;

  @override
  Future<ManifestLoadResult> load({String? entry}) async => result;
}

class _RecordingLogger extends CliLogger {
  _RecordingLogger() : super(verbose: true);
}
