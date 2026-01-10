import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/specs/cors.dart';
import 'package:test/test.dart';

void main() {
  group('CorsConfigSpec Schema Validation', () {
    test('validates correct config', () async {
      final spec = const CorsConfigSpec();
      final schema = spec.schema!;

      final validConfig = {
        'enabled': true,
        'allowed_origins': ['https://example.com'],
        'allowed_methods': ['GET', 'POST'],
        'allowed_headers': ['Content-Type'],
        'exposed_headers': ['X-Custom-Header'],
        'allow_credentials': true,
        'max_age': 3600,
      };

      final result = await schema.validate(validConfig);
      expect(result, isEmpty);
    });

    test('validates incorrect config', () async {
      final spec = const CorsConfigSpec();
      final schema = spec.schema!;

      final invalidConfig = {
        'enabled': 'not-a-bool',
        'allowed_origins': 'not-a-list',
        'max_age': 'not-an-int',
      };

      final result = await schema.validate(invalidConfig);
      expect(result, isNotEmpty);
    });

    test('contains default values', () {
      final spec = const CorsConfigSpec();
      final schema = spec.schema!;

      final objSchema = schema as ObjectSchema;
      final props = objSchema.properties!;

      expect(props['enabled']?.defaultValue, isFalse);
      expect(props['allowed_origins']?.defaultValue, equals(['*']));
      expect(props['max_age']?.defaultValue, isNull);
    });
  });
}
