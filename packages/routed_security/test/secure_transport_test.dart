import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('secure transport helpers', () {
    test('detects https from request scheme directly', () {
      expect(
        isSecureTransport(
          scheme: 'https',
          proxySupportEnabled: false,
          remoteIsTrustedProxy: false,
        ),
        isTrue,
      );
    });

    test('uses forwarded headers only when proxy is trusted', () {
      expect(
        isSecureTransport(
          scheme: 'http',
          proxySupportEnabled: true,
          remoteIsTrustedProxy: true,
          forwardedProto: 'https',
        ),
        isTrue,
      );

      expect(
        isSecureTransport(
          scheme: 'http',
          proxySupportEnabled: true,
          remoteIsTrustedProxy: false,
          forwardedProto: 'https',
        ),
        isFalse,
      );
    });

    test('parses RFC Forwarded proto', () {
      expect(forwardedHeaderIndicatesHttps('for=1.2.3.4;proto=https'), isTrue);
      expect(forwardedHeaderIndicatesHttps('for=1.2.3.4;proto=http'), isFalse);
    });
  });
}
