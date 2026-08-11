import 'dart:io';

import 'package:{{{routed:packageName}}}/cli.dart' as app;

Future<void> main(List<String> args) async {
  exitCode = await app.runCli(args);
}
