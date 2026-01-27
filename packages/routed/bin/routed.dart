import 'dart:io';

import 'package:artisanal/args.dart' show UsageException;
import 'package:routed/console.dart';
import 'package:routed/src/console/args/commands.dart' as cmds;
import 'package:routed/src/console/args/runner.dart';
import 'package:routed/src/console/project/commands_loader.dart';

Future<void> main(List<String> args) async {
  final logger = CliLogger();
  final runner = RoutedCommandRunner(logger: logger)
    ..register([
      cmds.CreateCommand(),
      cmds.DevCommand(),
      cmds.ConfigInitCommand(),
      cmds.ConfigPublishCommand(),
      cmds.ConfigCacheCommand(),
      cmds.ConfigSchemaCommand(),
      cmds.ConfigClearCommand(),
      cmds.RoutesCommand(),
      cmds.OpenApiCommand(),
      cmds.SpecGenerateCommand(),
      cmds.ProviderListCommand(),
      cmds.ProviderEnableCommand(),
      cmds.ProviderDisableCommand(),
      cmds.ProviderDriverCommand(),
      cmds.StimulusInstallCommand(),
    ]);

  final commandsLoader = ProjectCommandsLoader(logger: logger);

  try {
    final projectCommands = await commandsLoader.loadProjectCommands(
      runner.usage,
    );
    commandsLoader.registerWithRunner(runner, projectCommands, runner.usage);

    registerProviderCommands(
      runner,
      ProviderCommandRegistry.instance.registrations,
      runner.usage,
    );

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
