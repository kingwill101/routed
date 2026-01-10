import 'dart:convert';
import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:routed/console.dart' show CliLogger;

import 'package:routed/src/console/args/base_command.dart';
import 'package:routed/src/console/engine/introspector.dart';

class RoutesCommand extends BaseCommand {
  RoutesCommand({
    super.logger,
    super.fileSystem,
    ManifestLoaderFactory? loaderFactory,
  }) : _loaderFactory = loaderFactory ?? _defaultLoaderFactory {
    argParser
      ..addOption(
        'format',
        help: 'Output format.',
        allowed: ['table', 'json'],
        defaultsTo: 'table',
      )
      ..addFlag('pretty', help: 'Pretty-print JSON output.', defaultsTo: true)
      ..addOption(
        'entry',
        help: 'Optional manifest entrypoint to execute.',
        valueHelp: 'tool/spec_manifest.dart',
      );
  }

  @override
  String get name => 'routes';

  @override
  String get description => 'List application routes.';

  @override
  String get category => 'Introspection';

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

      final loader = _loaderFactory(projectRoot, logger, usage, fileSystem);

      final manifestResult = await loader.load(
        entry: results?['entry'] as String?,
      );
      final manifest = manifestResult.manifest;

      final format = (results?['format'] as String? ?? 'table').toLowerCase();
      if (format == 'json') {
        final pretty = results?['pretty'] as bool? ?? true;
        final encoder = pretty
            ? const JsonEncoder.withIndent('  ')
            : const JsonEncoder();
        logger.info(encoder.convert(manifest));
      } else {
        _printTable(manifest);
      }

      if (manifestResult.source == ManifestSource.app) {
        logger.info('Used application engine: lib/app.dart');
      } else {
        logger.info(
          'Used manifest entrypoint: ${manifestResult.sourceDescription}',
        );
      }
    });
  }

  void _printTable(Map<String, Object?> manifest) {
    final routesRaw = manifest['routes'];
    final routes = routesRaw is List
        ? routesRaw.cast<Map<String, Object?>>()
        : const <Map<String, Object?>>[];

    if (routes.isEmpty) {
      logger.info('No HTTP routes defined.');
    } else {
      final rows = <List<String>>[
        ['METHOD', 'PATH', 'NAME', 'MIDDLEWARE'],
      ];
      for (final route in routes) {
        final method = route['method']?.toString() ?? '';
        final path = route['path']?.toString() ?? '';
        final name = route['name']?.toString() ?? '';
        final middleware = route['middleware'];
        final middlewareString = middleware is List
            ? middleware.map((e) => e.toString()).join(', ')
            : '';
        rows.add([method, path, name, middlewareString]);
      }
      _printRows(rows);
    }

    final websocketsRaw = manifest['webSockets'];
    final websockets = websocketsRaw is List
        ? websocketsRaw.cast<Map<String, Object?>>()
        : const <Map<String, Object?>>[];

    if (websockets.isNotEmpty) {
      if (routes.isNotEmpty) {
        logger.info('');
      }
      logger.info('WebSocket routes:');
      final rows = <List<String>>[
        ['PATH', 'MIDDLEWARE'],
      ];
      for (final socket in websockets) {
        final path = socket['path']?.toString() ?? '';
        final middleware = socket['middleware'];
        final middlewareString = middleware is List
            ? middleware.map((e) => e.toString()).join(', ')
            : '';
        rows.add([path, middlewareString]);
      }
      _printRows(rows);
    }
  }

  void _printRows(List<List<String>> rows) {
    if (rows.isEmpty) return;
    final columnCount = rows.first.length;
    final widths = List<int>.filled(columnCount, 0);
    for (final row in rows) {
      for (var i = 0; i < columnCount; i++) {
        final cellLength = row[i].length;
        if (cellLength > widths[i]) {
          widths[i] = cellLength;
        }
      }
    }
    for (final row in rows) {
      final buffer = StringBuffer();
      for (var i = 0; i < columnCount; i++) {
        if (i > 0) buffer.write('  ');
        buffer.write(row[i].padRight(widths[i]));
      }
      logger.info(buffer.toString());
    }
  }
}
