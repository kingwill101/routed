import 'package:routed_core/src/security/ip_filter.dart';
import 'package:routed_core/src/security/network.dart';
import 'package:test/test.dart';

void main() {
  group('IP filter primitive', () {
    test('denies unmatched addresses when the default is deny', () {
      final filter = IpFilter(
        enabled: true,
        defaultAction: IpFilterAction.deny,
        allow: [NetworkMatcher.parse('203.0.113.5')],
        deny: const [],
        respectTrustedProxies: false,
      );

      expect(filter.allows('203.0.113.5'), isTrue);
      expect(filter.allows('198.51.100.10'), isFalse);
    });

    test('allows unmatched addresses when the default is allow', () {
      final filter = IpFilter(
        enabled: true,
        defaultAction: IpFilterAction.allow,
        allow: const [],
        deny: [NetworkMatcher.parse('198.51.100.0/24')],
        respectTrustedProxies: true,
      );

      expect(filter.allows('203.0.113.5'), isTrue);
      expect(filter.allows('198.51.100.25'), isFalse);
    });

    test('deny rules take precedence over allow rules', () {
      final filter = IpFilter(
        enabled: true,
        defaultAction: IpFilterAction.allow,
        allow: [NetworkMatcher.parse('0.0.0.0/0')],
        deny: [NetworkMatcher.parse('198.51.100.0/24')],
        respectTrustedProxies: true,
      );

      expect(filter.allows('203.0.113.5'), isTrue);
      expect(filter.allows('198.51.100.25'), isFalse);
    });

    test('disabled filters allow every address', () {
      expect(IpFilter.disabled().allows('not-an-ip'), isTrue);
    });
  });
}
