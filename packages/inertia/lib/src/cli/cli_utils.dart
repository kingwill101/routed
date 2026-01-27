library;

import 'dart:io';

import 'package:artisanal/artisanal.dart';
import 'package:path/path.dart' as p;

import 'framework.dart';
import 'templates.dart';

/// Runs an external command and returns a [TaskResult].
///
/// Side effects: spawns a process in [workingDirectory].
Future<TaskResult> runInertiaCommand(
  String executable,
  List<String> args, {
  required Directory workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory.path,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  return exitCode == 0 ? TaskResult.success : TaskResult.failure;
}

/// Utility helpers for CLI project scaffolding.
///
/// ```dart
/// await configureInertiaProject(dir, framework);
/// ```
///
/// Writes the framework templates into [projectDir].
///
/// Side effects: creates and updates files under [projectDir].
Future<void> configureInertiaProject(
  Directory projectDir,
  InertiaFramework framework,
) async {
  final configFile = File(p.join(projectDir.path, 'vite.config.js'));
  await configFile.writeAsString(framework.configTemplate);

  final hotFile = File(p.join(projectDir.path, 'inertia_hot_file.js'));
  await hotFile.writeAsString(inertiaHotFilePlugin);

  final mainFile = File(p.join(projectDir.path, framework.mainFile));
  await mainFile.create(recursive: true);
  await mainFile.writeAsString(framework.mainTemplate);

  final ssrFile = File(p.join(projectDir.path, framework.ssrFile));
  await ssrFile.create(recursive: true);
  await ssrFile.writeAsString(framework.ssrTemplate);

  final pageFile = File(p.join(projectDir.path, framework.pageFile));
  await pageFile.create(recursive: true);
  await pageFile.writeAsString(framework.pageTemplate);

  final indexFile = File(p.join(projectDir.path, 'index.html'));
  if (await indexFile.exists()) {
    final html = await indexFile.readAsString();
    var updated = html.replaceAll('id="root"', 'id="app"');
    updated = updated.replaceAll("id='root'", "id='app'");
    await indexFile.writeAsString(updated);
  }
}
