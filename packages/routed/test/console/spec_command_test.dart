import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;

import 'package:routed/console.dart' show CliLogger;
import 'package:routed/src/console/args/commands/spec.dart';
import 'package:routed/src/console/args/runner.dart';
import 'package:routed/src/console/engine/introspector.dart';
import 'package:test/test.dart';

void main() {
  group('SpecGenerateCommand', () {
    late MemoryFileSystem memoryFs;
    late fs.Directory projectRoot;
    late RoutedCommandRunner runner;
    late _RecordingLogger logger;

    void writeFile(String relativePath, String contents) {
      final file = memoryFs.file(memoryFs.path.join(projectRoot.path, relativePath));
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

      logger = _RecordingLogger();
      runner = RoutedCommandRunner(logger: logger)
        ..register([
          SpecGenerateCommand(
            logger: logger,
            fileSystem: memoryFs,
            loaderFactory: (root, log, usage, fileSystem) {
              return _FakeManifestLoader(
                root: root,
                logger: log,
                usage: usage,
                fileSystem: fileSystem,
                result: ManifestLoadResult(
                  manifest: {
                    'generatedAt': 'now',
                    'routes': [
                      {'method': 'GET', 'path': '/'},
                    ],
                    'webSockets': const [],
                  },
                  source: ManifestSource.entry,
                  sourceDescription: 'tool/spec_manifest.dart',
                ),
              );
            },
          ),
        ]);
    });

    test('writes manifest to disk', () async {
      await _run(runner, [
        'spec:generate',
        '--entry',
        'tool/spec_manifest.dart',
      ]);

      final manifestFile = memoryFs.file(
        memoryFs.path.join(projectRoot.path, '.dart_tool', 'routed', 'route_manifest.json'),
      );
      expect(manifestFile.existsSync(), isTrue);

      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      expect(manifest['routes'], isA<List<Object?>>());
      expect(
        logger.infos,
        contains('Used manifest entrypoint: tool/spec_manifest.dart'),
      );
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

  final List<String> infos = [];

  @override
  void info(Object? message) {
    super.info(message);
    infos.add(message.toString());
  }
}
