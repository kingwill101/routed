import 'dart:io';

import 'src/deployed_worker_auth_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runDeployedWorkerAuthConformanceCli(arguments);
}
