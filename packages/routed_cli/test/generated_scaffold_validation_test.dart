import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:routed_cli/routed_cli.dart' show CliLogger;
import 'package:routed_cli/src/console/args/commands/create.dart';
import 'package:routed_cli/src/console/args/runner.dart';
import 'package:test/test.dart';

void main() {
  final workspaceRoot = _findWorkspaceRoot(Directory.current);
  final sourcePackageConfig = File(
    p.join(workspaceRoot.path, '.dart_tool', 'package_config.json'),
  );

  const cases = <({String name, String template, List<String> authPlugins})>[
    (name: 'basic', template: 'basic', authPlugins: []),
    (name: 'api', template: 'api', authPlugins: []),
    (name: 'web', template: 'web', authPlugins: []),
    (name: 'fullstack', template: 'fullstack', authPlugins: []),
    (name: 'username', template: 'basic', authPlugins: ['username']),
  ];

  for (final scaffoldCase in cases) {
    final name = scaffoldCase.name;
    final template = scaffoldCase.template;
    test(
      'generated $name project analyzes, compiles, and runs its manifest',
      () async {
        expect(sourcePackageConfig.existsSync(), isTrue);
        final sandbox = await Directory.systemTemp.createTemp(
          'routed_cli_$template.',
        );
        addTearDown(() => sandbox.delete(recursive: true));

        final packageName = 'generated_$template';
        final runner = RoutedCommandRunner(logger: _SilentLogger())
          ..register([
            CreateCommand(
              logger: _SilentLogger(),
              fileSystem: const LocalFileSystem(),
              pubGet: (_) async => 0,
            ),
          ]);
        await runner.run([
          'create',
          '--name',
          packageName,
          '--output',
          sandbox.path,
          '--template',
          template,
          for (final plugin in scaffoldCase.authPlugins) ...[
            '--auth-plugin',
            plugin,
          ],
        ]);

        final project = Directory(p.join(sandbox.path, packageName));
        await _installPackageConfig(
          source: sourcePackageConfig,
          project: project,
          packageName: packageName,
        );

        await _expectDartSuccess(
          ['analyze', '--fatal-infos', '.'],
          project,
          '$template analyzer',
        );
        await _expectDartSuccess(
          [
            'compile',
            'kernel',
            'bin/server.dart',
            '-o',
            p.join(project.path, '.dart_tool', 'server.dill'),
          ],
          project,
          '$template server compilation',
        );
        final manifest = await _expectDartSuccess(
          ['run', 'tool/spec_manifest.dart'],
          project,
          '$template manifest entrypoint',
        );
        expect(
          manifest.stdout.toString(),
          contains('"routes"'),
          reason: template,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Future<void> _installPackageConfig({
  required File source,
  required Directory project,
  required String packageName,
}) async {
  final decoded =
      jsonDecode(await source.readAsString()) as Map<String, Object?>;
  final packages = (decoded['packages']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((entry) {
        final copy = Map<String, Object?>.from(entry);
        copy['rootUri'] = source.uri
            .resolve(entry['rootUri']! as String)
            .toString();
        return copy;
      })
      .where((entry) => entry['name'] != packageName)
      .toList();
  packages.add({
    'name': packageName,
    'rootUri': project.uri.toString(),
    'packageUri': 'lib/',
    'languageVersion': '3.9',
  });

  final output = Map<String, Object?>.from(decoded)..['packages'] = packages;
  final destination = File(
    p.join(project.path, '.dart_tool', 'package_config.json'),
  );
  await destination.parent.create(recursive: true);
  await destination.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
}

Future<ProcessResult> _expectDartSuccess(
  List<String> arguments,
  Directory workingDirectory,
  String label,
) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  expect(
    result.exitCode,
    0,
    reason:
        '$label failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
  return result;
}

Directory _findWorkspaceRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('workspace:')) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Unable to find routed workspace root');
    }
    current = parent;
  }
}

final class _SilentLogger extends CliLogger {
  @override
  void info(Object? message) {}

  @override
  void warn(Object? message) {}

  @override
  void error(Object? message) {}

  @override
  void debug(Object? message) {}
}
