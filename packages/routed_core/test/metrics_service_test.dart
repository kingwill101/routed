import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  group('MetricsService', () {
    test('tracks active requests and renders counters/histograms', () {
      final metrics = MetricsService(buckets: [0.1, 0.5, 1.0]);

      metrics.onRequestStart();
      metrics.onRequestStart();
      expect(metrics.activeRequests, equals(2));

      metrics.onRequestEnd(
        method: 'GET',
        route: '/items',
        status: 200,
        duration: const Duration(milliseconds: 120),
      );
      expect(metrics.activeRequests, equals(1));

      final output = metrics.renderPrometheus();
      expect(output, contains('routed_requests_total'));
      expect(output, contains('method="GET"'));
      expect(output, contains('route="/items"'));
      expect(output, contains('status="200"'));
      expect(output, contains('routed_request_duration_seconds_bucket'));
      expect(output, contains('routed_active_requests 1'));
    });

    test('active requests never drops below zero', () {
      final metrics = MetricsService(buckets: [0.25]);
      metrics.onRequestEnd(
        method: 'POST',
        route: '/submit',
        status: 500,
        duration: const Duration(milliseconds: 5),
      );
      expect(metrics.activeRequests, equals(0));
    });
  });
}
