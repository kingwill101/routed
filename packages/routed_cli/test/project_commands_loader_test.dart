import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart' show UsageException;
import 'package:path/path.dart' as p;
import 'package:routed_cli/routed_cli.dart' as rc;
import 'package:routed_cli/src/args/commands.dart' as cmds;
import 'package:routed_cli/src/args/runner.dart';
import 'package:routed_cli/src/project/commands_loader.dart';
import 'package:routed_cli/src/util/dart_exec.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectCommandsLoader', () {
    late String cliRoot;
    late rc.CliLogger logger;
    late io.Directory projectDir;

    setUpAll(() {
      cliRoot = io.Directory.current.path;
    });

    setUp(() async {
      logger = rc.CliLogger(verbose: true);
      projectDir = await io.Directory.systemTemp.createTemp(
        'routed_cli_project_commands_test_',
      );
    });

    tearDown(() async {
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
    });

    test('discovers and runs project commands', () async {
      await _writeProject(
        projectDir: projectDir,
        cliRoot: cliRoot,
        commandName: 'hello',
      );

      final previousCwd = io.Directory.current;
      io.Directory.current = projectDir;
      addTearDown(() => io.Directory.current = previousCwd);

      final loader = ProjectCommandsLoader(logger: logger);
      final infos = await loader.loadProjectCommands('usage');

      expect(infos.map((info) => info.name), contains('hello'));

      final exitCode = await loader.runProjectCommand('hello', [
        '--name',
        'Dart',
      ]);
      expect(exitCode, equals(0));

      final outputFile = io.File(p.join(projectDir.path, 'command_output.txt'));
      expect(await outputFile.readAsString(), contains('hello for Dart'));
    });

    test('throws when a project command conflicts with built-ins', () async {
      await _writeProject(
        projectDir: projectDir,
        cliRoot: cliRoot,
        commandName: 'dev',
      );

      final previousCwd = io.Directory.current;
      io.Directory.current = projectDir;
      addTearDown(() => io.Directory.current = previousCwd);

      final loader = ProjectCommandsLoader(logger: logger);
      final infos = await loader.loadProjectCommands('usage');

      final runner = RoutedCommandRunner(logger: logger)
        ..register([cmds.DevCommand()]);

      expect(
        () => loader.registerWithRunner(runner, infos, runner.usage),
        throwsA(isA<UsageException>()),
      );
    });

    test('fails when entrypoint returns invalid values', () async {
      await _writeProject(
        projectDir: projectDir,
        cliRoot: cliRoot,
        commandName: 'broken',
        commandsSource: '''
import 'dart:async';
import 'package:args/command_runner.dart';

FutureOr<List<Command<void>>> buildProjectCommands() async {
  return [42];
}
''',
      );

      final previousCwd = io.Directory.current;
      io.Directory.current = projectDir;
      addTearDown(() => io.Directory.current = previousCwd);

      final loader = ProjectCommandsLoader(logger: logger);
      expect(
        () => loader.loadProjectCommands('usage'),
        throwsA(isA<UsageException>()),
      );
    });
  });
}

Future<void> _writeProject({
  required io.Directory projectDir,
  required String cliRoot,
  required String commandName,
  String? commandsSource,
}) async {
  final pubspec =
      '''
name: project_app
environment:
  sdk: ">=3.9.2 <4.0.0"
dependencies:
  args: any
dev_dependencies:
  routed_cli:
    path: ${_escapePath(cliRoot)}
''';

  final pubspecFile = io.File(p.join(projectDir.path, 'pubspec.yaml'));
  await pubspecFile.writeAsString(pubspec);

  final libDir = io.Directory(p.join(projectDir.path, 'lib'));
  await libDir.create(recursive: true);
  final binDir = io.Directory(p.join(projectDir.path, 'bin'));
  await binDir.create(recursive: true);
  await io.File(p.join(binDir.path, 'server.dart')).writeAsString('''
void main(List<String> args) {}
''');

  final commandsFile = io.File(p.join(libDir.path, 'commands.dart'));
  final className =
      '${commandName[0].toUpperCase()}${commandName.substring(1)}Command';
  final defaultSource =
      '''
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

class $className extends Command<void> {
  $className() {
    argParser.addOption('name', defaultsTo: 'World');
  }

  @override
  String get name => '$commandName';

  @override
  String get description => 'Example project command.';

  @override
  Future<void> run() async {
    final target = argResults?.option('name') ?? 'World';
    final file = File('command_output.txt');
    await file.writeAsString('$commandName for \$target');
  }
}

FutureOr<List<Command<void>>> buildProjectCommands() => [$className()];
''';
  await commandsFile.writeAsString(commandsSource ?? defaultSource);

  final process = await startDartProcess([
    'pub',
    'get',
  ], workingDirectory: projectDir.path);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;
  final stdoutText = await stdoutFuture;
  final stderrText = await stderrFuture;
  if (exitCode != 0) {
    throw StateError(
      'pub get failed (exit code $exitCode):\n$stdoutText\n$stderrText',
    );
  }
}

String _escapePath(String path) {
  if (io.Platform.isWindows) {
    return path.replaceAll(r'\', r'\\');
  }
  return path;
}
