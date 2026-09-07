import 'dart:async';
import 'dart:io' as io;

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;
import 'package:routed_cli/src/console/args/base_command.dart';
import 'package:routed_cli/src/console/util/dart_exec.dart';
import 'package:routed_cli/src/console/util/pubspec.dart';

/// Runs the Dart compiler for the generated server entrypoint.
typedef BuildProcessRunner =
    Future<int> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

enum _BuildTarget { native, node }

/// Builds a self-contained Routed server executable or Node.js bundle.
///
/// The generated entrypoint boots the application's normal `createEngine()`
/// composition, provisions provider-owned CLI commands from
/// `CliCommandRegistry`, and loads `lib/commands.dart` when present. With no
/// arguments the resulting binary serves HTTP; with a command argument it
/// runs that command using the same engine:
///
/// ```text
/// routed build
/// ./build/server
/// ./build/server schedule:work
/// routed build --target node
/// node ./build/server.js
/// ```
final class BuildCommand extends BaseCommand {
  /// Creates a build command.
  BuildCommand({
    super.logger,
    super.fileSystem,
    BuildProcessRunner? processRunner,
  }) : _processRunner = processRunner ?? _runBuildProcess {
    argParser
      ..addOption(
        'target',
        help: 'Build target.',
        valueHelp: 'native|node',
        allowed: const ['native', 'node'],
        defaultsTo: 'native',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output path for the server artifact.',
        valueHelp: 'file',
        defaultsTo: 'build/server',
      )
      ..addOption(
        'entry',
        help: 'Application entrypoint containing createEngine().',
        valueHelp: 'path/to/app.dart',
        defaultsTo: 'lib/app.dart',
      )
      ..addMultiOption(
        'define',
        help: 'Compile-time environment declaration. Use NAME=VALUE.',
        valueHelp: 'NAME=VALUE',
      );
  }

  final BuildProcessRunner _processRunner;

  @override
  String get name => 'build';

  @override
  List<String> get aliases => const ['cli:build'];

  @override
  String get description => 'Build a native or Node.js Routed server.';

  @override
  String get category => 'Build';

