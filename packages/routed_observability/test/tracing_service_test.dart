import 'package:routed_observability/routed_observability.dart';
import 'package:test/test.dart';

void main() {
  test('disabled tracing service has no tracer', () {
    final service = TracingService.disabled();

    expect(service.enabled, isFalse);
    expect(service.hasTracer, isFalse);
    expect(service.tracer, isNull);
  });

  test('buildTracingService returns disabled when config disabled', () {
    final service = buildTracingService(
      const TracingConfig(
        enabled: false,
        serviceName: 'svc',
        exporter: 'none',
        endpoint: null,
        headers: {},
      ),
    );

    expect(service.enabled, isFalse);
    expect(service.hasTracer, isFalse);
  });
}
