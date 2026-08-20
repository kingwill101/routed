import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  final suite = AuthWebAuthnStoreConformanceSuite(
    () =>
        AuthWebAuthnStoreConformanceFixture(capabilities: InMemoryAuthStore()),
  );

  for (final testCase in suite.cases) {
    test('in-memory WebAuthn conformance: ${testCase.id}', testCase.run);
  }

  test(
    'passkey removal fails closed without the exact mutation store',
    () async {
      final root = InMemoryAuthStore();
      final capabilities = _ReadWriteOnlyWebAuthnCapabilities();
      final plugin = WebAuthnPlugin<Object>(
        provider: _provider,
        storage: capabilities,
      );
      final methods = AuthAuthenticationMethodService(store: root);
      plugin.configure(
        AuthServerPluginContext<Object>(
          store: root,
          authenticationMethods: methods,
        ),
      );
      methods.composeContributors([plugin]);
      await capabilities.webAuthnAuthenticators.create(
        WebAuthnAuthenticator(
          credentialId: 'credential-1',
          publicKey: 'public-key',
          counter: 0,
          userId: 'user-1',
          createdAt: DateTime.utc(2099),
        ),
      );

      await expectLater(
        plugin.deleteCredential(userId: 'user-1', credentialId: 'credential-1'),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'authentication_method_mutation_unavailable',
          ),
        ),
      );
      expect(
        await capabilities.webAuthnAuthenticators.findByCredentialId(
          'credential-1',
        ),
        isNotNull,
      );
    },
  );
}

final WebAuthnProvider _provider = WebAuthnProvider(
  getUserInfo: (_, _, _) => null,
  getRelyingParty: (_, _) => const WebAuthnRelyingParty(
    id: 'example.com',
    name: 'Example',
    origin: 'https://example.com',
  ),
);

final class _ReadWriteOnlyWebAuthnCapabilities
    implements AuthWebAuthnStoreCapabilities {
  _ReadWriteOnlyWebAuthnCapabilities();

  @override
  final AuthWebAuthnChallengeStore webAuthnChallenges =
      InMemoryAuthWebAuthnChallengeStore();

  @override
  final AuthWebAuthnAuthenticatorStore webAuthnAuthenticators =
      _ReadWriteOnlyWebAuthnAuthenticatorStore();
}

final class _ReadWriteOnlyWebAuthnAuthenticatorStore
    implements AuthWebAuthnAuthenticatorStore {
  final InMemoryAuthWebAuthnAuthenticatorStore _delegate =
      InMemoryAuthWebAuthnAuthenticatorStore();

  @override
  Future<WebAuthnAuthenticator> create(WebAuthnAuthenticator authenticator) =>
      Future.sync(() => _delegate.create(authenticator));

  @override
  Future<bool> deleteForUser(String userId, String credentialId) =>
      Future.sync(() => _delegate.deleteForUser(userId, credentialId));

  @override
  Future<WebAuthnAuthenticator?> findByCredentialId(String credentialId) =>
      Future.sync(() => _delegate.findByCredentialId(credentialId));

  @override
  Future<List<WebAuthnAuthenticator>> listForUser(String userId) =>
      Future.sync(() => _delegate.listForUser(userId));

  @override
  Future<WebAuthnAuthenticator?> renameForUser(
    String userId,
    String credentialId,
    String name,
  ) => Future.sync(() => _delegate.renameForUser(userId, credentialId, name));

  @override
  Future<WebAuthnAuthenticator?> updateUsage({
    required String credentialId,
    required int expectedCounter,
    required int newCounter,
    required DateTime lastUsedAt,
  }) => Future.sync(
    () => _delegate.updateUsage(
      credentialId: credentialId,
      expectedCounter: expectedCounter,
      newCounter: newCounter,
      lastUsedAt: lastUsedAt,
    ),
  );
}
