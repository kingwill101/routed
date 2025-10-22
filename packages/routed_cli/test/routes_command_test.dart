import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed_cli/routed_cli.dart' as rc;
import 'package:routed_cli/src/args/commands/routes.dart';
import 'package:routed_cli/src/args/runner.dart';
import 'package:routed_cli/src/engine/introspector.dart';
import 'package:test/test.dart';

@Tags(['serial'])
void main() {
  group('RoutesCommand', () {
    late MemoryFileSystem memoryFs;
    late fs.Directory projectRoot;
    late RoutedCommandRunner runner;
    late _RecordingLogger logger;

    void writeFile(String relative, String contents) {
      final file = memoryFs.file(p.join(projectRoot.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    setUp(() {
      memoryFs = MemoryFileSystem();
      projectRoot = memoryFs.directory('/workspace/project')
        ..createSync(recursive: true);
      memoryFs.currentDirectory = projectRoot;
      writeFile('pubspec.yaml', 'name: demo\n');

      logger = _RecordingLogger();
    });

    test('prints table by default', () async {
      final manifest = {
        'routes': [
          {
            'method': 'GET',
            'path': '/readyz',
            'name': 'observability.readiness',
          },
          {'method': 'GET', 'path': '/livez', 'name': 'observability.liveness'},
          {'method': 'GET', 'path': '/', 'name': ''},
        ],
        'webSockets': const [],
      };

      runner = RoutedCommandRunner(logger: logger)
        ..register([
          RoutesCommand(
            logger: logger,
            fileSystem: memoryFs,
            loaderFactory: (root, log, usage, fileSystem) {
              return _FakeManifestLoader(
                root: root,
                logger: log,
                usage: usage,
                fileSystem: fileSystem,
                result: ManifestLoadResult(
                  manifest: manifest,
                  source: ManifestSource.entry,
                  sourceDescription: 'tool/spec_manifest.dart',
                ),
              );
            },
          ),
        ]);

      await _run(runner, ['routes']);

      expect(
        logger.infos,
        contains('METHOD  PATH     NAME                     MIDDLEWARE'),
      );
      expect(
        logger.infos,
        contains('GET     /readyz  observability.readiness            '),
      );
      expect(
        logger.infos,
        contains('Used manifest entrypoint: tool/spec_manifest.dart'),
      );
    });

    test('supports json format', () async {
      final manifest = {
        'routes': [
          {'method': 'GET', 'path': '/'},
        ],
        'webSockets': const [],
      };

      runner = RoutedCommandRunner(logger: logger)
        ..register([
          RoutesCommand(
            logger: logger,
            fileSystem: memoryFs,
            loaderFactory: (root, log, usage, fileSystem) {
              return _FakeManifestLoader(
                root: root,
                logger: log,
                usage: usage,
                fileSystem: fileSystem,
                result: ManifestLoadResult(
                  manifest: manifest,
                  source: ManifestSource.entry,
                  sourceDescription: 'tool/spec_manifest.dart',
                ),
              );
            },
          ),
        ]);

      await _run(runner, ['routes', '--format', 'json', '--pretty']);

      final jsonLine = logger.infos.firstWhere(
        (line) => line.trim().startsWith('{'),
      );
      final decoded = jsonDecode(jsonLine) as Map<String, dynamic>;
      expect(decoded['routes'], isA<List>());
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
  }) : super(
         projectRoot: root,
       );

  final ManifestLoadResult result;

  @override
  Future<ManifestLoadResult> load({String? entry}) async => result;
}

class _RecordingLogger extends rc.CliLogger {
  _RecordingLogger() : super(verbose: true);

  final List<String> infos = [];

  @override
  void info(Object? message) {
    super.info(message);
    infos.add(message.toString());
  }
}
