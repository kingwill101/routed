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
}
