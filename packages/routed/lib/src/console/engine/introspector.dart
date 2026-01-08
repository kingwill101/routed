import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed/console.dart' show CliLogger;

import '../util/dart_exec.dart';
import '../util/pubspec.dart';

enum ManifestSource { app, entry }

class ManifestLoadResult {
  ManifestLoadResult({
    required this.manifest,
    required this.source,
    required this.sourceDescription,
  });

  final Map<String, Object?> manifest;
  final ManifestSource source;
  final String sourceDescription;
}

typedef ManifestLoaderFactory =
    ManifestLoader Function(
      fs.Directory projectRoot,
      CliLogger logger,
      String usage,
      fs.FileSystem fileSystem,
    );

class ManifestLoader {
  ManifestLoader({
    required this.projectRoot,
    required this.logger,
    required this.usage,
    fs.FileSystem? fileSystem,
  }) : fileSystem = fileSystem ?? projectRoot.fileSystem;

  final fs.Directory projectRoot;
  final CliLogger logger;
  final String usage;
  final fs.FileSystem fileSystem;

  Future<ManifestLoadResult> load({String? entry}) async {
    if (entry != null && entry.isNotEmpty) {
      final manifest = await _runEntry(entry);
      return ManifestLoadResult(
        manifest: manifest,
        source: ManifestSource.entry,
        sourceDescription: entry,
      );
    }

    final appManifest = await _runApp();
    if (appManifest != null) {
      return ManifestLoadResult(
        manifest: appManifest,
        source: ManifestSource.app,
        sourceDescription: 'lib/app.dart',
      );
    }

    final defaultEntry = _resolveDefaultEntry();
    if (defaultEntry != null) {
      final manifest = await _runEntry(defaultEntry);
      return ManifestLoadResult(
        manifest: manifest,
        source: ManifestSource.entry,
        sourceDescription: defaultEntry,
      );
    }

    throw UsageException(
      'Unable to locate lib/app.dart or tool/spec_manifest.dart. '
      'Provide --entry <path> or ensure your application exposes createEngine().',
      usage,
    );
  }

  Future<Map<String, Object?>?> _runApp() async {
    final appFile = fileSystem.file(
      p.join(projectRoot.path, 'lib', 'app.dart'),
    );
    if (!await appFile.exists()) {
      return null;
    }

    final packageName = await readPackageName(projectRoot);
    if (packageName == null || packageName.isEmpty) {
      return null;
    }

    final scriptRelativePath = p.join(
      '.dart_tool',
      'routed',
      'introspect_manifest.dart',
    );
    final scriptFile = fileSystem.file(
      p.join(projectRoot.path, scriptRelativePath),
    );
    await scriptFile.parent.create(recursive: true);

    final rootLiteral = jsonEncode(projectRoot.path);
    final scriptContents =
        '''
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:$packageName/app.dart' as app;

Future<void> main(List<String> args) async {
  Directory.current = Directory($rootLiteral);
  final engine = await app.createEngine();
  final manifest = engine.buildRouteManifest();
  print(jsonEncode(manifest.toJson()));
}
''';

    await scriptFile.writeAsString(scriptContents);
    return _runEntry(scriptRelativePath);
  }

  String? _resolveDefaultEntry() {
    final candidate = p.join(projectRoot.path, 'tool', 'spec_manifest.dart');
    if (fileSystem.file(candidate).existsSync()) {
      return p.join('tool', 'spec_manifest.dart');
    }
    return null;
  }

  Future<Map<String, Object?>> _runEntry(String entry) async {
    final entryFile = fileSystem.file(p.join(projectRoot.path, entry));
    if (!await entryFile.exists()) {
      throw UsageException('Manifest entrypoint not found: $entry', usage);
    }

    logger.debug('Running manifest entrypoint: dart run $entry');

    final process = await startDartProcess([
      'run',
      entry,
    ], workingDirectory: projectRoot.path);

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .listen(stdoutBuffer.write);
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write);

    final exitCode = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();

    if (exitCode != 0) {
      final message = stderrBuffer.isEmpty
          ? 'Manifest entrypoint exited with code $exitCode.'
          : stderrBuffer.toString();
      throw UsageException(message.trim(), usage);
    }

    final output = stdoutBuffer.toString().trim();
    if (output.isEmpty) {
      throw UsageException('Manifest entrypoint produced no output.', usage);
    }

    try {
      final decoded = jsonDecode(output);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      throw const FormatException('Manifest output must be a JSON object.');
    } on FormatException catch (e) {
      throw UsageException(
        'Failed to parse manifest JSON: ${e.message}',
        usage,
      );
    }
  }
}
