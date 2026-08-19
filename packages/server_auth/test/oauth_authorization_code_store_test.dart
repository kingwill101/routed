import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'authorization codes are hash-only and one-time with S256 PKCE',
    () async {
      final store = InMemoryAuthOAuthAuthorizationCodeStore();
      final service = AuthOAuthAuthorizationCodeService(store: store);
      final code = await service.issue(
        rawCode: 'raw-code-secret',
        clientId: 'mcp-client',
        userId: 'user-1',
        redirectUri: Uri.parse('https://client.example/callback'),
        scopes: const ['mcp:read'],
        codeChallenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
        codeChallengeMethod: 'S256',
        nonce: 'nonce-1',
      );

      expect(code.codeHash, isNot(contains('raw-code-secret')));
      expect(code.toStorageJson(), isNot(contains('raw-code-secret')));
      expect(
        await service.exchange(
          rawCode: 'raw-code-secret',
          clientId: 'mcp-client',
          redirectUri: Uri.parse('https://client.example/callback'),
          codeVerifier: 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        same(code),
      );
      expect(
        await service.exchange(
          rawCode: 'raw-code-secret',
          clientId: 'mcp-client',
          redirectUri: Uri.parse('https://client.example/callback'),
          codeVerifier: 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        isNull,
      );
    },
  );

  test('binding failures consume a code and do not reveal its state', () async {
    final store = InMemoryAuthOAuthAuthorizationCodeStore();
    final service = AuthOAuthAuthorizationCodeService(store: store);
    await service.issue(
      rawCode: 'code-1',
      clientId: 'client-1',
      userId: 'user-1',
      redirectUri: Uri.parse('https://client.example/callback'),
      scopes: const [],
      codeChallenge: 'challenge',
      codeChallengeMethod: 'S256',
    );

    expect(
      await service.exchange(
        rawCode: 'code-1',
        clientId: 'other-client',
        redirectUri: Uri.parse('https://client.example/callback'),
        codeVerifier: 'verifier',
      ),
      isNull,
    );
    expect(
      await service.exchange(
        rawCode: 'code-1',
        clientId: 'client-1',
        redirectUri: Uri.parse('https://client.example/callback'),
        codeVerifier: 'verifier',
      ),
      isNull,
    );
  });

  test('issue rejects insecure authorization-code configuration', () async {
    final service = AuthOAuthAuthorizationCodeService(
      store: InMemoryAuthOAuthAuthorizationCodeStore(),
    );
    expect(
      () => service.issue(
        rawCode: 'code-1',
        clientId: 'client-1',
        userId: 'user-1',
        redirectUri: Uri.parse('https://client.example/callback#fragment'),
        scopes: const [],
        codeChallenge: 'challenge',
        codeChallengeMethod: 'plain',
      ),
      throwsArgumentError,
    );
  });
}
