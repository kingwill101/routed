import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:routed/console.dart' show CliLogger;
import 'package:routed/src/console/args/commands/provider.dart';
import 'package:routed/src/console/args/runner.dart';
import 'package:test/test.dart';

void main() {
  group('Provider commands', () {
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
      writeFile('config/http.yaml', '''providers:
  - routed.logging
  - routed.cache
''');

      logger = _RecordingLogger();
      runner = RoutedCommandRunner(logger: logger)
        ..register([ProviderListCommand(logger: logger, fileSystem: memoryFs)]);
    });

    test('provider:list filters by id', () async {
      await runner.run(['provider:list', 'routed.logging', '--config']);

      expect(_hasProviderLine(logger, 'routed.logging'), isTrue);
      expect(_hasProviderLine(logger, 'routed.cache'), isFalse);
    });

    test('provider:list rejects unknown ids', () async {
      await expectLater(
        runner.run(['provider:list', 'routed.unknown']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}

bool _hasProviderLine(_RecordingLogger logger, String id) {
  return logger.infos.any((line) => line.startsWith(id));
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
