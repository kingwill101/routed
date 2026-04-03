import 'package:routed_core/routed_core.dart';
import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('CorsConfigSpec', () {
    const spec = CorsConfigSpec();

    test('fromMap parses explicit values', () {
      final resolved = spec.fromMap({
        'enabled': true,
        'allowed_origins': ['https://app.dev'],
        'allowed_methods': ['GET', 'POST'],
        'allowed_headers': ['Authorization'],
        'allow_credentials': true,
        'max_age': 600,
        'exposed_headers': ['X-Token'],
      });

      expect(resolved.enabled, isTrue);
      expect(resolved.allowedOrigins, equals(['https://app.dev']));
      expect(resolved.allowedMethods, equals(['GET', 'POST']));
      expect(resolved.allowedHeaders, equals(['Authorization']));
      expect(resolved.allowCredentials, isTrue);
      expect(resolved.maxAge, equals(600));
      expect(resolved.exposedHeaders, equals(['X-Token']));
    });

    test('resolveFromConfig merges security and cors namespaces', () {
      final config = ConfigImpl({
        'security': {
          'cors': {
            'enabled': true,
            'allowed_origins': ['https://security.dev'],
          },
        },
        'cors': {
          'allowed_methods': ['GET', 'PATCH'],
        },
      });

      final resolved = spec.resolveFromConfig(config);
      expect(resolved.enabled, isTrue);
      expect(resolved.allowedOrigins, equals(['https://security.dev']));
      expect(resolved.allowedMethods, equals(['GET', 'PATCH']));
    });
  });
}
