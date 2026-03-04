import 'dart:io';

import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('NetworkMatcher', () {
    test('parses IPv4/IPv6 CIDR and matches addresses', () {
      final ipv4 = NetworkMatcher.parse('192.168.1.0/24');
      final ipv6 = NetworkMatcher.parse('2001:db8::/32');

      expect(ipv4.contains(InternetAddress('192.168.1.42')), isTrue);
      expect(ipv4.contains(InternetAddress('192.168.2.1')), isFalse);
      expect(ipv6.contains(InternetAddress('2001:db8::1')), isTrue);
      expect(ipv6.contains(InternetAddress('2001:db9::1')), isFalse);
    });

    test('returns null for invalid values in maybeParse', () {
      expect(NetworkMatcher.maybeParse(''), isNull);
      expect(NetworkMatcher.maybeParse('not-an-ip'), isNull);
    });
  });
}
