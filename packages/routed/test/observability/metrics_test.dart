import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('MetricsService', () {
    group('renderPrometheus label formatting', () {
      test('counter labels contain only method, route and status by default',
          () {
        final service = MetricsService(buckets: []);
        service.onRequestStart();
        service.onRequestEnd(
          method: 'GET',
          route: '/hello',
          status: 200,
          duration: Duration.zero,
        );

        final output = service.renderPrometheus();

        // The counter line must have exactly {method,route,status} with no
        // extra key such as "le" leaking in from the histogram bucket path.
        expect(
          output,
          contains(
            'routed_requests_total{method="GET",route="/hello",status="200"} 1',
          ),
        );
        // Confirm the counter label string does not contain a stray "le="
        final counterLine = output
            .split('\n')
            .where((line) => line.startsWith('routed_requests_total{'))
            .first;
        expect(counterLine, isNot(contains('le=')));
      });

      test('histogram bucket labels include the "le" boundary label', () {
        final service = MetricsService(buckets: [0.1, 0.5]);
        service.onRequestStart();
        service.onRequestEnd(
          method: 'POST',
          route: '/submit',
          status: 201,
          duration: const Duration(milliseconds: 50),
        );

        final output = service.renderPrometheus();

        // Bucket lines for histogram entries must carry a le= label.
        final bucketLines = output
            .split('\n')
            .where(
              (line) =>
                  line.startsWith('routed_request_duration_seconds_bucket'),
            )
            .toList();
        expect(bucketLines, isNotEmpty);
        for (final line in bucketLines) {
          expect(line, contains('le="'));
        }
        // The "+Inf" sentinel must also be present.
        expect(bucketLines.any((l) => l.contains('le="+Inf"')), isTrue);
      });

      test(
          'null extra does not produce malformed label output (regression for ...?extra)',
          () {
        // This test guards against regressions where passing null extra
        // to toLabelString could produce invalid Prometheus label syntax such
        // as double commas or a trailing comma.
        final service = MetricsService(buckets: [0.005]);
        service.onRequestStart();
        service.onRequestEnd(
          method: 'DELETE',
          route: '/item',
          status: 204,
          duration: const Duration(milliseconds: 1),
        );

        final output = service.renderPrometheus();

        // No malformed label artifacts.
        expect(output, isNot(contains(',}')));
        expect(output, isNot(contains('{,')));
        expect(output, isNot(contains('null')));
      });

      test('renderPrometheus tracks active request count', () {
        final service = MetricsService(buckets: []);

        service.onRequestStart();
        service.onRequestStart();
        expect(service.activeRequests, 2);

        service.onRequestEnd(
          method: 'GET',
          route: '/',
          status: 200,
          duration: Duration.zero,
        );
        expect(service.activeRequests, 1);

        final output = service.renderPrometheus();
        expect(output, contains('routed_active_requests 1'));
      });

      test(
          'multiple requests with different methods produce separate counter entries',
          () {
        final service = MetricsService(buckets: []);

        for (final method in ['GET', 'POST', 'PUT']) {
          service.onRequestStart();
          service.onRequestEnd(
            method: method,
            route: '/resource',
            status: 200,
            duration: Duration.zero,
          );
        }

        final output = service.renderPrometheus();
        expect(
          output,
          contains(
            'routed_requests_total{method="GET",route="/resource",status="200"} 1',
          ),
        );
        expect(
          output,
          contains(
            'routed_requests_total{method="POST",route="/resource",status="200"} 1',
          ),
        );
        expect(
          output,
          contains(
            'routed_requests_total{method="PUT",route="/resource",status="200"} 1',
          ),
        );
      });

      test('label values with special characters are properly escaped', () {
        final service = MetricsService(buckets: []);
        service.onRequestStart();
        service.onRequestEnd(
          method: 'GET',
          // Route contains a double-quote which must be escaped in the output.
          route: r'/path"with"quotes',
          status: 200,
          duration: Duration.zero,
        );

        final output = service.renderPrometheus();

        // Verify that the route label does not produce unescaped quotes that
        // would break Prometheus label syntax.
        final counterLines = output
            .split('\n')
            .where((l) => l.startsWith('routed_requests_total{'))
            .toList();
        expect(counterLines, isNotEmpty);
        // The escaped form uses \" inside the string literal.
        expect(counterLines.first, contains(r'\"with\"'));
      });
    });
  });
}