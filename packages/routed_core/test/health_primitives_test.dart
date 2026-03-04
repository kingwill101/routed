import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  group('health primitives', () {
    test('HealthCheckResult serializes details', () {
      final ok = HealthCheckResult.ok({'version': '1.0.0'});
      final fail = HealthCheckResult.failure({'reason': 'db-down'});

      expect(ok.ok, isTrue);
      expect(ok.toJson(), equals({'ok': true, 'version': '1.0.0'}));

      expect(fail.ok, isFalse);
      expect(fail.toJson(), equals({'ok': false, 'reason': 'db-down'}));
    });

    test('HealthEndpointRegistry stores path allow list', () {
      final registry = HealthEndpointRegistry();
      registry.setPaths(['/health', '/ready']);

      expect(registry.allows('/health'), isTrue);
      expect(registry.allows('/ready'), isTrue);
      expect(registry.allows('/live'), isFalse);
    });
  });
}
