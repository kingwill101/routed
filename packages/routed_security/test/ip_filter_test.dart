import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('IpFilter', () {
    test('disabled filter always allows', () {
      final filter = IpFilter.disabled();
      expect(filter.allows('203.0.113.10'), isTrue);
      expect(filter.allows('invalid-ip'), isTrue);
    });

    test('deny rules take precedence over allow rules', () {
      final filter = IpFilter(
        enabled: true,
        defaultAction: IpFilterAction.allow,
        allow: [NetworkMatcher.parse('10.0.0.0/8')],
        deny: [NetworkMatcher.parse('10.0.0.5/32')],
        respectTrustedProxies: true,
      );

      expect(filter.allows('10.0.0.4'), isTrue);
      expect(filter.allows('10.0.0.5'), isFalse);
    });

    test('default action is used when no rule matches', () {
      final allowByDefault = IpFilter(
        enabled: true,
        defaultAction: IpFilterAction.allow,
        allow: const [],
        deny: const [],
        respectTrustedProxies: true,
      );
      final denyByDefault = IpFilter(
        enabled: true,
        defaultAction: IpFilterAction.deny,
        allow: const [],
        deny: const [],
        respectTrustedProxies: true,
      );

      expect(allowByDefault.allows('198.51.100.1'), isTrue);
      expect(denyByDefault.allows('198.51.100.1'), isFalse);
    });
  });
}
