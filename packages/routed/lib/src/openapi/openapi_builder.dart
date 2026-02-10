/// Build-runner `$package$` builder that generates an OpenAPI 3.1 spec
/// from a route manifest JSON file.
///
/// This builder reads the route manifest (produced by running
/// `dart run routed spec`) and converts it into `openapi.json` plus a
/// serving controller.
///
/// ## Usage
///
/// 1. Generate the manifest:
///    ```bash
///    dart run routed spec
///    ```
///    This writes `.dart_tool/routed/route_manifest.json` by default.
///
/// 2. Run `build_runner`:
///    ```bash
///    dart run build_runner build
///    ```
///
/// 3. The builder outputs:
///    - `lib/generated/openapi.json` — The OpenAPI 3.1 specification
///    - `lib/generated/openapi_controller.g.dart` — A handler that serves
///      the spec
///
/// ## Configuration
///
/// Configure the builder via `build.yaml` options:
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       routed|openapi:
///         options:
///           title: "My API"
///           version: "1.0.0"
///           description: "API description"
///           manifest_path: ".dart_tool/routed/route_manifest.json"
///           serve_path: "/openapi.json"
///           include_hidden: false
///           servers:
///             - url: "https://api.example.com"
///               description: "Production"
/// ```
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:routed/src/engine/route_manifest.dart';
import 'package:routed/src/openapi/manifest_to_openapi.dart';
import 'package:routed/src/openapi/openapi_spec.dart';

/// Factory function registered in `build.yaml`.
Builder openApiBuilder(BuilderOptions options) =>
    _OpenApiBuilder(options.config);

class _OpenApiBuilder implements Builder {
  _OpenApiBuilder(this._config);

  final Map<String, dynamic> _config;

  static const _defaultManifestPath = '.dart_tool/routed/route_manifest.json';
  static const _outputSpecPath = 'lib/generated/openapi.json';
  static const _outputControllerPath =
      'lib/generated/openapi_controller.g.dart';

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$package$': [_outputSpecPath, _outputControllerPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final manifestPath =
        _config['manifest_path'] as String? ?? _defaultManifestPath;

    // Locate the manifest file.
    final manifestAssetId = AssetId(buildStep.inputId.package, manifestPath);
    if (!await buildStep.canRead(manifestAssetId)) {
      log.warning(
        'OpenAPI builder: manifest file not found at "$manifestPath". '
        'Run `dart run routed spec` first to generate it.',
      );
      return;
    }

    // Parse the manifest.
    final manifestJson = await buildStep.readAsString(manifestAssetId);
    final Map<String, Object?> manifestMap;
    try {
      manifestMap = jsonDecode(manifestJson) as Map<String, Object?>;
    } on FormatException catch (e) {
      log.severe('OpenAPI builder: failed to parse manifest JSON: $e');
      return;
    }

    final manifest = RouteManifest.fromJson(manifestMap);

    // Build the OpenAPI config from builder options.
    final config = _buildConfig();

    // Convert manifest → OpenAPI spec.
    final spec = manifestToOpenApi(manifest, config: config);

    // Write openapi.json.
    final specOutput = AssetId(buildStep.inputId.package, _outputSpecPath);
    await buildStep.writeAsString(specOutput, spec.toJsonString(pretty: true));

    // Write serving controller.
    final controllerOutput = AssetId(
      buildStep.inputId.package,
      _outputControllerPath,
    );
    final servePath = _config['serve_path'] as String? ?? '/openapi.json';
    final controllerCode = _generateController(spec, servePath);
    await buildStep.writeAsString(controllerOutput, controllerCode);

    log.info(
      'OpenAPI builder: generated spec with ${spec.paths.length} paths '
      'and ${spec.tags.length} tags.',
    );
  }

  OpenApiConfig _buildConfig() {
    final title = _config['title'] as String? ?? 'API';
    final version = _config['version'] as String? ?? '1.0.0';
    final description = _config['description'] as String?;
    final includeHidden = _config['include_hidden'] == true;

    final servers = <OpenApiServer>[];
    final serversConfig = _config['servers'];
    if (serversConfig is List) {
      for (final entry in serversConfig) {
        if (entry is Map) {
          servers.add(
            OpenApiServer(
              url: entry['url']?.toString() ?? '/',
              description: entry['description']?.toString(),
            ),
          );
        }
      }
    }

    return OpenApiConfig(
      title: title,
      version: version,
      description: description,
      servers: servers,
      includeHidden: includeHidden,
    );
  }

  /// Generates a Dart file that exports the OpenAPI spec as a const string
  /// and provides a handler to serve it.
  String _generateController(OpenApiSpec spec, String servePath) {
    final specJson = spec.toJsonString(pretty: true);
    // Escape for embedding in a Dart raw string.
    final escaped = specJson.replaceAll(r"'", r"\'");

    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// Generated by openApiBuilder')
      ..writeln('// ignore_for_file: lines_longer_than_80_chars')
      ..writeln()
      ..writeln("import 'dart:convert';")
      ..writeln()
      ..writeln("import 'package:routed/routed.dart';")
      ..writeln()
      ..writeln('/// The OpenAPI 3.1 specification as a JSON string.')
      ..writeln("const String openApiSpecJson = '$escaped';")
      ..writeln()
      ..writeln('/// The OpenAPI 3.1 specification as a parsed map.')
      ..writeln(
        'final Map<String, Object?> openApiSpecMap = '
        'jsonDecode(openApiSpecJson) as Map<String, Object?>;',
      )
      ..writeln()
      ..writeln('/// Registers the OpenAPI spec endpoint on the engine.')
      ..writeln('///')
      ..writeln('/// Serves the spec at `$servePath` as `application/json`.')
      ..writeln('void registerOpenApiEndpoint(Engine engine) {')
      ..writeln("  engine.get('$servePath', (EngineContext ctx) {")
      ..writeln(
        "    ctx.response.headers.set('Content-Type', "
        "'application/json; charset=utf-8');",
      )
      ..writeln('    return ctx.string(openApiSpecJson);')
      ..writeln('  });')
      ..writeln('}');

    return buffer.toString();
  }
}
