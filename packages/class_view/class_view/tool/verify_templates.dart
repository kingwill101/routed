#!/usr/bin/env dart

import 'dart:io';

/// Verification script to ensure the template bundle matches the current
/// Liquid templates. Intended for CI and publish checks.
Future<void> main() async {
  final result = await Process.run('dart', [
    'tool/build_templates.dart',
    '--output=lib/src/view/form/template_bundle.dart',
    '--check',
  ], workingDirectory: Directory.current.path);

  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    exit(result.exitCode);
  }
}
