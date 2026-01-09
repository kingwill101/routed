import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed/console.dart' show CliLogger;
import 'package:routed/src/console/args/commands/dev.dart';
import 'package:routed/src/console/args/runner.dart';
import 'package:routed/src/console/dev/dev_server_runner.dart' as dev;
import 'package:test/test.dart';

void main() {
  group('DevCommand', () {
    late MemoryFileSystem memoryFs;
    late fs.Directory projectRoot;
    late RoutedCommandRunner runner;
    late _RecordingLogger logger;
    late _FakeDevServer fakeServer;

    void writeFile(String relative, String contents) {
      final file = memoryFs.file(memoryFs.path.join(projectRoot.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    setUp(() {
      memoryFs = MemoryFileSystem();
      projectRoot = memoryFs.directory('/workspace/project')
        ..createSync(recursive: true);
      memoryFs.currentDirectory = projectRoot;

      writeFile('pubspec.yaml', 'name: dev_sample\n');
      writeFile('bin/server.dart', _sampleServer);

      fakeServer = _FakeDevServer();
      logger = _RecordingLogger();
      runner = RoutedCommandRunner(logger: logger)
        ..register([
          DevCommand(
            logger: logger,
            fileSystem: memoryFs,
            runnerFactory:
                ({
                  required CliLogger logger,
                  required String port,
                  required io.InternetAddress? address,
                  required String dartVmServicePort,
                  required io.Directory workingDirectory,
                  required String scriptPath,
                  required bool hotReloadExpected,
                  List<String>? additionalWatchPaths,
                }) {
                  fakeServer.configure(
                    port: port,
                    address: address,
                    workingDirectory: workingDirectory,
                    scriptPath: scriptPath,
                    hotReloadExpected: hotReloadExpected,
                    additionalWatchPaths: additionalWatchPaths ?? const [],
                  );
                  return fakeServer;
                },
          ),
        ]);
    });

    test('launches dev server with bootstrap disabled', () async {
      await _run(runner, [
        'dev',
        '--entry',
        'bin/server.dart',
        '--host',
        '127.0.0.1',
        '--port',
        '4242',
        '--no-bootstrap',
        '--no-install-missing',
        '--no-warn-missing',
      ]);

      expect(fakeServer.started, isTrue);
      expect(
        fakeServer.startArguments,
        equals(['--host', '127.0.0.1', '--port', '4242']),
      );
      expect(fakeServer.port, equals('4242'));
      expect(
        fakeServer.scriptPath,
        equals(memoryFs.path.join(projectRoot.path, 'bin/server.dart')),
      );
      expect(fakeServer.hotReloadExpected, isFalse);
      expect(fakeServer.additionalWatchPaths, isEmpty);
      expect(io.exitCode, equals(dev.ExitCode.success.code));
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

class _FakeDevServer implements DevServer {
  bool started = false;
  List<String>? startArguments;
  late String port;
  io.InternetAddress? address;
  late io.Directory workingDirectory;
  late String scriptPath;
  late bool hotReloadExpected;
  late List<String> additionalWatchPaths;

  void configure({
    required String port,
    required io.InternetAddress? address,
    required io.Directory workingDirectory,
    required String scriptPath,
    required bool hotReloadExpected,
    required List<String> additionalWatchPaths,
  }) {
    this.port = port;
    this.address = address;
    this.workingDirectory = workingDirectory;
    this.scriptPath = scriptPath;
    this.hotReloadExpected = hotReloadExpected;
    this.additionalWatchPaths = additionalWatchPaths;
    started = false;
    startArguments = null;
  }

  @override
  Future<void> start(List<String> arguments) async {
    started = true;
    startArguments = arguments;
  }

  @override
  Future<dev.ExitCode> get exitCode async => dev.ExitCode.success;
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

const String _sampleServer = '''
import 'dart:io';

Future<void> main(List<String> args) async {
  final server = await HttpServer.bind('127.0.0.1', 4242);
  stdout.writeln('Sample dev server listening on http://127.0.0.1:' + server.port.toString());
  await for (final request in server) {
    request.response
      ..write('ok')
      ..close();
  }
}
''';
