import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('public user serialization removes credential-like attributes', () {
    final user = AuthUser(
      id: 'user-1',
      attributes: {
        'theme': 'dark',
        'password': 'plain-text',
        'password_hash': 'hash',
        'refreshToken': 'secret',
        'nested': {'refresh_token': 'secret', 'visible': true},
      },
    );

    expect(
      user.toJson()['attributes'],
      equals({
        'theme': 'dark',
        'nested': {'visible': true},
      }),
    );
  });

  test('session serialization omits JWTs unless explicitly requested', () {
    final session = AuthSession(
      user: AuthUser(id: 'user-1'),
      expiresAt: DateTime.utc(2030),
      strategy: AuthSessionStrategy.jwt,
      token: 'bearer-secret',
    );

    expect(session.toJson().containsKey('token'), isFalse);
    expect(
      session.toJson(includeToken: true)['token'],
      equals('bearer-secret'),
    );
  });

  test('account serialization omits provider tokens by default', () {
    final account = AuthAccount(
      providerId: 'github',
      providerAccountId: 'account-1',
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
    );

    expect(account.toJson().containsKey('access_token'), isFalse);
    expect(account.toStorageJson()['access_token'], equals('access-secret'));
  });

  test('credential attributes do not duplicate the submitted password', () {
    final credentials = AuthCredentials.fromMap({
      'email': 'user@example.com',
      'password': 'plain-text',
      'remember': true,
    });

    expect(credentials.password, equals('plain-text'));
    expect(credentials.attributes.containsKey('password'), isFalse);
    expect(credentials.attributes['remember'], isTrue);
  });
}
