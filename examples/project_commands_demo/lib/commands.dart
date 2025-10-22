import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:project_commands_demo/app.dart' as app;
import 'package:routed/routed.dart';

class DumpRoutesCommand extends Command<void> {
  DumpRoutesCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'File path where the route manifest should be written.',
        defaultsTo: 'build/routes.json',
      )
      ..addFlag(
        'pretty',
        help: 'Pretty print the generated JSON file.',
        defaultsTo: true,
      );
  }

  @override
  String get name => 'routes:dump';

  @override
  String get description =>
      'Build the application and dump the route manifest as JSON. Useful for tooling or docs.';

  @override
  String get summary => 'Dump the current route manifest to disk.';

  @override
  String get category => 'Project';

  @override
  Future<void> run() async {
    final output = argResults?.option('output') ?? 'build/routes.json';
    final pretty = argResults?.flag('pretty') ?? true;

    final engine = await app.createEngine();
    final manifest = engine.buildRouteManifest();
    await engine.close();

    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();

    final file = File(output);
    await file.parent.create(recursive: true);
    await file.writeAsString(encoder.convert(manifest.toJson()));

    stdout.writeln('Route manifest written to $output');
  }
}

class GreetCommand extends Command<void> {
  GreetCommand() {
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'Person or team to greet.',
      defaultsTo: 'Routed developer',
    );
  }

  @override
  String get name => 'demo:greet';

  @override
  String get description =>
      'Simple example command that shows how to parse arguments and produce output.';

  @override
  String get summary => 'Print a greeting from the project.';

  @override
  String get category => 'Project';

  @override
  Future<void> run() async {
    final target = argResults?.option('name') ?? 'Routed developer';
    stdout.writeln('Hello, $target! 👋');
  }
}

FutureOr<List<Command<void>>> buildProjectCommands() {
  return [DumpRoutesCommand(), GreetCommand()];
}
