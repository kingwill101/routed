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

  test('user deserialization tolerates hostile types and nested secrets', () {
    final user = AuthUser.fromJson({
      'id': 'user-1',
      'roles': ['admin', 42, null],
      'attributes': {
        'theme': 'dark',
        'nested': {'api-key': 'secret', 'visible': true},
        42: 'ignored-key',
      },
    });

    expect(user.roles, equals(['admin']));
    expect(
      user.attributes,
      equals({
        'theme': 'dark',
        'nested': {'visible': true},
      }),
    );
    expect(
      () => AuthUser.fromJson({
        'id': 'user-2',
        'roles': 'admin',
        'attributes': 'not-a-map',
      }),
      returnsNormally,
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

  test(
    'persisted session records contain only a token digest and lifecycle data',
    () {
      final now = DateTime.utc(2030);
      final record = AuthSessionRecord(
        id: 'session-1',
        tokenHash: hashOpaqueToken('session-secret'),
        userId: 'user-1',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        lastUsedAt: now,
        authenticationMethod: 'password',
        ipAddress: '192.0.2.1',
        userAgent: 'test-agent',
      );

      final json = record.toStorageJson();

      expect(record.isActive(now: now), isTrue);
      expect(json['token_hash'], equals(record.tokenHash));
      expect(json.containsKey('session-secret'), isFalse);
      expect(json['user_id'], equals('user-1'));
    },
  );

  test('password credential records never serialize plaintext passwords', () {
    final credential = AuthPasswordCredential(
      id: 'credential-1',
      userId: 'user-1',
      identifier: 'user@example.com',
      passwordHash: hashOpaqueToken('encoded-hash-placeholder'),
      createdAt: DateTime.utc(2030),
      updatedAt: DateTime.utc(2030),
    );

    final json = credential.toStorageJson();

    expect(json.containsKey('password'), isFalse);
    expect(json['password_hash'], equals(credential.passwordHash));
    expect(json.containsValue('encoded-hash-placeholder'), isFalse);
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

  test(
    'account redaction removes provider tokens and nested metadata secrets',
    () {
      final account = AuthAccount(
        providerId: 'github',
        providerAccountId: 'account-1',
        accessToken: 'access-secret',
        refreshToken: 'refresh-secret',
        metadata: {
          'display_name': 'Alice',
          'nested': {'client_secret': 'client-secret'},
        },
      );

      final redacted = account.redacted();

      expect(redacted.accessToken, isNull);
      expect(redacted.refreshToken, isNull);
      expect(
        redacted.metadata,
        equals({'display_name': 'Alice', 'nested': {}}),
      );
    },
  );

  test('user and session redaction removes nested attributes and JWTs', () {
    final session = AuthSession(
      user: AuthUser(
        id: 'user-1',
        attributes: {
          'nested': {'access_token': 'secret'},
        },
      ),
      expiresAt: DateTime.utc(2030),
      strategy: AuthSessionStrategy.jwt,
      token: 'jwt-secret',
    );

    final redacted = session.redacted();

    expect(redacted.token, isNull);
    expect(redacted.user.attributes, equals({'nested': {}}));
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

  test(
    'credential redaction removes password aliases before event retention',
    () {
      final credentials = AuthCredentials.fromMap({
        'email': 'user@example.com',
        'password': 'plain-text',
        'password_hash': 'encoded-secret',
        'passphrase': 'another-secret',
        'remember_me': true,
        'nested': {'password': 'nested-secret'},
      });

      final redacted = credentials.redacted();

      expect(redacted.password, isNull);
      expect(redacted.attributes.containsKey('password_hash'), isFalse);
      expect(redacted.attributes.containsKey('passphrase'), isFalse);
      expect(redacted.attributes['remember_me'], isTrue);
      expect(redacted.attributes['nested'], equals(<String, dynamic>{}));
    },
  );
}
