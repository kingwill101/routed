library;

import 'dart:io';

import 'package:inertia_dart/src/cli/inertia_cli.dart';

/// Entry point for the `inertia` command line tool.
///
/// ```bash
/// dart run inertia_dart:inertia --help
/// ```
///
/// Runs the CLI and exits with the returned status code.
Future<void> main(List<String> args) async {
  final cli = InertiaCli();
  final code = await cli.run(args);
  if (code != 0) {
    exitCode = code;
  }
}
