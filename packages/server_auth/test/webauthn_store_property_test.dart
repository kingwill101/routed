import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('concurrent generated removals always preserve one passkey', () async {
    final runner = PropertyTestRunner<int>(Gen.integer(min: 2, max: 24), (
      credentialCount,
    ) async {
      final store = InMemoryAuthStore();
      final plugin = WebAuthnPlugin<Object>(provider: _provider);
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: [_provider],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [plugin],
        ),
      );
      for (var index = 0; index < credentialCount; index++) {
        await store.webAuthnAuthenticators.create(
          WebAuthnAuthenticator(
            credentialId: 'credential-$index',
            publicKey: 'public-key-$index',
            counter: index,
            userId: 'user-1',
            createdAt: DateTime.utc(2099),
          ),
        );
      }

      final outcomes = await Future.wait([
        for (var index = 0; index < credentialCount; index++)
          plugin
              .deleteCredential(
                userId: 'user-1',
                credentialId: 'credential-$index',
              )
              .then<String>((_) => 'deleted')
              .catchError(
                (Object error) => error is AuthFlowException
                    ? error.code
                    : Error.throwWithStackTrace(error, StackTrace.current),
              ),
      ]);

      expect(
        await store.webAuthnAuthenticators.listForUser('user-1'),
        hasLength(1),
      );
      expect(
        outcomes.where((value) => value == 'deleted'),
        hasLength(credentialCount - 1),
      );
      expect(
        outcomes.where((value) => value == 'last_authentication_method'),
        hasLength(1),
      );
    }, PropertyConfig(numTests: 128, seed: 20260820));

    final result = await runner.run();
    expect(
      result.success,
      isTrue,
      reason:
          'Property failed after ${result.numTests} cases: '
          '${result.error}; input=${result.failingInput}; seed=${result.seed}',
    );
  });
}

final WebAuthnProvider _provider = WebAuthnProvider(
  getUserInfo: (_, _, _) => null,
  getRelyingParty: (_, _) => const WebAuthnRelyingParty(
    id: 'example.com',
    name: 'Example',
    origin: 'https://example.com',
  ),
);
