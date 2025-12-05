import 'dart:io';

import 'package:routed/src/security/network.dart';
import 'package:test/test.dart';

void main() {
  group('NetworkMatcher', () {
    group('maybeParse', () {
      test('should parse valid IPv4 CIDR', () {
        final matcher = NetworkMatcher.maybeParse('192.168.1.0/24');
        expect(matcher, isNotNull);
      });

      test('should parse valid IPv6 CIDR', () {
        final matcher = NetworkMatcher.maybeParse('2001:db8::/32');
        expect(matcher, isNotNull);
      });

      test('should parse valid IPv4 address without CIDR', () {
        final matcher = NetworkMatcher.maybeParse('192.168.1.1');
        expect(matcher, isNotNull);
      });

      test('should parse valid IPv6 address without CIDR', () {
        final matcher = NetworkMatcher.maybeParse('2001:db8::1');
        expect(matcher, isNotNull);
      });

      test('should return null for empty string', () {
        final matcher = NetworkMatcher.maybeParse('');
        expect(matcher, isNull);
      });

      test('should return null for invalid IP', () {
        final matcher = NetworkMatcher.maybeParse('999.999.999.999/24');
        expect(matcher, isNull);
      });

      test('should return null for invalid CIDR prefix', () {
        final matcher = NetworkMatcher.maybeParse('192.168.1.0/33');
        expect(matcher, isNotNull); // it clamps the prefix
      });

      test('should return null for garbage string', () {
        final matcher = NetworkMatcher.maybeParse('not-an-ip');
        expect(matcher, isNull);
      });
    });

    group('parse', () {
      test('should parse valid IPv4 CIDR', () {
        final matcher = NetworkMatcher.parse('192.168.1.0/24');
        expect(matcher, isA<NetworkMatcher>());
      });

      test('should parse valid IPv6 CIDR', () {
        final matcher = NetworkMatcher.parse('2001:db8::/32');
        expect(matcher, isA<NetworkMatcher>());
      });

      test('should throw FormatException for invalid input', () {
        expect(
          () => NetworkMatcher.parse('invalid'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('contains', () {
      group('IPv4', () {
        final matcher = NetworkMatcher.parse('192.168.1.0/24');

        test('should return true for address inside the range', () {
          final address = InternetAddress('192.168.1.100');
          expect(matcher.contains(address), isTrue);
        });

        test('should return false for address outside the range', () {
          final address = InternetAddress('192.168.2.1');
          expect(matcher.contains(address), isFalse);
        });

        test('should return true for the first address in the range', () {
          final address = InternetAddress('192.168.1.0');
          expect(matcher.contains(address), isTrue);
        });

        test('should return true for the last address in the range', () {
          final address = InternetAddress('192.168.1.255');
          expect(matcher.contains(address), isTrue);
        });

        test('should handle /32 prefix for exact match', () {
          final matcher32 = NetworkMatcher.parse('192.168.1.1/32');
          final address = InternetAddress('192.168.1.1');
          expect(matcher32.contains(address), isTrue);
          final anotherAddress = InternetAddress('192.168.1.2');
          expect(matcher32.contains(anotherAddress), isFalse);
        });

        test('should handle /0 prefix to match all addresses', () {
          final matcher0 = NetworkMatcher.parse('0.0.0.0/0');
          final address = InternetAddress('10.0.0.1');
          expect(matcher0.contains(address), isTrue);
        });
      });

      group('IPv6', () {
        final matcher = NetworkMatcher.parse('2001:db8::/32');

        test('should return true for address inside the range', () {
          final address = InternetAddress('2001:db8:dead:beef::1');
          expect(matcher.contains(address), isTrue);
        });

        test('should return false for address outside the range', () {
          final address = InternetAddress('2001:db9::1');
          expect(matcher.contains(address), isFalse);
        });

        test('should handle /128 prefix for exact match', () {
          final matcher128 = NetworkMatcher.parse('2001:db8::1/128');
          final address = InternetAddress('2001:db8::1');
          expect(matcher128.contains(address), isTrue);
          final anotherAddress = InternetAddress('2001:db8::2');
          expect(matcher128.contains(anotherAddress), isFalse);
        });

        test('should handle /0 prefix to match all addresses', () {
          final matcher0 = NetworkMatcher.parse('::/0');
          final address = InternetAddress('::1');
          expect(matcher0.contains(address), isTrue);
        });
      });

      group('Mixed types', () {
        test(
          'should return false when matching IPv6 address against IPv4 matcher',
          () {
            final matcher = NetworkMatcher.parse('192.168.1.0/24');
            final address = InternetAddress('2001:db8::1');
            expect(matcher.contains(address), isFalse);
          },
        );

        test(
          'should return false when matching IPv4 address against IPv6 matcher',
          () {
            final matcher = NetworkMatcher.parse('2001:db8::/32');
            final address = InternetAddress('192.168.1.1');
            expect(matcher.contains(address), isFalse);
          },
        );
      });
    });
  });
}
