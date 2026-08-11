import 'package:build/build.dart';
import 'package:test/test.dart';
import 'package:routed_openapi_builder/routed_openapi_builder.dart';

void main() {
  group('RoutedOpenApiBuilder', () {
    test('builder is exported', () {
      expect(openApiBuilder, isNotNull);
    });

    test('builder creates OpenApiBuilder', () {
      final builder = openApiBuilder(BuilderOptions({}));
      expect(builder, isA<OpenApiBuilder>());
    });
  });
}
