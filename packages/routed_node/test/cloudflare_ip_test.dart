import 'package:routed_node/src/fetch/cloudflare_ip.dart';
import 'package:test/test.dart';

void main() {
  test('resolves Cloudflare client IP headers case-insensitively', () {
    expect(
      cloudflareClientIpFromHeaders(<String, Object?>{
        'CF-Connecting-IP': ' 203.0.113.10 ',
      }),
      '203.0.113.10',
    );
    expect(
      cloudflareClientIpFromHeaders(<String, Object?>{
        'cf-connecting-ip': <String>['', '2001:db8::10'],
      }),
      '2001:db8::10',
    );
  });

  test('does not invent an address when Cloudflare did not provide one', () {
    expect(
      cloudflareClientIpFromHeaders(<String, Object?>{
        'x-forwarded-for': '203.0.113.10',
      }),
      isNull,
    );
  });
}
