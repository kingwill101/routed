import 'package:routed_cli/src/console/args/commands/create.dart';
import 'package:routed_cli/src/console/args/commands/dev.dart';
import 'package:routed_cli/src/console/args/commands/deploy.dart';
import 'package:routed_cli/src/console/args/commands/routes.dart';
import 'package:routed_cli/src/console/args/commands/spec.dart';
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
  await runner.run(args);
}
