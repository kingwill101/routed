import 'dart:io';

import 'src/live_d1_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runLiveD1ConformanceCli(arguments);
}
