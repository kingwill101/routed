import 'dart:async';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:routed/routed.dart' show registerRoutedProviders;
import 'package:routed_cli/routed_cli.dart';

/// Runs Routed commands with shared global flags and provider registration.
///
/// The runner registers Routed's built-in provider catalog in its constructor,
/// then provides global `--help` and `--version` handling. Add application
/// commands with [register] before calling [run]. The nested
/// `openapi generate` spelling is normalized to the legacy
/// `openapi:generate` command name.
///
/// ```dart
/// final runner = RoutedCommandRunner()
///   ..register(applicationCommands);
/// await runner.run(arguments);
/// ```
class RoutedCommandRunner extends CommandRunner<void> {
  /// Creates a command runner with the standard Routed global options.
  RoutedCommandRunner({
    String name = 'routed',
    String description = 'A fast, minimalistic backend framework for Dart.',
    CliLogger? logger,
  }) : logger = logger ?? CliLogger(),
       super(name, description) {
    // The CLI inspects and generates manifests outside the application
    // isolate, so register the same official providers as package:routed.
    registerRoutedProviders();

    // Global flags
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the current version.',
    );
  }

  /// Logger used for runner-level diagnostics and version output.
  final CliLogger logger;

  ArgResults? _globalResults;

  /// Registers [commands] and returns this runner for fluent composition.
  ///
  /// Command names and aliases must be unique according to the underlying
  /// [CommandRunner] contract.
  RoutedCommandRunner register(Iterable<Command<void>> commands) {
    commands.forEach(addCommand);
    // Fluent registration is part of the public runner API.
    // ignore: avoid_returning_this
    return this;
  }

  /// The top-level arguments parsed during the most recent [run] call.
  ArgResults? get globalResults => _globalResults;

  /// Handles global options before dispatching to a registered command.
  ///
  /// Passing `--help` prints runner usage, while `--version` resolves the
  /// version through [CliVersion]. Other arguments are delegated to the
  /// selected subcommand.
  @override
  Future<void> run(Iterable<String> args) async {
    // Accept the documented nested spelling while retaining the existing
    // colon-separated command names used by older projects.
    final normalizedArgs = args.toList(growable: false);
    final commandArgs =
        normalizedArgs.length >= 2 &&
            normalizedArgs[0] == 'openapi' &&
            normalizedArgs[1] == 'generate'
        ? <String>['openapi:generate', ...normalizedArgs.skip(2)]
        : normalizedArgs;

    // Parse top-level args first to support global flags (like --help/--version)
    final results = parse(commandArgs);

    _globalResults = results;

    // --help
    if (results['help'] == true) {
      _printTopLevelUsage();
      return;
    }

    // --version
    if (results['version'] == true) {
      final version = await CliVersion.resolve();
      stdout.writeln('$executableName $version');
      return;
    }

    // Delegate to subcommand
    return super.runCommand(results);
  }

  void _printTopLevelUsage() {
    // Show description header (if provided) followed by usage.
    if (description.isNotEmpty) {
      stdout
        ..writeln(description)
        ..writeln();
    }
    stdout.writeln(usage);
  }
}
