import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed_cli/routed_cli.dart' show CliLogger;

import 'package:routed_cli/src/console/util/dart_exec.dart';
import 'package:routed_cli/src/console/util/pubspec.dart';

/// Source used to produce a route manifest.
enum ManifestSource {
  /// The application's `lib/app.dart` engine factory.
  app,

  /// An explicitly selected or discovered manifest entrypoint.
  entry,
}

/// A route manifest together with information about how it was loaded.
class ManifestLoadResult {
  /// Creates a manifest-load result.
  ManifestLoadResult({
    required this.manifest,
    required this.source,
    required this.sourceDescription,
  });

  /// Decoded route manifest data.
  final Map<String, Object?> manifest;

  /// Source category that produced [manifest].
  final ManifestSource source;

  /// Human-readable source path or description.
  final String sourceDescription;
}

/// Creates a manifest loader for a project root.
typedef ManifestLoaderFactory =
    ManifestLoader Function(
      fs.Directory projectRoot,
      CliLogger logger,
      String usage,
      fs.FileSystem fileSystem,
    );

/// Loads route manifests from a Routed application or standalone entrypoint.
class ManifestLoader {
  /// Creates a loader rooted at [projectRoot].
  ManifestLoader({
    required this.projectRoot,
    required this.logger,
    required this.usage,
    fs.FileSystem? fileSystem,
  }) : fileSystem = fileSystem ?? projectRoot.fileSystem;

  /// Project directory used for entrypoint discovery and process execution.
  final fs.Directory projectRoot;

  /// Logger used for process diagnostics.
  final CliLogger logger;

  /// Usage text attached to loader failures.
  final String usage;

  /// Filesystem abstraction used for project inspection.
  final fs.FileSystem fileSystem;

  /// Loads a manifest, optionally using [entry] as the entrypoint.
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
      'Provide --entry <path> or ensure your application exposes '
      'createEngine().',
      usage,
    );
  }

  Future<Map<String, Object?>?> _runApp() async {
    final appFile = fileSystem.file(
      p.join(projectRoot.path, 'lib', 'app.dart'),
    );
    if (!appFile.existsSync()) {
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

import 'package:routed_core/routed_core.dart';
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
    if (!entryFile.existsSync()) {
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

    final rawOutput = stdoutBuffer.toString().trim();
    if (rawOutput.isEmpty) {
      throw UsageException('Manifest entrypoint produced no output.', usage);
    }

    // Applications may emit harmless startup diagnostics to stdout. The
    // manifest contract is the JSON object in the output; tolerate those
    // diagnostics while still requiring a valid JSON manifest.
    final jsonStart = rawOutput.indexOf('{');
    final output = jsonStart == -1 ? rawOutput : rawOutput.substring(jsonStart);

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
