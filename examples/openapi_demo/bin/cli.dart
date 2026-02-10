import 'dart:io';

import 'package:openapi_demo/cli.dart' as app;

Future<void> main(List<String> args) async {
  exitCode = await app.runCli(args);
}
