import 'package:build/build.dart';
import 'package:routed_openapi_builder/routed_openapi_builder.dart';
import 'package:test/test.dart';

void main() {
  group('RoutedOpenApiBuilder', () {
    test('builder is exported', () {
      expect(openApiBuilder, isNotNull);
    });

    test('builder creates OpenApiBuilder', () {
      final builder = openApiBuilder(BuilderOptions.empty);
      expect(builder, isA<OpenApiBuilder>());
    });

    test('builder exposes the OpenAPI generated artifact contract', () {
      final builder = OpenApiBuilder();

      expect(builder.buildExtensions, {
        r'$package$': [
          'lib/generated/openapi.json',
          'lib/generated/openapi_controller.g.dart',
        ],
      });
    });
  });
}
