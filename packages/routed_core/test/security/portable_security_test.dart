import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  test('trusted proxy rules initialize without dart:io parsing', () {
    final resolver = TrustedProxyResolver(
      enabled: true,
      forwardClientIp: true,
      proxies: ['10.0.0.0/8', '2001:db8::/32'],
      headers: ['x-forwarded-for'],
    );

    expect(resolver, isA<TrustedProxyResolver>());
    expect(NetworkMatcher.parse('10.0.0.0/8').containsText('10.2.3.4'), isTrue);
  });

  test('trusted proxy resolver accepts portable client addresses', () {
    final resolver = TrustedProxyResolver(
      enabled: true,
      forwardClientIp: true,
      proxies: ['127.0.0.1'],
      headers: ['x-forwarded-for'],
    );
    final request = AdapterHttpBridge.toHttpRequest(
      HttpConnection(
        PortableRequest(
          method: 'GET',
          uri: Uri.parse('http://example.test/'),
          headers: PortableHeaders({
            'x-forwarded-for': ['203.0.113.8'],
          }),
          remoteAddress: '127.0.0.1',
        ).asAdapter(),
        RecordingResponseAdapter(),
      ),
    );

    expect(resolver.resolve(request), '203.0.113.8');
  });
}
