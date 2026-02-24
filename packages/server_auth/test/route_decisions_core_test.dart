import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

class _CustomCallbackProvider extends AuthProvider with CallbackProvider {
  _CustomCallbackProvider()
    : super(
        id: 'custom-callback',
        name: 'Custom Callback',
        type: AuthProviderType.oauth,
      );

  @override
  CallbackResult handleCallback(AuthContext ctx, Map<String, String> params) {
    return const CallbackResult.failure('not-implemented');
  }
}

OAuthProvider<Map<String, dynamic>> _oauthProvider() {
  return OAuthProvider<Map<String, dynamic>>(
    id: 'oauth',
    name: 'OAuth',
    clientId: 'client-id',
    clientSecret: 'client-secret',
    authorizationEndpoint: Uri.parse('https://auth.example.test/authorize'),
    tokenEndpoint: Uri.parse('https://auth.example.test/token'),
    redirectUri: 'https://app.example.test/auth/callback/oauth',
    profile: (profile) => AuthUser(id: profile['id']?.toString() ?? 'user-1'),
  );
}

void main() {
  group('resolveAuthSignInRouteDecision', () {
    test('returns missing_provider when provider id is absent', () {
      final decision = resolveAuthSignInRouteDecision(
        providerId: null,
        provider: null,
        method: 'POST',
        payload: const <String, dynamic>{},
        csrfValid: true,
      );

      expect(decision.kind, equals(AuthSignInRouteKind.error));
      expect(decision.errorCode, equals('missing_provider'));
      expect(decision.requiresCsrf, isFalse);
    });

    test('returns unknown_provider when provider is unresolved', () {
      final decision = resolveAuthSignInRouteDecision(
        providerId: 'missing',
        provider: null,
        method: 'POST',
        payload: const <String, dynamic>{},
        csrfValid: true,
      );

      expect(decision.kind, equals(AuthSignInRouteKind.error));
      expect(decision.errorCode, equals('unknown_provider'));
      expect(decision.requiresCsrf, isFalse);
    });

    test('oauth provider short-circuits before method and csrf checks', () {
      final decision = resolveAuthSignInRouteDecision(
        providerId: 'oauth',
        provider: _oauthProvider(),
        method: 'GET',
        payload: const <String, dynamic>{},
        csrfValid: false,
      );

      expect(decision.kind, equals(AuthSignInRouteKind.oauth));
      expect(decision.errorCode, isNull);
      expect(decision.requiresCsrf, isFalse);
    });

    test('non-oauth GET returns method_not_allowed', () {
      final decision = resolveAuthSignInRouteDecision(
        providerId: 'credentials',
        provider: CredentialsProvider(),
        method: 'GET',
        payload: const <String, dynamic>{},
        csrfValid: true,
      );

      expect(decision.kind, equals(AuthSignInRouteKind.error));
      expect(decision.errorCode, equals('method_not_allowed'));
      expect(decision.requiresCsrf, isFalse);
    });

    test('csrf failure returns invalid_csrf for non-oauth POST', () {
      final decision = resolveAuthSignInRouteDecision(
        providerId: 'credentials',
        provider: CredentialsProvider(),
        method: 'POST',
        payload: const <String, dynamic>{},
        csrfValid: false,
      );

      expect(decision.kind, equals(AuthSignInRouteKind.error));
      expect(decision.errorCode, equals('invalid_csrf'));
      expect(decision.requiresCsrf, isTrue);
    });

    test('email provider requires non-empty email', () {
      final missingEmail = resolveAuthSignInRouteDecision(
        providerId: 'email',
        provider: EmailProvider(sendVerificationRequest: (_, _, _) async {}),
        method: 'POST',
        payload: const <String, dynamic>{},
        csrfValid: true,
      );
      final withEmail = resolveAuthSignInRouteDecision(
        providerId: 'email',
        provider: EmailProvider(sendVerificationRequest: (_, _, _) async {}),
        method: 'POST',
        payload: const <String, dynamic>{'email': 'person@example.com'},
        csrfValid: true,
      );

      expect(missingEmail.kind, equals(AuthSignInRouteKind.error));
      expect(missingEmail.errorCode, equals('missing_email'));
      expect(missingEmail.requiresCsrf, isTrue);
      expect(withEmail.kind, equals(AuthSignInRouteKind.email));
      expect(withEmail.email, equals('person@example.com'));
      expect(withEmail.requiresCsrf, isTrue);
    });

    test('credentials provider chooses credentials branch', () {
      final decision = resolveAuthSignInRouteDecision(
        providerId: 'credentials',
        provider: CredentialsProvider(),
        method: 'POST',
        payload: const <String, dynamic>{'email': 'user@example.com'},
        csrfValid: true,
      );

      expect(decision.kind, equals(AuthSignInRouteKind.credentials));
      expect(decision.errorCode, isNull);
      expect(decision.requiresCsrf, isTrue);
    });

    test('unsupported provider returns unsupported_provider', () {
      final decision = resolveAuthSignInRouteDecision(
        providerId: 'webauthn',
        provider: AuthProvider(
          id: 'webauthn',
          name: 'WebAuthn',
          type: AuthProviderType.webauthn,
        ),
        method: 'POST',
        payload: const <String, dynamic>{},
        csrfValid: true,
      );

      expect(decision.kind, equals(AuthSignInRouteKind.error));
      expect(decision.errorCode, equals('unsupported_provider'));
      expect(decision.requiresCsrf, isTrue);
    });
  });

  group('resolveAuthRegisterRouteDecision', () {
    test('returns missing_provider and unknown_provider errors', () {
      final missing = resolveAuthRegisterRouteDecision(
        providerId: '',
        provider: null,
        csrfValid: true,
      );
      final unknown = resolveAuthRegisterRouteDecision(
        providerId: 'missing',
        provider: null,
        csrfValid: true,
      );

      expect(missing.kind, equals(AuthRegisterRouteKind.error));
      expect(missing.errorCode, equals('missing_provider'));
      expect(missing.requiresCsrf, isFalse);
      expect(unknown.kind, equals(AuthRegisterRouteKind.error));
      expect(unknown.errorCode, equals('unknown_provider'));
      expect(unknown.requiresCsrf, isFalse);
    });

    test('requires csrf before provider-specific register branch', () {
      final csrfFailure = resolveAuthRegisterRouteDecision(
        providerId: 'credentials',
        provider: CredentialsProvider(),
        csrfValid: false,
      );
      final success = resolveAuthRegisterRouteDecision(
        providerId: 'credentials',
        provider: CredentialsProvider(),
        csrfValid: true,
      );

      expect(csrfFailure.kind, equals(AuthRegisterRouteKind.error));
      expect(csrfFailure.errorCode, equals('invalid_csrf'));
      expect(csrfFailure.requiresCsrf, isTrue);
      expect(success.kind, equals(AuthRegisterRouteKind.credentials));
      expect(success.errorCode, isNull);
      expect(success.requiresCsrf, isTrue);
    });

    test('unsupported provider returns unsupported_provider', () {
      final decision = resolveAuthRegisterRouteDecision(
        providerId: 'email',
        provider: EmailProvider(sendVerificationRequest: (_, _, _) async {}),
        csrfValid: true,
      );

      expect(decision.kind, equals(AuthRegisterRouteKind.error));
      expect(decision.errorCode, equals('unsupported_provider'));
      expect(decision.requiresCsrf, isTrue);
    });
  });

  group('resolveAuthCallbackRouteDecision', () {
    test('returns missing_provider and unknown_provider errors', () {
      final missing = resolveAuthCallbackRouteDecision(
        providerId: null,
        provider: null,
        query: const <String, dynamic>{},
      );
      final unknown = resolveAuthCallbackRouteDecision(
        providerId: 'missing',
        provider: null,
        query: const <String, dynamic>{},
      );

      expect(missing.kind, equals(AuthCallbackRouteKind.error));
      expect(missing.errorCode, equals('missing_provider'));
      expect(unknown.kind, equals(AuthCallbackRouteKind.error));
      expect(unknown.errorCode, equals('unknown_provider'));
    });

    test('oauth callback requires code and keeps optional state', () {
      final missingCode = resolveAuthCallbackRouteDecision(
        providerId: 'oauth',
        provider: _oauthProvider(),
        query: const <String, dynamic>{'state': 's1'},
      );
      final success = resolveAuthCallbackRouteDecision(
        providerId: 'oauth',
        provider: _oauthProvider(),
        query: const <String, dynamic>{'code': 'code-1', 'state': 's1'},
      );

      expect(missingCode.kind, equals(AuthCallbackRouteKind.error));
      expect(missingCode.errorCode, equals('missing_code'));
      expect(success.kind, equals(AuthCallbackRouteKind.oauth));
      expect(success.code, equals('code-1'));
      expect(success.state, equals('s1'));
    });

    test('email callback requires token and email or identifier', () {
      final missingToken = resolveAuthCallbackRouteDecision(
        providerId: 'email',
        provider: EmailProvider(sendVerificationRequest: (_, _, _) async {}),
        query: const <String, dynamic>{'email': 'mail@example.com'},
      );
      final missingEmail = resolveAuthCallbackRouteDecision(
        providerId: 'email',
        provider: EmailProvider(sendVerificationRequest: (_, _, _) async {}),
        query: const <String, dynamic>{'token': 'tok-1'},
      );
      final success = resolveAuthCallbackRouteDecision(
        providerId: 'email',
        provider: EmailProvider(sendVerificationRequest: (_, _, _) async {}),
        query: const <String, dynamic>{
          'token': 'tok-1',
          'identifier': 'mail@example.com',
        },
      );

      expect(missingToken.kind, equals(AuthCallbackRouteKind.error));
      expect(missingToken.errorCode, equals('missing_token'));
      expect(missingEmail.kind, equals(AuthCallbackRouteKind.error));
      expect(missingEmail.errorCode, equals('missing_token'));
      expect(success.kind, equals(AuthCallbackRouteKind.email));
      expect(success.token, equals('tok-1'));
      expect(success.email, equals('mail@example.com'));
    });

    test('callback provider selects custom branch', () {
      final decision = resolveAuthCallbackRouteDecision(
        providerId: 'custom-callback',
        provider: _CustomCallbackProvider(),
        query: const <String, dynamic>{},
      );

      expect(decision.kind, equals(AuthCallbackRouteKind.custom));
      expect(decision.errorCode, isNull);
    });

    test('unsupported provider returns unsupported_provider', () {
      final decision = resolveAuthCallbackRouteDecision(
        providerId: 'credentials',
        provider: CredentialsProvider(),
        query: const <String, dynamic>{},
      );

      expect(decision.kind, equals(AuthCallbackRouteKind.error));
      expect(decision.errorCode, equals('unsupported_provider'));
    });
  });
}
