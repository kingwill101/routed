import 'package:routed_cli/src/console/args/commands/create.dart';
import 'package:routed_cli/src/console/args/commands/dev.dart';
import 'package:routed_cli/src/console/args/commands/deploy.dart';
import 'package:routed_cli/src/console/args/commands/routes.dart';
import 'package:routed_cli/src/console/args/commands/spec.dart';
import 'package:routed_cli/src/console/project/commands_loader.dart';
import 'package:routed_cli/src/console/args/runner.dart';

Future<void> main(List<String> args) async {
  final runner = RoutedCommandRunner()
    ..register([
      SpecGenerateCommand(),
      RoutesCommand(),
      CreateCommand(),
      DevCommand(),
      DeployCommand(),
    ]);
  final projectLoader = ProjectCommandsLoader(logger: runner.logger);
  if (shouldLoadProjectCommands(args, runner)) {
    final projectCommands = await projectLoader.loadProjectCommands(
      runner.usage,
    );
    projectLoader.registerWithRunner(runner, projectCommands, runner.usage);
  }
  await runner.run(args);
}
