#!/usr/bin/env dart

import 'dart:io';

/// Main build script that runs all build tasks
void main(List<String> args) async {
  print('🏗️  Running class_view build tasks...');

  // Run template bundle generation
  print('\n📦 Building template bundle...');
  final result = await Process.run('dart', [
    'tool/build_templates.dart',
    '--output=lib/src/view/form/template_bundle.dart',
  ], workingDirectory: Directory.current.path);

  if (result.exitCode == 0) {
    print(result.stdout);
    print('✅ Build completed successfully!');
  } else {
    print('❌ Build failed:');
    print(result.stderr);
    exit(result.exitCode);
  }
}
