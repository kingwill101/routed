import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart' as routed;
import 'package:routed_cli/routed_cli.dart' as rc;
import 'package:routed_cli/src/args/base_command.dart';
import 'package:routed_cli/src/engine/introspector.dart';

class OpenApiCommand extends Command<void> {
  OpenApiCommand({
    rc.CliLogger? logger,
    fs.FileSystem? fileSystem,
    ManifestLoaderFactory? loaderFactory,
  }) {
    addSubcommand(
      OpenApiGenerateCommand(
        logger: logger,
        fileSystem: fileSystem,
        loaderFactory: loaderFactory,
      ),
    );
  }

  @override
  String get name => 'openapi';

  @override
  String get description => 'OpenAPI tooling for Routed applications.';

  @override
  Future<void> run() async {
    throw UsageException('Specify a subcommand.', usage);
  }
}

class OpenApiGenerateCommand extends BaseCommand {
  OpenApiGenerateCommand({
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
        help: 'Target path for the generated OpenAPI document.',
        defaultsTo: p.join('.dart_tool', 'routed', 'openapi.json'),
        valueHelp: 'file',
      )
      ..addOption(
        'title',
        help: 'OpenAPI info.title value.',
        defaultsTo: 'Routed Service',
      )
      ..addOption(
        'version',
        help: 'OpenAPI info.version value.',
        defaultsTo: '1.0.0',
      )
      ..addOption('description', help: 'OpenAPI info.description value.')
      ..addMultiOption(
        'server',
        help:
            'Server URL(s) to include. Format: url or url|Description. Repeat to add multiple servers.',
        valueHelp: 'url[|description]',
      )
      ..addFlag(
        'pretty',
        help: 'Pretty-print the JSON output.',
        defaultsTo: true,
      );
  }

  final ManifestLoaderFactory _loaderFactory;

  static ManifestLoader _defaultLoaderFactory(
    fs.Directory projectRoot,
    rc.CliLogger logger,
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
  String get name => 'generate';

  @override
  String get description =>
      'Generate an OpenAPI document from the route graph.';

  @override
  String get category => 'Specification';

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

      final loader = _loaderFactory(projectRoot, logger, usage, fileSystem);
      final manifestResult = await loader.load(
        entry: results?['entry'] as String?,
      );

      final manifest = routed.RouteManifest.fromJson(manifestResult.manifest);

      final info = routed.OpenApiDocumentInfo(
        title: (results?['title'] as String?)?.trim().isNotEmpty == true
            ? (results?['title'] as String).trim()
            : 'Routed Service',
        version: (results?['version'] as String?)?.trim().isNotEmpty == true
            ? (results?['version'] as String).trim()
            : '1.0.0',
        description:
            (results?['description'] as String?)?.trim().isNotEmpty == true
            ? (results?['description'] as String).trim()
            : null,
      );

      final servers = <routed.OpenApiServer>[];
      final serverArgs = results?['server'] as List<String>? ?? const [];
      for (final raw in serverArgs) {
        final parts = raw.split('|');
        if (parts.isEmpty) continue;
        final url = parts.first.trim();
        if (url.isEmpty) continue;
        String? description;
        if (parts.length > 1) {
          description = parts.sublist(1).join('|').trim();
          if (description.isEmpty) {
            description = null;
          }
        }
        servers.add(routed.OpenApiServer(url: url, description: description));
      }

      final document = routed.generateOpenApiDocument(
        manifest,
        info: info,
        servers: servers,
      );

      final outputArg =
          results?['output'] as String? ??
          p.join('.dart_tool', 'routed', 'openapi.json');
      final outputFile = fileSystem.file(
        joinPath([projectRoot.path, outputArg]),
      );
      await ensureDir(outputFile.parent);

      final pretty = results?['pretty'] as bool? ?? true;
      final encoder = pretty
          ? const JsonEncoder.withIndent('  ')
          : const JsonEncoder();
      await outputFile.writeAsString(encoder.convert(document));

      logger.info(
        'Wrote OpenAPI document to '
        '${p.relative(outputFile.path, from: projectRoot.path)}',
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
