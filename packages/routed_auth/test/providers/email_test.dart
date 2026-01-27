import 'dart:async';

import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('EmailProvider', () {
    test('creates provider with default id and name', () {
      final provider = EmailProvider(sendVerificationRequest: (_, __, ___) {});

      expect(provider.id, equals('email'));
      expect(provider.name, equals('Email'));
      expect(provider.type, equals(AuthProviderType.email));
    });

    test('creates provider with custom id and name', () {
      final provider = EmailProvider(
        id: 'magic-link',
        name: 'Magic Link',
        sendVerificationRequest: (_, __, ___) {},
      );

      expect(provider.id, equals('magic-link'));
      expect(provider.name, equals('Magic Link'));
    });

    test('sends verification request with email and token', () async {
      AuthEmailRequest? sentRequest;
      final provider = EmailProvider(
        sendVerificationRequest: (context, provider, request) {
          sentRequest = request;
        },
      );

      final request = AuthEmailRequest(
        email: 'user@example.com',
        token: 'verify-token-123',
        callbackUrl:
            'https://example.com/auth/callback/email?token=verify-token-123',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      await provider.sendVerificationRequest(
        _MockEngineContext(),
        provider,
        request,
      );

      expect(sentRequest, isNotNull);
      expect(sentRequest?.email, equals('user@example.com'));
      expect(sentRequest?.token, equals('verify-token-123'));
      expect(sentRequest?.callbackUrl, contains('callback/email'));
    });

    test('default token expiry is 15 minutes', () {
      final provider = EmailProvider(sendVerificationRequest: (_, __, ___) {});

      expect(provider.tokenExpiry, equals(const Duration(minutes: 15)));
    });

    test('custom token expiry is respected', () {
      final provider = EmailProvider(
        sendVerificationRequest: (_, __, ___) {},
        tokenExpiry: const Duration(hours: 1),
      );

      expect(provider.tokenExpiry, equals(const Duration(hours: 1)));
    });

    test('custom token generator is used when provided', () {
      var callCount = 0;
      final provider = EmailProvider(
        sendVerificationRequest: (_, __, ___) {},
        tokenGenerator: () {
          callCount++;
          return 'custom-token-$callCount';
        },
      );

      final token1 = provider.tokenGenerator!();
      final token2 = provider.tokenGenerator!();

      expect(token1, equals('custom-token-1'));
      expect(token2, equals('custom-token-2'));
      expect(callCount, equals(2));
    });

    test('tokenGenerator is null by default', () {
      final provider = EmailProvider(sendVerificationRequest: (_, __, ___) {});

      expect(provider.tokenGenerator, isNull);
    });

    test('toJson returns provider metadata', () {
      final provider = EmailProvider(
        id: 'magic',
        name: 'Magic Link Login',
        sendVerificationRequest: (_, __, ___) {},
      );

      final json = provider.toJson();

      expect(json['id'], equals('magic'));
      expect(json['name'], equals('Magic Link Login'));
      expect(json['type'], equals('email'));
    });

    test('sendVerificationRequest can be async', () async {
      final completer = Completer<void>();
      var completed = false;

      final provider = EmailProvider(
        sendVerificationRequest: (context, provider, request) async {
          await Future.delayed(const Duration(milliseconds: 10));
          completed = true;
          completer.complete();
        },
      );

      final request = AuthEmailRequest(
        email: 'async@example.com',
        token: 'async-token',
        callbackUrl: 'https://example.com/callback',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      provider.sendVerificationRequest(_MockEngineContext(), provider, request);

      await completer.future;
      expect(completed, isTrue);
    });
  });

  group('AuthEmailRequest', () {
    test('stores all required fields', () {
      final expiresAt = DateTime.now().add(const Duration(minutes: 15));
      final request = AuthEmailRequest(
        email: 'test@example.com',
        token: 'abc123',
        callbackUrl: 'https://example.com/verify',
        expiresAt: expiresAt,
      );

      expect(request.email, equals('test@example.com'));
      expect(request.token, equals('abc123'));
      expect(request.callbackUrl, equals('https://example.com/verify'));
      expect(request.expiresAt, equals(expiresAt));
    });
  });

  group('Email verification flow integration', () {
    test('full flow with InMemoryAuthAdapter', () async {
      final adapter = InMemoryAuthAdapter();
      final sentTokens = <AuthEmailRequest>[];

      final provider = EmailProvider(
        sendVerificationRequest: (context, provider, request) {
          sentTokens.add(request);
        },
      );

      // Step 1: User requests sign-in, system generates token
      const email = 'flow@example.com';
      const token = 'flow-token-123';
      final expiresAt = DateTime.now().add(provider.tokenExpiry);

      final verificationToken = AuthVerificationToken(
        identifier: email,
        token: token,
        expiresAt: expiresAt,
      );

      // Step 2: Save token to adapter
      await adapter.saveVerificationToken(verificationToken);

      // Step 3: Send email with magic link
      final emailRequest = AuthEmailRequest(
        email: email,
        token: token,
        callbackUrl:
            'https://example.com/auth/callback/email?token=$token&email=$email',
        expiresAt: expiresAt,
      );
      await provider.sendVerificationRequest(
        _MockEngineContext(),
        provider,
        emailRequest,
      );

      expect(sentTokens.length, equals(1));
      expect(sentTokens.first.email, equals(email));

      // Step 4: User clicks link, system verifies token
      final verified = await adapter.useVerificationToken(email, token);
      expect(verified, isNotNull);
      expect(verified?.identifier, equals(email));

      // Step 5: Token is consumed (cannot be reused)
      final reused = await adapter.useVerificationToken(email, token);
      expect(reused, isNull);
    });

    test('expired tokens are rejected', () async {
      final adapter = InMemoryAuthAdapter();

      final expiredToken = AuthVerificationToken(
        identifier: 'expired@example.com',
        token: 'expired-token',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await adapter.saveVerificationToken(expiredToken);

      final result = await adapter.useVerificationToken(
        'expired@example.com',
        'expired-token',
      );

      expect(result, isNull);
    });

    test('wrong token is rejected', () async {
      final adapter = InMemoryAuthAdapter();

      final token = AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'correct-token',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      await adapter.saveVerificationToken(token);

      final result = await adapter.useVerificationToken(
        'user@example.com',
        'wrong-token',
      );

      expect(result, isNull);
    });

    test('wrong email is rejected', () async {
      final adapter = InMemoryAuthAdapter();

      final token = AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'the-token',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      await adapter.saveVerificationToken(token);

      final result = await adapter.useVerificationToken(
        'other@example.com',
        'the-token',
      );

      expect(result, isNull);
    });

    test(
      'deleteVerificationTokens removes all tokens for identifier',
      () async {
        final adapter = InMemoryAuthAdapter();

        await adapter.saveVerificationToken(
          AuthVerificationToken(
            identifier: 'user@example.com',
            token: 'token-1',
            expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          ),
        );

        await adapter.saveVerificationToken(
          AuthVerificationToken(
            identifier: 'user@example.com',
            token: 'token-2',
            expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          ),
        );

        await adapter.deleteVerificationTokens('user@example.com');

        final result1 = await adapter.useVerificationToken(
          'user@example.com',
          'token-1',
        );
        final result2 = await adapter.useVerificationToken(
          'user@example.com',
          'token-2',
        );

        expect(result1, isNull);
        expect(result2, isNull);
      },
    );

    test('createUser on first email sign-in', () async {
      final adapter = InMemoryAuthAdapter();

      // Simulate successful token verification
      final token = AuthVerificationToken(
        identifier: 'newuser@example.com',
        token: 'verify-token',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      await adapter.saveVerificationToken(token);

      final verified = await adapter.useVerificationToken(
        'newuser@example.com',
        'verify-token',
      );
      expect(verified, isNotNull);

      // Check if user exists
      var user = await adapter.getUserByEmail('newuser@example.com');
      expect(user, isNull);

      // Create user on first sign-in (like NextAuth does)
      user = await adapter.createUser(
        AuthUser(id: 'auto-generated-id', email: 'newuser@example.com'),
      );

      expect(user.email, equals('newuser@example.com'));

      // Subsequent sign-in finds existing user
      final existingUser = await adapter.getUserByEmail('newuser@example.com');
      expect(existingUser, isNotNull);
      expect(existingUser?.id, equals('auto-generated-id'));
    });
  });
}

/// Minimal mock for EngineContext - tests don't need full context.
class _MockEngineContext implements EngineContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
