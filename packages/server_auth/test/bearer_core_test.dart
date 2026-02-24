import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('extractBearerToken', () {
    test('extracts token for matching prefix', () {
      expect(extractBearerToken('Bearer token-123'), equals('token-123'));
    });

    test('returns null for missing or invalid values', () {
      expect(extractBearerToken(null), isNull);
      expect(extractBearerToken(''), isNull);
      expect(extractBearerToken('Basic abc'), isNull);
      expect(extractBearerToken('Bearer   '), isNull);
    });

    test('supports custom prefix', () {
      expect(extractBearerToken('Token abc', prefix: 'Token '), equals('abc'));
    });

    test('supports case-insensitive matching', () {
      expect(
        extractBearerToken('bearer lower', caseSensitive: false),
        equals('lower'),
      );
      expect(extractBearerToken('bearer lower'), isNull);
    });

    test('uses full value when prefix is empty', () {
      expect(
        extractBearerToken('  raw-token  ', prefix: ''),
        equals('raw-token'),
      );
    });
  });

  group('resolveBearerOrCookieToken', () {
    test('prefers bearer header when present', () {
      final token = resolveBearerOrCookieToken(
        authorizationHeader: 'Bearer header-token',
        bearerPrefix: 'Bearer ',
        cookieName: 'auth',
        cookies: const <MapEntry<String, String>>[
          MapEntry<String, String>('auth', 'cookie-token'),
        ],
      );
      expect(token, equals('header-token'));
    });

    test('falls back to named cookie token', () {
      final token = resolveBearerOrCookieToken(
        authorizationHeader: null,
        bearerPrefix: 'Bearer ',
        cookieName: 'auth',
        cookies: const <MapEntry<String, String>>[
          MapEntry<String, String>('other', 'x'),
          MapEntry<String, String>('auth', ' cookie-token '),
        ],
      );
      expect(token, equals('cookie-token'));
    });

    test('returns null when header and cookie are missing or empty', () {
      final missing = resolveBearerOrCookieToken(
        authorizationHeader: null,
        bearerPrefix: 'Bearer ',
        cookieName: 'auth',
        cookies: const <MapEntry<String, String>>[],
      );
      final emptyCookie = resolveBearerOrCookieToken(
        authorizationHeader: null,
        bearerPrefix: 'Bearer ',
        cookieName: 'auth',
        cookies: const <MapEntry<String, String>>[
          MapEntry<String, String>('auth', '   '),
        ],
      );
      expect(missing, isNull);
      expect(emptyCookie, isNull);
    });
  });
}
