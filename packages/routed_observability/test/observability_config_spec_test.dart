import 'package:routed_observability/routed_observability.dart';
import 'package:test/test.dart';

void main() {
  group('ObservabilityConfigSpec', () {
    const spec = ObservabilityConfigSpec();

    test('parses defaults', () {
      final config = spec.fromMap(const {});
      expect(config.enabled, isTrue);
      expect(config.tracing.enabled, isFalse);
      expect(config.metrics.enabled, isFalse);
      expect(config.health.enabled, isTrue);
      expect(config.health.readinessPath, equals('/readyz'));
      expect(config.health.livenessPath, equals('/livez'));
    });

    test('validates sentry requirements and bucket positivity', () {
      expect(
        () => spec.fromMap({
          'sentry': {'enabled': true, 'dsn': ''},
        }),
        throwsA(isA<Exception>()),
      );

      expect(
        () => spec.fromMap({
          'metrics': {
            'buckets': [0.1, 0],
          },
        }),
        throwsA(isA<Exception>()),
      );
    });
  });
}