  @override
  Future<void> run() {
    return guarded(() async {
      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        throw UsageException(
          'Could not locate a pubspec.yaml in the current directory.',
          usage,
        );
      }

      final packageName = await readPackageName(projectRoot);
      if (packageName == null) {
        throw UsageException(
          'Could not read a package name from pubspec.yaml.',
          usage,
        );
      }

      final appEntry = results?['entry'] as String? ?? 'lib/app.dart';
      final normalizedEntry = p.normalize(appEntry);
      if (p.isAbsolute(normalizedEntry) ||
          normalizedEntry == '..' ||
          normalizedEntry.startsWith('..${p.separator}')) {
        throw UsageException(
          'The application entrypoint must be inside the project root.',
          usage,
        );
      }
      final appFile = projectRoot.fileSystem.file(
        p.join(projectRoot.path, normalizedEntry),
      );
      if (!appFile.existsSync()) {
        throw UsageException(
          'Application entrypoint not found: $appEntry',
          usage,
        );
      }
      if (!_hasCreateEngine(appFile.readAsStringSync())) {
        throw UsageException(
          'Application entrypoint must export createEngine().',
          usage,
        );
      }

      final target = _target;
      final outputWasParsed = results?.wasParsed('output') ?? false;
      final requestedOutput = outputWasParsed
          ? (results?['output'] as String?)
          : null;
      final outputArg =
          requestedOutput ??
          (target == _BuildTarget.node
              ? p.join('build', 'server.js')
              : p.join('build', 'server'));
      final outputPath = p.isAbsolute(outputArg)
          ? outputArg
          : p.normalize(outputArg);
      final outputFile = projectRoot.fileSystem.file(
        p.isAbsolute(outputPath)
            ? outputPath
            : p.join(projectRoot.path, outputPath),
      );
      await outputFile.parent.create(recursive: true);

      final generatedEntrypoint = projectRoot.fileSystem.file(
        p.join(
          '.dart_tool',
          'routed',
          target == _BuildTarget.node
              ? 'node_server_cli_entrypoint.dart'
              : 'server_cli_entrypoint.dart',
        ),
      );
      final generatedEntrypointPath = p.join(
        '.dart_tool',
        'routed',
        target == _BuildTarget.node
            ? 'node_server_cli_entrypoint.dart'
            : 'server_cli_entrypoint.dart',
      );
      await generatedEntrypoint.parent.create(recursive: true);
      await generatedEntrypoint.writeAsString(
        _buildEntrypoint(
          packageName: packageName,
          appImportPath: '../../${normalizedEntry.replaceAll(r'\', '/')}',
          target: target,
          includeProjectCommands: projectRoot.fileSystem
              .file(p.join(projectRoot.path, 'lib', 'commands.dart'))
              .existsSync(),
        ),
      );

      final compiler = target == _BuildTarget.node ? 'js' : 'exe';
      final arguments = <String>[
        'compile',
        compiler,
        ..._defines,
        generatedEntrypointPath,
        '-o',
        outputPath,
        if (target == _BuildTarget.node) '-O2',
      ];
      final targetLabel = target == _BuildTarget.node ? 'Node.js' : 'native';
      logger.info('Building $outputPath ($targetLabel)...');
      final exitCode = await _processRunner(
        resolveDartExecutable(),
        arguments,
        projectRoot.path,
      );
      if (exitCode != 0) {
        throw StateError('Dart build compiler exited with code $exitCode.');
      }
      logger.info('Built $outputPath');
    });
  }

  List<String> get _defines {
    final values = results?['define'] as List<String>? ?? const <String>[];
    return values.map((value) => '-D$value').toList(growable: false);
  }

  _BuildTarget get _target {
    return switch (results?['target'] as String? ?? 'native') {
      'node' => _BuildTarget.node,
      _ => _BuildTarget.native,
    };
  }

  bool _hasCreateEngine(String source) {
    return RegExp(
      r'^\s*(?:Future(?:<[^>]+>)?|Engine)\s+createEngine\s*\(',
      multiLine: true,
    ).hasMatch(source);
  }

  String _buildEntrypoint({
    required String packageName,
    required String appImportPath,
    required _BuildTarget target,
    required bool includeProjectCommands,
  }) {
    final isNode = target == _BuildTarget.node;
    final runtimeImport = isNode
        ? "import 'dart:async';\nimport 'package:routed_node/node.dart';\n"
        : '';
    final environmentExpression = isNode
        ? 'NodeRuntimeEnvironment.current()'
        : 'RuntimeEnvironment(readProcessEnvironment(), '
              'isWindows: hostIsWindows)';
    final hostDefault = isNode
        ? "environment.string('HOST') ?? '0.0.0.0'"
        : "environment.string('HOST') ?? '127.0.0.1'";
    final portDefault = isNode
        ? "environment.string('PORT') ?? '8080'"
        : "environment.string('PORT') ?? '8080'";
    final serveBody = isNode
        ? '''
    await serveNode(engine, host: host, port: port);
    await Completer<void>().future;
'''
        : '''
    await engine.serve(host: host, port: port);
''';
    final projectImport = includeProjectCommands
        ? "import '../../lib/commands.dart' as project_commands;\n"
        : '';
    final projectLoader = includeProjectCommands
        ? r'''
  final projectCommands = await Future.sync(
    project_commands.buildProjectCommands,
  );
  for (final command in projectCommands) {
    if (command is! Command<void>) {
      throw StateError(
        'buildProjectCommands() returned ${command.runtimeType}, '
        'expected Command<void>.',
      );
    }
    _addCommand(commands, command);
  }
'''
        : '';

    return '''
// Generated by routed build. Do not edit by hand.

import 'package:artisanal/args.dart';
import 'package:routed_core/routed_core.dart';
${runtimeImport}import '$appImportPath' as app;
$projectImport
Future<void> main(List<String> args) async {
${isNode ? '  keepNodeEventLoopAlive(persistent: false);\n' : ''}  final environment = $environmentExpression;
  final commandArgs = ${isNode ? 'environment.arguments' : 'args'};
  final engine = await app.createEngine();
  try {
    final commands = <Command<void>>[ServeCommand(engine, environment)];
    final registry = engine.container.get<CliCommandRegistry>();
    for (final registration in registry.registrations) {
      final command = registration.factory(engine.container);
      if (command is! Command<void>) {
        throw StateError(
          'CLI command registration "\${registration.id}" returned '
          '\${command.runtimeType}, expected Command<void>.',
        );
      }
      _addCommand(commands, command);
    }
$projectLoader
    final runner = CommandRunner<void>(
      '$packageName',
      'Routed server and application commands.',
    );
    for (final command in commands) {
      runner.addCommand(command);
    }
    if (commandArgs.isEmpty) {
      await runner.run(const ['serve']);
    } else {
      await runner.run(commandArgs);
    }
  } finally {
    await engine.close();
  }
}

void _addCommand(List<Command<void>> commands, Command<void> command) {
  final names = commands
      .expand((value) => <String>[value.name, ...value.aliases])
      .toSet();
  if (names.contains(command.name) ||
      command.aliases.any(names.contains)) {
    throw StateError(
      'Command "\${command.name}" is registered more than once.',
    );
  }
  commands.add(command);
}

final class ServeCommand extends Command<void> {
  ServeCommand(this.engine, this.environment) {
    argParser
      ..addOption(
        'host',
        help: 'Host to bind the HTTP server.',
        defaultsTo: $hostDefault,
      )
      ..addOption(
        'port',
        help: 'Port to bind the HTTP server.',
        defaultsTo: $portDefault,
      );
  }

  final Engine engine;
  final RuntimeEnvironment environment;

  @override
  String get name => 'serve';

  @override
  String get description => 'Start the HTTP server.';

  @override
  Future<void> run() async {
    final host = argResults?['host'] as String? ?? $hostDefault;
    final port = int.tryParse(argResults?['port'] as String? ?? $portDefault);
    if (port == null || port <= 0) {
      throw UsageException('Port must be a positive integer.', usage);
    }
$serveBody
  }
}
''';
  }
}

Future<int> _runBuildProcess(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final process = await io.Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  await Future.wait([
    io.stdout.addStream(process.stdout),
    io.stderr.addStream(process.stderr),
  ]);
  return process.exitCode;
}
