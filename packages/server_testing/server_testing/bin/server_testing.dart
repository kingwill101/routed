import 'dart:io';

import 'package:server_testing/src/cli/server_testing_cli.dart';

Future<void> main(List<String> args) async {
  final cli = ServerTestingCli();
  final exit = await cli.run(args);
  exitCode = exit;
}
