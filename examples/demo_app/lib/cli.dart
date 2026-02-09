import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:routed/routed.dart';
import 'package:demo_app/app.dart' as app;
import 'package:demo_app/commands.dart' as project_commands;

Future<int> runCli(List<String> args) async {
  await app.createEngine(initialize: false);

  final runner = CommandRunner<void>(
    'demo_app',
    'Command line interface for Demo App.',
  );

  runner.addCommand(ServeCommand());

  final projectCommands = await _loadProjectCommands();
  for (final command in projectCommands) {
    runner.addCommand(command);
  }

  if (args.isEmpty || _isHelp(args)) {
    stdout.writeln(runner.usage);
    return 0;
  }

  try {
    await runner.run(args);
    return 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    return 64;
  } catch (error, stack) {
    stderr
      ..writeln('Unhandled error: $error')
      ..writeln(stack);
    return 70;
  }
}

class ServeCommand extends Command<void> {
  ServeCommand()
    : _defaultHost = Platform.environment['HOST'] ?? '127.0.0.1',
      _defaultPort = Platform.environment['PORT'] ?? '8080' {
    argParser
      ..addOption(
        'host',
        help: 'Host to bind the HTTP server.',
        defaultsTo: _defaultHost,
      )
      ..addOption(
        'port',
        help: 'Port to bind the HTTP server.',
        defaultsTo: _defaultPort,
      );
  }

  final String _defaultHost;
  final String _defaultPort;

  @override
  String get name => 'serve';

  @override
  String get description => 'Start the HTTP server.';

  @override
  Future<void> run() async {
    final host = (argResults?['host'] as String?)?.trim() ?? _defaultHost;
    final portText = argResults?['port'] as String? ?? _defaultPort;
    final port = int.tryParse(portText);
    if (host.isEmpty) {
      throw UsageException('Host must be provided.', usage);
    }
    if (port == null || port <= 0) {
      throw UsageException('Port must be a positive integer.', usage);
    }

    final engine = await app.createEngine();
    await engine.serve(host: host, port: port);
  }
}

bool _isHelp(List<String> args) {
  return args.length == 1 && (args[0] == '--help' || args[0] == '-h');
}

Future<List<Command<void>>> _loadProjectCommands() async {
  final result = await Future.sync(project_commands.buildProjectCommands);
  return List<Command<void>>.from(result);
}
