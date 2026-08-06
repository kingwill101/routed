import 'package:build/build.dart';

/// Build-time OpenAPI builder for Routed (stub).
class OpenApiBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['openapi.json']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Stub: generate empty OpenAPI spec
    final id = buildStep.inputId.changeExtension('.openapi.json');
    await buildStep.writeAsString(id, '{}');
  }
}

Builder openApiBuilder(BuilderOptions options) => OpenApiBuilder();
