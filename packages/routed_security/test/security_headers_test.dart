import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('security header policy helpers', () {
    test('builds headers for enabled policy fields', () {
      final headers = buildSecurityHeaders(
        const SecurityHeaderPolicy(
          csp: "default-src 'self'",
          xContentTypeOptionsNoSniff: true,
          hstsMaxAge: 31536000,
          xFrameOptions: 'DENY',
        ),
      );

      expect(headers['Content-Security-Policy'], "default-src 'self'");
      expect(headers['X-Content-Type-Options'], 'nosniff');
      expect(
        headers['Strict-Transport-Security'],
        'max-age=31536000; includeSubDomains; preload',
      );
      expect(headers['X-Frame-Options'], 'DENY');
    });
  });
}
