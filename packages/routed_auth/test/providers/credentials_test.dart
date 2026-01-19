import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('CredentialsProvider', () {
    test('creates provider with default id and name', () {
      final provider = CredentialsProvider();

      expect(provider.id, equals('credentials'));
      expect(provider.name, equals('Credentials'));
      expect(provider.type, equals(AuthProviderType.credentials));
    });

    test('creates provider with custom id and name', () {
      final provider = CredentialsProvider(
        id: 'custom-login',
        name: 'Custom Login',
      );

      expect(provider.id, equals('custom-login'));
      expect(provider.name, equals('Custom Login'));
    });

    test('authorize callback is invoked with credentials', () async {
      AuthCredentials? receivedCredentials;
      final provider = CredentialsProvider(
        authorize: (context, provider, credentials) {
          receivedCredentials = credentials;
          if (credentials.email == 'user@example.com' &&
              credentials.password == 'secret123') {
            return AuthUser(
              id: 'user-1',
              email: credentials.email,
              name: 'Test User',
            );
          }
          return null;
        },
      );

      // Simulate calling authorize (would normally come from routes)
      final credentials = AuthCredentials(
        email: 'user@example.com',
        password: 'secret123',
      );

      // Call the authorize callback directly
      final result = await provider.authorize?.call(
        _MockEngineContext(),
        provider,
        credentials,
      );

      expect(receivedCredentials?.email, equals('user@example.com'));
      expect(receivedCredentials?.password, equals('secret123'));
      expect(result?.id, equals('user-1'));
    });

    test('authorize returns null for invalid credentials', () async {
      final provider = CredentialsProvider(
        authorize: (context, provider, credentials) {
          if (credentials.password == 'correct') {
            return AuthUser(id: 'user-1');
          }
          return null;
        },
      );

      final result = await provider.authorize?.call(
        _MockEngineContext(),
        provider,
        AuthCredentials(email: 'user@example.com', password: 'wrong'),
      );

      expect(result, isNull);
    });

    test('register callback creates new users', () async {
      final registeredUsers = <AuthUser>[];
      final provider = CredentialsProvider(
        register: (context, provider, credentials) {
          if (credentials.email != null && credentials.password != null) {
            final user = AuthUser(
              id: 'new-${registeredUsers.length + 1}',
              email: credentials.email,
              name: credentials.attributes['name']?.toString(),
            );
            registeredUsers.add(user);
            return user;
          }
          return null;
        },
      );

      final result1 = await provider.register?.call(
        _MockEngineContext(),
        provider,
        AuthCredentials(
          email: 'new@example.com',
          password: 'pass123',
          attributes: {'name': 'New User'},
        ),
      );

      final result2 = await provider.register?.call(
        _MockEngineContext(),
        provider,
        AuthCredentials(
          email: 'another@example.com',
          password: 'pass456',
        ),
      );

      expect(registeredUsers.length, equals(2));
      expect(result1?.email, equals('new@example.com'));
      expect(result1?.name, equals('New User'));
      expect(result2?.id, equals('new-2'));
    });

    test('register returns null when required fields missing', () async {
      final provider = CredentialsProvider(
        register: (context, provider, credentials) {
          if (credentials.email == null || credentials.password == null) {
            return null;
          }
          return AuthUser(id: 'user-1', email: credentials.email);
        },
      );

      final missingEmail = await provider.register?.call(
        _MockEngineContext(),
        provider,
        AuthCredentials(password: 'pass'),
      );

      final missingPassword = await provider.register?.call(
        _MockEngineContext(),
        provider,
        AuthCredentials(email: 'user@example.com'),
      );

      expect(missingEmail, isNull);
      expect(missingPassword, isNull);
    });

    test('provider without callbacks returns null from nullable fields', () {
      final provider = CredentialsProvider();

      expect(provider.authorize, isNull);
      expect(provider.register, isNull);
    });

    test('toJson returns provider metadata', () {
      final provider = CredentialsProvider(
        id: 'login',
        name: 'Login',
      );

      final json = provider.toJson();

      expect(json['id'], equals('login'));
      expect(json['name'], equals('Login'));
      expect(json['type'], equals('credentials'));
    });

    test('supports username-based authentication', () async {
      final provider = CredentialsProvider(
        authorize: (context, provider, credentials) {
          final identifier = credentials.username ?? credentials.email;
          if (identifier == 'admin' && credentials.password == 'admin123') {
            return AuthUser(id: 'admin-1', name: 'Administrator');
          }
          return null;
        },
      );

      final result = await provider.authorize?.call(
        _MockEngineContext(),
        provider,
        AuthCredentials(username: 'admin', password: 'admin123'),
      );

      expect(result?.id, equals('admin-1'));
      expect(result?.name, equals('Administrator'));
    });

    test('credentials fromMap extracts all fields', () {
      final credentials = AuthCredentials.fromMap({
        'email': 'user@example.com',
        'username': 'user123',
        'password': 'secret',
        'remember_me': true,
        'csrf_token': 'abc123',
      });

      expect(credentials.email, equals('user@example.com'));
      expect(credentials.username, equals('user123'));
      expect(credentials.password, equals('secret'));
      expect(credentials.attributes['remember_me'], equals(true));
      expect(credentials.attributes['csrf_token'], equals('abc123'));
    });
  });
}

/// Minimal mock for EngineContext - tests don't need full context.
class _MockEngineContext implements EngineContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
