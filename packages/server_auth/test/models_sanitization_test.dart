import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('public attribute sanitization terminates on cyclic values', () {
    final attributes = <String, dynamic>{};
    attributes['self'] = attributes;
    attributes['token'] = 'must-not-survive';
    attributes['public'] = 'safe';

    final sanitized = sanitizeAuthPublicAttributes(attributes);

    expect(sanitized['self'], isNull);
    expect(sanitized.containsKey('token'), isFalse);
    expect(sanitized['public'], equals('safe'));
  });

  test('public attribute sanitization removes secret-bearing key variants', () {
    final sanitized = sanitizeAuthPublicAttributes({
      'passwordResetToken': 'hidden',
      'oauthAccessToken': 'hidden',
      'jwt': 'hidden',
      'sessionId': 'hidden',
      'secretValue': 'hidden',
      'publicValue': 'safe',
    });

    expect(sanitized.keys, contains('publicValue'));
    expect(sanitized.keys, isNot(contains('passwordResetToken')));
    expect(sanitized.keys, isNot(contains('oauthAccessToken')));
    expect(sanitized.keys, isNot(contains('jwt')));
    expect(sanitized.keys, isNot(contains('sessionId')));
    expect(sanitized.keys, isNot(contains('secretValue')));
  });

  test('public attribute sanitization bounds deeply nested values', () {
    final attributes = <String, dynamic>{};
    var current = attributes;
    for (var index = 0; index < 64; index++) {
      final next = <String, dynamic>{};
      current['level$index'] = next;
      current = next;
    }
    current['password'] = 'must-not-survive';

    final sanitized = sanitizeAuthPublicAttributes(attributes);

    expect(sanitized, isNotEmpty);
    var value = sanitized;
    for (var index = 0; index < 31; index++) {
      value = value['level$index'] as Map<String, dynamic>;
    }
    expect(value['level31'], isNull);
  });
}
