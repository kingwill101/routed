import 'package:file/memory.dart';
import 'package:routed_cli/routed_cli.dart';
import 'package:test/test.dart';

void main() {
  test('build generates a native entrypoint with engine commands', () async {
    final fileSystem = MemoryFileSystem();
    final projectRoot = fileSystem.directory('/workspace/demo')
      ..createSync(recursive: true);
    fileSystem.currentDirectory = projectRoot;
    _write(
      fileSystem,
      projectRoot.path,
      'pubspec.yaml',
      'name: demo\n',
    );
    _write(
      fileSystem,
      projectRoot.path,
      'lib/app.dart',
      '''
import 'package:routed_core/routed_core.dart';

Future<Engine> createEngine({bool initialize = true}) async {
  return Engine();
}
''',
    );
    _write(
      fileSystem,
      projectRoot.path,
      'lib/commands.dart',
      'void buildProjectCommands() {}\n',
    );

    String? executable;
    List<String>? arguments;
    String? workingDirectory;
    final runner = RoutedCommandRunner()
      ..register([
        BuildCommand(
          fileSystem: fileSystem,
          processRunner: (value, args, directory) async {
            executable = value;
            arguments = args;
            workingDirectory = directory;
            return 0;
          },
        ),
      ]);

    await runner.run([
      'build',
      '--output',
      'out/server',
      '--define',
      'FEATURE=enabled',
    ]);

    final generated = fileSystem.file(
      fileSystem.path.join(
        projectRoot.path,
        '.dart_tool/routed/server_cli_entrypoint.dart',
      ),
    );
    expect(generated.existsSync(), isTrue);
    final source = generated.readAsStringSync();
    expect(source, contains("import '../../lib/app.dart' as app;"));
    expect(
      source,
      contains("import '../../lib/commands.dart' as project_commands;"),
    );
    expect(source, contains('engine.container.get<CliCommandRegistry>()'));
    expect(source, contains("runner.run(const ['serve'])"));
    expect(source, contains('await Completer<void>().future;'));

    expect(executable, isNotNull);
    expect(arguments, contains('-DFEATURE=enabled'));
    expect(arguments, contains('.dart_tool/routed/server_cli_entrypoint.dart'));
    expect(arguments, contains('out/server'));
    expect(workingDirectory, equals(projectRoot.path));
    expect(
      fileSystem
          .directory(fileSystem.path.join(projectRoot.path, 'out'))
          .existsSync(),
      isTrue,
    );
  });

  test('supports the nested routed cli build spelling', () async {
    final fileSystem = MemoryFileSystem();
    final projectRoot = fileSystem.directory('/workspace/demo')
      ..createSync(recursive: true);
    fileSystem.currentDirectory = projectRoot;
    _write(fileSystem, projectRoot.path, 'pubspec.yaml', 'name: demo\n');
    _write(
      fileSystem,
      projectRoot.path,
      'lib/app.dart',
      'Future<void> createEngine() async {}\n',
    );

    var invoked = false;
    final runner = RoutedCommandRunner()
      ..register([
        BuildCommand(
          fileSystem: fileSystem,
          processRunner: (_, _, _) async {
            invoked = true;
            return 0;
          },
        ),
      ]);

    await runner.run(const ['cli', 'build']);
    expect(invoked, isTrue);
  });

  test('builds a Node.js entrypoint with the Node listener', () async {
    final fileSystem = MemoryFileSystem();
    final projectRoot = fileSystem.directory('/workspace/node_demo')
      ..createSync(recursive: true);
    fileSystem.currentDirectory = projectRoot;
    _write(fileSystem, projectRoot.path, 'pubspec.yaml', 'name: node_demo\n');
    _write(
      fileSystem,
      projectRoot.path,
      'lib/app.dart',
      '''
import 'package:routed_core/routed_core.dart';

Future<Engine> createEngine({bool initialize = true}) async {
  return Engine();
}
''',
    );

    List<String>? arguments;
    final runner = RoutedCommandRunner()
      ..register([
        BuildCommand(
          fileSystem: fileSystem,
          processRunner: (_, args, _) async {
            arguments = args;
            return 0;
          },
        ),
      ]);

    await runner.run(const ['build', '--target', 'node']);

    final generated = fileSystem.file(
      fileSystem.path.join(
        projectRoot.path,
        '.dart_tool/routed/node_server_cli_entrypoint.dart',
      ),
    );
    expect(generated.existsSync(), isTrue);
    final source = generated.readAsStringSync();
    expect(source, contains("import 'package:routed_node/node.dart';"));
    expect(source, contains('NodeRuntimeEnvironment.current()'));
    expect(source, contains('serveNode(engine, host: host, port: port)'));
    expect(source, contains('environment.arguments'));
    expect(source, contains('keepNodeEventLoopAlive(persistent: false)'));
    expect(source, isNot(contains("import 'dart:io';")));

    expect(arguments, contains('js'));
    expect(arguments, contains('-O2'));
    expect(arguments, contains('build/server.js'));
  });
}

void _write(
  MemoryFileSystem fileSystem,
  String root,
  String relativePath,
  String contents,
) {
  final file = fileSystem.file(fileSystem.path.join(root, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
