library;

import 'dart:io';

import 'package:artisanal/args.dart';

import 'create_command.dart';
import 'install_command.dart';
import 'ssr_check_command.dart';
import 'ssr_start_command.dart';
import 'ssr_stop_command.dart';

/// Implements the `inertia` command line interface.
///
/// ```dart
/// final cli = InertiaCli();
/// final exitCode = await cli.run(args);
/// ```
///
/// Command line interface for Inertia scaffolding and utilities.
class InertiaCli {
  /// Creates a CLI runner with optional output overrides.
  InertiaCli({
    StringSink? stdoutSink,
    StringSink? stderrSink,
    Directory? workingDirectory,
  }) : _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr,
       _workingDirectory = workingDirectory ?? Directory.current;

  final StringSink _stdout;
  final StringSink _stderr;
  final Directory _workingDirectory;

  /// The stdout sink used by the CLI.
  StringSink get stdoutSink => _stdout;

  /// The stderr sink used by the CLI.
  StringSink get stderrSink => _stderr;

  /// The working directory used by the CLI.
  Directory get workingDirectory => _workingDirectory;

  /// Runs the CLI with the provided [args] and returns an exit code.
  Future<int> run(List<String> args) async {
    if (args.isEmpty || _isHelp(args)) {
      _buildRunner().printUsage();
      return 0;
    }

    int? usageExitCode;
    final runner = _buildRunner(
      setExitCode: (code) {
        usageExitCode = code;
      },
    );

    try {
      final result = await runner.run(args);
      if (result != null) return result;
      return usageExitCode ?? 0;
    } catch (e) {
      _stderr.writeln('Failed to run command: $e');
      return 1;
    }
  }

  /// Returns `true` when [args] request help output.
  bool _isHelp(List<String> args) {
    return args.length == 1 && (args[0] == '--help' || args[0] == '-h');
  }

  /// Builds the command runner and registers subcommands.
  CommandRunner<int> _buildRunner({void Function(int code)? setExitCode}) {
    final runner = CommandRunner<int>(
      'inertia',
      'Inertia client installer and scaffolding tools.',
      usageExitCode: 64,
      out: (line) => _stdout.writeln(line),
      err: (line) => _stderr.writeln(line),
      setExitCode: setExitCode,
    );

    runner
      ..addCommand(InertiaCreateCommand(this))
      ..addCommand(InertiaInstallCommand(this))
      ..addCommand(InertiaSsrStartCommand(this))
      ..addCommand(InertiaSsrStopCommand())
      ..addCommand(InertiaSsrCheckCommand());
    return runner;
  }
}
