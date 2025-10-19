import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:routed_cli/routed_cli.dart' as rc;

/// RoutedCommandRunner centralizes global flags and command registration.
///
/// - Provides global `--help` and `--version` flags.
/// - Centralizes command registration so the bin entrypoint can be minimal.
/// - Uses [rc.CliVersion] to resolve and print the CLI version.
///
/// Usage:
///   final runner = RoutedCommandRunner();
///   runner.register([DevCommand(), BuildCommand(), ...]);
///   await runner.run(args);
class RoutedCommandRunner extends CommandRunner<void> {
  RoutedCommandRunner({
    String name = 'routed',
    String description = 'A fast, minimalistic backend framework for Dart.',
    rc.CliLogger? logger,
  }) : logger = logger ?? rc.CliLogger(),
       super(name, description) {
    // Global flags
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the current version.',
    );
  }

  /// Logger for runner-level output.
  final rc.CliLogger logger;

  ArgResults? _globalResults;

  /// Register multiple commands at once.
  RoutedCommandRunner register(Iterable<Command<void>> commands) {
    for (final cmd in commands) {
      addCommand(cmd);
    }
    return this;
  }

  /// Convenience accessor to the parsed [ArgResults] for subcommands.
  ArgResults? get globalResults => _globalResults;

  @override
  Future<void> run(Iterable<String> args) async {
    // Parse top-level args first to support global flags (like --help/--version)
    final results = parse(args);

    _globalResults = results;

    // --help
    if (results['help'] == true) {
      _printTopLevelUsage();
      return;
    }

    // --version
    if (results['version'] == true) {
      final version = await rc.CliVersion.resolve();
      stdout.writeln('$executableName $version');
      return;
    }

    // Delegate to subcommand
    return super.runCommand(results);
  }

  void _printTopLevelUsage() {
    // Show description header (if provided) followed by usage.
    if (description.isNotEmpty) {
      stdout.writeln(description);
      stdout.writeln();
    }
    stdout.writeln(usage);
  }
}
