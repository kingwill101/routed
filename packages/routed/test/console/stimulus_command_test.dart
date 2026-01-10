import 'package:file/memory.dart';
import 'package:routed/console.dart' show CliLogger;
import 'package:routed/src/console/args/commands/stimulus.dart';
import 'package:routed/src/console/args/runner.dart';
import 'package:test/test.dart';

class _RecordingLogger extends CliLogger {
  final infos = <String>[];
  final warns = <String>[];
  final errors = <String>[];

  @override
  void info(Object? message) => infos.add('$message');

  @override
  void warn(Object? message) => warns.add('$message');

  @override
  void error(Object? message) => errors.add('$message');
}

void main() {
  group('StimulusInstallCommand', () {
    late MemoryFileSystem memoryFs;
    late _RecordingLogger logger;
    late RoutedCommandRunner runner;

    setUp(() {
      memoryFs = MemoryFileSystem();
      final projectRoot = memoryFs.directory('/workspace/demo')
        ..createSync(recursive: true);
      memoryFs.file(memoryFs.path.join(projectRoot.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: demo');
      memoryFs.currentDirectory = projectRoot;

      logger = _RecordingLogger();
      runner = RoutedCommandRunner(logger: logger)
        ..register([
          StimulusInstallCommand(logger: logger, fileSystem: memoryFs),
        ]);
    });

    test('scaffolds files when missing', () async {
      await runner.run(['stimulus:install']);

      final createdFiles = [
        'public/js/controllers/application.js',
        'public/js/controllers/index.js',
        'public/js/controllers/hello_controller.js',
        'public/js/stimulus.js',
      ];

      for (final relative in createdFiles) {
        final file = memoryFs.file(relative);
        expect(file.existsSync(), isTrue, reason: '$relative missing');
      }

      expect(
        logger.infos.join('\n'),
        contains('Generated Stimulus scaffolding'),
      );
    });

    test('skips existing files unless forced', () async {
      final existing = ['public/js/stimulus.js'];
      for (final relative in existing) {
        memoryFs.file(relative)
          ..createSync(recursive: true)
          ..writeAsStringSync('// existing');
      }

      await runner.run(['stimulus:install']);

      final skippedMessage = logger.warns.join('\n');
      expect(skippedMessage, contains('Skipped existing files'));
      expect(skippedMessage, contains('public/js/stimulus.js'));

      await runner.run(['stimulus:install', '--force']);
      expect(
        memoryFs.file('public/js/stimulus.js').readAsStringSync(),
        isNot('// existing'),
      );
    });
  });
}
