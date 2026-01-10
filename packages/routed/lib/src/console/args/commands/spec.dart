import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed/console.dart';
import 'package:routed/src/console/args/base_command.dart';
import 'package:routed/src/console/engine/introspector.dart';

class SpecGenerateCommand extends BaseCommand {
  SpecGenerateCommand({
    super.logger,
    super.fileSystem,
    ManifestLoaderFactory? loaderFactory,
  }) : _loaderFactory = loaderFactory ?? _defaultLoaderFactory {
    argParser
      ..addOption(
        'entry',
        help: 'Optional Dart entrypoint that prints a route manifest as JSON.',
        valueHelp: 'tool/spec_manifest.dart',
      )
      ..addOption(
        'output',
        help:
            'Target path for the generated manifest (relative to project root).',
        valueHelp: 'file',
        defaultsTo: this.fileSystem.path.join(
          '.dart_tool',
          'routed',
          'route_manifest.json',
        ),
      )
      ..addFlag(
        'pretty',
        help: 'Pretty-print the JSON output.',
        defaultsTo: true,
      );
  }

  @override
  String get name => 'spec:generate';

  @override
  List<String> get aliases => const ['spec'];

  @override
  String get description => 'Generates a route/spec manifest.';

  @override
  String get category => 'Specification';

  final ManifestLoaderFactory _loaderFactory;

  static ManifestLoader _defaultLoaderFactory(
    fs.Directory projectRoot,
    CliLogger logger,
    String usage,
    fs.FileSystem fileSystem,
  ) {
    return ManifestLoader(
      projectRoot: projectRoot,
      logger: logger,
      usage: usage,
      fileSystem: fileSystem,
    );
  }

  @override
  Future<void> run() async {
    return guarded(() async {
      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        throw UsageException(
          'Could not locate a pubspec.yaml in the current directory.',
          usage,
        );
      }

      final outputArg = results?['output'] as String?;
      final outputPath = outputArg == null || outputArg.isEmpty
          ? fileSystem.path.join('.dart_tool', 'routed', 'route_manifest.json')
          : outputArg;
      final manifestFile = fileSystem.file(
        joinPath([projectRoot.path, outputPath]),
      );

      await ensureDir(manifestFile.parent);

      final loader = _loaderFactory(projectRoot, logger, usage, fileSystem);

      final manifestResult = await loader.load(
        entry: results?['entry'] as String?,
      );

      final pretty = results?['pretty'] as bool? ?? true;
      final encoder = pretty
          ? const JsonEncoder.withIndent('  ')
          : const JsonEncoder();

      await manifestFile.writeAsString(
        encoder.convert(manifestResult.manifest),
      );

      logger.info(
        'Wrote manifest to '
        '${p.relative(manifestFile.path, from: projectRoot.path)}',
      );
      if (manifestResult.source == ManifestSource.app) {
        logger.info('Used application engine: lib/app.dart');
      } else {
        logger.info(
          'Used manifest entrypoint: ${manifestResult.sourceDescription}',
        );
      }
    });
  }
}
