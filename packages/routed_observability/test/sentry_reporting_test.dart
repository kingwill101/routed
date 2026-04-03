import 'package:routed_observability/routed_observability.dart';
import 'package:test/test.dart';

void main() {
  test('SentryReporter remains disabled when integration disabled', () async {
    final reporter = SentryReporter();
    reporter.configure(
      const ObservabilitySentryConfig(
        enabled: false,
        dsn: null,
        sendDefaultPii: false,
        tracesSampleRate: 0,
      ),
      enabled: true,
    );

    expect(reporter.enabled, isFalse);
    await reporter.ensureReady();
    await reporter.close();
    expect(reporter.enabled, isFalse);
  });
}
