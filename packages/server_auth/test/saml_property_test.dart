import 'package:property_testing/property_testing.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'property: arbitrary ACS payloads fail with stable public code',
    () async {
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 0, maxLength: 4096),
        (value) async {
          final plugin = _plugin();
          try {
            await _endpoint(plugin).invoke(
              const AuthOperationInvocation(
                context: 'browser-binding-value-0001',
                user: null,
              ),
              {
                'providerId': 'enterprise',
                'SAMLResponse': value,
                'RelayState': value,
              },
            );
            fail('Hostile payload unexpectedly authenticated');
          } on AuthFlowException catch (error) {
            expect(error.code, 'saml_authentication_failed');
            expect(
              error.toString(),
              'AuthFlowException(saml_authentication_failed)',
            );
          }
        },
        PropertyConfig(numTests: 300, seed: 20260820),
      );
      final result = await runner.run();
      expect(
        result.success,
        isTrue,
        reason: '${result.error} ${result.failingInput}',
      );
    },
  );
}

AuthSamlPlugin<String> _plugin() => AuthSamlPlugin<String>(
  connections: _Catalog(),
  replayStore: InMemoryAuthSamlReplayStore(),
  assertionVerifier: const _Verifier(),
  identityResolver: const _Resolver(),
  browserBindingResolver: (context) => context,
  clock: () => DateTime.parse('2030-01-01T12:00:00Z'),
  options: const AuthSamlOptions(allowInMemoryStoreForTesting: true),
);

AuthEndpointDescriptor<String> _endpoint(AuthSamlPlugin<String> plugin) =>
    plugin.endpoints.singleWhere((endpoint) => endpoint.id == 'saml.acs');

final class _Catalog implements AuthSamlConnectionCatalog {
  final connection = AuthSamlConnection(
    providerId: 'enterprise',
    idpEntityId: 'https://idp.example.test/entity',
    idpSsoUrl: Uri.parse('https://idp.example.test/sso'),
    idpSigningCertificate: 'PINNED CERTIFICATE',
    spEntityId: 'https://sp.example.test/entity',
    assertionConsumerServiceUrl: Uri.parse(
      'https://sp.example.test/auth/sso/saml/acs/enterprise',
    ),
  );

  @override
  AuthSamlConnection? findByProviderId(String providerId) =>
      providerId == connection.providerId ? connection : null;

  @override
  AuthSamlConnection? findByVerifiedDomain(String domain) => null;

  @override
  AuthSamlConnection? findByOrganizationSlug(String slug) => null;
}

final class _Verifier implements AuthSamlAssertionVerifier {
  const _Verifier();

  @override
  AuthSamlSignatureProof verify(AuthSamlVerificationInput input) =>
      AuthSamlSignatureProof(
        signedResponseId: null,
        signedAssertionId: input.assertionId,
        signatureAlgorithm: 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',
        digestAlgorithm: 'http://www.w3.org/2001/04/xmlenc#sha256',
        canonicalizationAlgorithm: 'http://www.w3.org/2001/10/xml-exc-c14n#',
      );
}

final class _Resolver implements AuthSamlIdentityResolver<String> {
  const _Resolver();

  @override
  AuthUser resolveOrProvision(AuthSamlIdentityInput<String> input) =>
      AuthUser(id: 'user-1', email: 'verified@example.test');
}
