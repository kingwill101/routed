import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('secureRandomToken returns non-empty randomized values', () {
    final a = secureRandomToken();
    final b = secureRandomToken();

    expect(a, isNotEmpty);
    expect(b, isNotEmpty);
    expect(a, isNot(equals(b)));
  });

  test('secureRandomToken supports custom byte length', () {
    final short = secureRandomToken(length: 8);
    final long = secureRandomToken(length: 64);

    expect(short.length, lessThan(long.length));
  });

  test('base64UrlNoPadding removes trailing padding', () {
    final encoded = base64UrlNoPadding(<int>[255]);

    expect(encoded, equals('_w'));
    expect(encoded.contains('='), isFalse);
  });
}
