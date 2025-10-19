import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:routed_cli/src/args/commands.dart' as cmds;
import 'package:routed_cli/src/args/runner.dart' as cli;

Future<void> main(List<String> args) async {
  final runner = cli.RoutedCommandRunner()
    ..register([
      cmds.CreateCommand(),
      cmds.DevCommand(),
      cmds.ConfigInitCommand(),
      cmds.ConfigPublishCommand(),
      cmds.ConfigCacheCommand(),
      cmds.ConfigClearCommand(),
      cmds.RoutesCommand(),
      cmds.OpenApiCommand(),
      cmds.SpecGenerateCommand(),
      cmds.ProviderListCommand(),
      cmds.ProviderEnableCommand(),
      cmds.ProviderDisableCommand(),
      cmds.ProviderDriverCommand(),
    ]);

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = ExitCode.usage.code;
  } catch (e, st) {
    stderr
      ..writeln('Unhandled error: $e')
      ..writeln(st);
    exitCode = ExitCode.software.code;
  }
}

/// Common exit codes used by the CLI entrypoint.
class ExitCode {
  final int code;

  const ExitCode._(this.code);

  static const usage = ExitCode._(64);
  static const software = ExitCode._(70);
}
