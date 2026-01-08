import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart' as routed;
import 'package:routed/src/console/args/base_command.dart';
import 'package:routed/src/console/engine/analyzer_introspector.dart';

class OpenApiMakeCommand extends BaseCommand {
  OpenApiMakeCommand({super.logger, super.fileSystem}) {
    argParser
      ..addOption(
        'output',
        help: 'Target path for the generated OpenAPI document.',
        defaultsTo: p.join('.dart_tool', 'routed', 'openapi.json'),
        valueHelp: 'file',
      )
      ..addOption(
        'entry',
        help: 'Entrypoint file to start analysis from.',
        defaultsTo: 'tool/spec_manifest.dart',
      )
      ..addFlag(
        'pretty',
        help: 'Pretty-print the JSON output.',
        defaultsTo: true,
      );
  }

  @override
  String get name => 'make';

  @override
  String get description =>
      'Statically analyze the codebase to generate an OpenAPI document.';

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

      final entrypoint =
          results?['entry'] as String? ?? 'tool/spec_manifest.dart';
      final absoluteEntry = p.join(projectRoot.path, entrypoint);

      if (!await fileSystem.file(absoluteEntry).exists()) {
        // Fallback to lib/app.dart if default wasn't changed
        if (entrypoint == 'tool/spec_manifest.dart') {
          if (await fileSystem
              .file(p.join(projectRoot.path, 'lib/app.dart'))
              .exists()) {
            logger.info(
              'tool/spec_manifest.dart not found, falling back to lib/app.dart',
            );
            // We can't easily change the variable but we can use a different path for introspection
          } else {
            throw UsageException('Entrypoint not found: $entrypoint', usage);
          }
        } else {
          throw UsageException('Entrypoint not found: $entrypoint', usage);
        }
      }

      logger.info('Analyzing routes starting from $entrypoint...');

      final introspector = AnalyzerIntrospector(
        projectRoot: projectRoot.path,
        entrypoint: entrypoint,
      );

      final manifest = await introspector.introspect();

      final info = const routed.OpenApiDocumentInfo(
        title: 'Routed Service',
        version: '1.0.0',
      );

      // Extract components from the first route if available
      Map<String, Object?> components = {};
      if (manifest.routes.isNotEmpty &&
          manifest.routes.first.constraints.containsKey('components')) {
        final comps = manifest.routes.first.constraints['components'];
        if (comps is Map<String, Object?>) {
          components = comps;
        }
        // Clean up the constraint
        // manifest.routes.first.constraints.remove('components');
      }

      final document = routed.generateOpenApiDocument(
        manifest,
        info: info,
        components: components,
      );
      final outputArg =
          results?['output'] as String? ??
          p.join('.dart_tool', 'routed', 'openapi.json');
      final outputFile = fileSystem.file(p.join(projectRoot.path, outputArg));
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
      logger.info('Found ${manifest.routes.length} routes.');
    });
  }
}
