import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('engine security models', () {
    test('cors defaults remain stable', () {
      const config = CorsConfig();
      expect(config.enabled, isFalse);
      expect(config.allowedOrigins, equals(['*']));
      expect(
        config.allowedMethods,
        equals(['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS']),
      );
      expect(config.allowCredentials, isFalse);
      expect(config.maxAge, isNull);
      expect(config.exposedHeaders, isEmpty);
    });

    test('engine security copyWith overrides selected fields', () {
      const initial = EngineSecurityFeatures();
      final updated = initial.copyWith(
        csrfProtection: false,
        csrfCookieName: 'csrf_custom',
        xContentTypeOptionsNoSniff: true,
        maxRequestSize: 2048,
        cors: const CorsConfig(enabled: true),
      );

      expect(updated.csrfProtection, isFalse);
      expect(updated.csrfCookieName, equals('csrf_custom'));
      expect(updated.xContentTypeOptionsNoSniff, isTrue);
      expect(updated.maxRequestSize, equals(2048));
      expect(updated.cors.enabled, isTrue);
      expect(updated.hstsMaxAge, initial.hstsMaxAge);
    });
  });
}
