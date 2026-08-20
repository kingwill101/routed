import 'dart:convert';

import 'package:property_testing/property_testing.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

const _now = '2030-01-01T12:00:00Z';
const _signatureAlgorithm = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256';
const _digestAlgorithm = 'http://www.w3.org/2001/04/xmlenc#sha256';
const _canonicalization = 'http://www.w3.org/2001/10/xml-exc-c14n#';

void main() {
  group('AuthSamlPlugin', () {
    test('requires durable atomic replay persistence by default', () {
      expect(() => _plugin(allowTestStore: false), throwsA(isA<StateError>()));
      expect(_plugin().validateProductionPosture, throwsA(isA<StateError>()));
      expect(
        _plugin(
          allowTestStore: false,
          replayStore: _DurableReplayStore(),
        ).validateProductionPosture,
        returnsNormally,
      );
    });

    test('satisfies composed plugin conformance', () async {
      final plugin = _plugin();
      final runtime = AuthRuntime<String>(
        options: AuthOptions<String>(
          providers: const [],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          plugins: [plugin],
        ),
      );
      final suite = AuthPluginConformanceSuite<String>.fromRuntime(runtime);
      for (final conformanceCase in suite.cases) {
        final result = await conformanceCase.run();
        expect(result.isPassed, isTrue, reason: conformanceCase.id);
      }
    });

    test('creates one-time browser-bound HTTP-POST AuthnRequest', () async {
      final plugin = _plugin();
      final signIn = _endpoint(plugin, 'saml.signIn');
      final first =
          await signIn.invoke(_invocation('browser-binding-value-0001'), const {
                'domain': 'example.test',
                'callbackUrl': '/dashboard',
              })
              as Map<String, dynamic>;

      expect(first['providerId'], 'enterprise');
      expect(first['destination'], 'https://idp.example.test/sso');
      final fields = Map<String, dynamic>.from(first['fields'] as Map);
      expect(fields['RelayState'], isNotEmpty);
      final xml = utf8.decode(base64.decode(fields['SAMLRequest'] as String));
      expect(xml, contains('samlp:AuthnRequest'));
      expect(xml, contains('AssertionConsumerServiceURL'));
      expect(xml, isNot(contains(fields['RelayState'])));
    });

    test(
      'publishes bounded SP metadata without the pinned certificate',
      () async {
        final response = await _endpoint(_plugin(), 'saml.metadata').invoke(
          _invocation('browser-binding-value-0001'),
          const {'providerId': 'enterprise'},
        );
        expect(response, isA<AuthEndpointHttpResponse>());
        final metadata = response as AuthEndpointHttpResponse;
        expect(
          metadata.headers['content-type'],
          startsWith('application/samlmetadata+xml'),
        );
        expect(metadata.body, isA<String>());
        final body = metadata.body! as String;
        expect(body, contains('WantAssertionsSigned="true"'));
        expect(
          body,
          contains('https://sp.example.test/auth/sso/saml/acs/enterprise'),
        );
        expect(body, isNot(contains('PINNED CERTIFICATE')));
      },
    );

    test(
      'accepts once, resolves only the stable SAML identity, then rejects replay',
      () async {
        AuthSamlAccountIdentity? resolved;
        final plugin = _plugin(onIdentity: (identity) => resolved = identity);
        final started = await _start(plugin);
        final responseXml = _response(
          requestId: started.requestId,
          assertionId: '_assertion-1',
          email: 'unverified@example.test',
        );
        final payload = {
          'providerId': 'enterprise',
          'SAMLResponse': base64.encode(utf8.encode(responseXml)),
          'RelayState': started.relayState,
        };
        final result = await _endpoint(
          plugin,
          'saml.acs',
        ).invoke(_invocation('browser-binding-value-0001'), payload);

        expect(result, isA<AuthEndpointAuthenticationIntent>());
        final intent = result as AuthEndpointAuthenticationIntent;
        expect(intent.authenticationMethod, 'saml:enterprise');
        expect(resolved!.stableKey, contains('signed-name-id'));
        expect(resolved!.stableKey, isNot(contains('unverified@example.test')));
        expect(
          await intent.projectResponse(const {'strategy': 'session'}),
          isA<AuthEndpointRedirect>(),
        );

        await expectLater(
          () => _endpoint(
            plugin,
            'saml.acs',
          ).invoke(_invocation('browser-binding-value-0001'), payload),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'saml_authentication_failed',
            ),
          ),
        );
      },
    );

    test('rejects cross-browser RelayState consumption', () async {
      final plugin = _plugin();
      final started = await _start(plugin);
      await expectLater(
        () => _endpoint(plugin, 'saml.acs')
            .invoke(_invocation('different-browser-value-0002'), {
              'providerId': 'enterprise',
              'SAMLResponse': base64.encode(
                utf8.encode(
                  _response(
                    requestId: started.requestId,
                    assertionId: '_assertion-browser',
                  ),
                ),
              ),
              'RelayState': started.relayState,
            }),
        throwsA(isA<AuthFlowException>()),
      );
    });

    test(
      'permits IdP initiation only with an explicit fixed callback',
      () async {
        final xml = _response(
          requestId: '_unused',
          assertionId: '_assertion-idp',
        ).replaceAll(' InResponseTo="_unused"', '');
        final disabled = _plugin();
        await expectLater(
          () => _endpoint(disabled, 'saml.acs')
              .invoke(_invocation('browser-binding-value-0001'), {
                'providerId': 'enterprise',
                'SAMLResponse': base64.encode(utf8.encode(xml)),
              }),
          throwsA(isA<AuthFlowException>()),
        );

        final enabled = _plugin(
          idpInitiated: AuthSamlIdpInitiatedPolicy.fixedCallback(
            Uri(path: '/idp-complete'),
          ),
        );
        final intent =
            await _endpoint(
                  enabled,
                  'saml.acs',
                ).invoke(_invocation('browser-binding-value-0001'), {
                  'providerId': 'enterprise',
                  'SAMLResponse': base64.encode(utf8.encode(xml)),
                })
                as AuthEndpointAuthenticationIntent;
        final projected = await intent.projectResponse(const {});
        expect(
          (projected as AuthEndpointRedirect).location.path,
          '/idp-complete',
        );
      },
    );

    test('rejects signature wrapping IDs and deprecated algorithms', () async {
      final wrapping = _plugin();
      final started = await _start(wrapping);
      final xml =
          _response(
            requestId: started.requestId,
            assertionId: '_duplicate',
          ).replaceFirst(
            '<saml:AttributeStatement>',
            '<saml:AttributeStatement><saml:Attribute ID="_duplicate" Name="wrapped"/>',
          );
      await _expectGenericFailure(wrapping, started, xml);

      final weak = _plugin(
        verifier: const _Verifier(
          signatureAlgorithm: 'http://www.w3.org/2000/09/xmldsig#rsa-sha1',
        ),
      );
      final weakStarted = await _start(weak);
      await _expectGenericFailure(
        weak,
        weakStarted,
        _response(
          requestId: weakStarted.requestId,
          assertionId: '_assertion-weak',
        ),
      );
    });

    test('rejects DTD, missing timestamps, and wrong provider binding', () async {
      final plugin = _plugin();
      final started = await _start(plugin);
      await _expectGenericFailure(
        plugin,
        started,
        '<!DOCTYPE saml [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>${_response(requestId: started.requestId, assertionId: '_a-dtd')}',
      );

      final missingTime = _plugin();
      final missingStarted = await _start(missingTime);
      await _expectGenericFailure(
        missingTime,
        missingStarted,
        _response(
          requestId: missingStarted.requestId,
          assertionId: '_a-time',
        ).replaceFirst(' NotBefore="2030-01-01T11:59:30Z"', ''),
      );

      final wrongProvider = _plugin();
      final wrongStarted = await _start(wrongProvider);
      await expectLater(
        () => _endpoint(wrongProvider, 'saml.acs')
            .invoke(_invocation('browser-binding-value-0001'), {
              'providerId': 'other',
              'SAMLResponse': base64.encode(
                utf8.encode(
                  _response(
                    requestId: wrongStarted.requestId,
                    assertionId: '_a-provider',
                  ),
                ),
              ),
              'RelayState': wrongStarted.relayState,
            }),
        throwsA(isA<AuthFlowException>()),
      );
    });

    test(
      'property: arbitrary ACS payloads fail with stable public code',
      () async {
        final runner = PropertyTestRunner<String>(
          Chaos.string(minLength: 0, maxLength: 4096),
          (value) async {
            final plugin = _plugin();
            try {
              await _endpoint(
                plugin,
                'saml.acs',
              ).invoke(_invocation('browser-binding-value-0001'), {
                'providerId': 'enterprise',
                'SAMLResponse': value,
                'RelayState': value,
              });
              fail('Hostile payload unexpectedly authenticated');
            } on AuthFlowException catch (error) {
              expect(error.code, 'saml_authentication_failed');
              expect(error.toString(), isNot(contains(value)));
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
  });
}

AuthSamlPlugin<String> _plugin({
  bool allowTestStore = true,
  _Verifier verifier = const _Verifier(),
  AuthSamlReplayStore? replayStore,
  AuthSamlIdpInitiatedPolicy idpInitiated =
      const AuthSamlIdpInitiatedPolicy.disabled(),
  void Function(AuthSamlAccountIdentity identity)? onIdentity,
}) => AuthSamlPlugin<String>(
  connections: _Catalog(),
  replayStore: replayStore ?? InMemoryAuthSamlReplayStore(),
  assertionVerifier: verifier,
  identityResolver: _Resolver(onIdentity),
  browserBindingResolver: (context) => context,
  clock: () => DateTime.parse(_now),
  options: AuthSamlOptions(
    allowInMemoryStoreForTesting: allowTestStore,
    idpInitiated: idpInitiated,
    redirectPolicy: AuthSamlRedirectPolicy(
      trustedOrigins: {Uri.parse('https://app.example.test')},
    ),
  ),
);

AuthOperationInvocation<String> _invocation(String binding) =>
    AuthOperationInvocation(context: binding, user: null);

AuthEndpointDescriptor<String> _endpoint(
  AuthSamlPlugin<String> plugin,
  String id,
) => plugin.endpoints.singleWhere((endpoint) => endpoint.id == id);

Future<_Started> _start(AuthSamlPlugin<String> plugin) async {
  final response =
      await _endpoint(plugin, 'saml.signIn').invoke(
            _invocation('browser-binding-value-0001'),
            const {'providerId': 'enterprise', 'callbackUrl': '/dashboard'},
          )
          as Map<String, dynamic>;
  final fields = Map<String, dynamic>.from(response['fields'] as Map);
  final xml = utf8.decode(base64.decode(fields['SAMLRequest'] as String));
  final requestId = RegExp(r' ID="([^"]+)"').firstMatch(xml)!.group(1)!;
  return _Started(requestId, fields['RelayState'] as String);
}

Future<void> _expectGenericFailure(
  AuthSamlPlugin<String> plugin,
  _Started started,
  String xml,
) => expectLater(
  () => _endpoint(plugin, 'saml.acs')
      .invoke(_invocation('browser-binding-value-0001'), {
        'providerId': 'enterprise',
        'SAMLResponse': base64.encode(utf8.encode(xml)),
        'RelayState': started.relayState,
      }),
  throwsA(
    isA<AuthFlowException>().having(
      (error) => error.code,
      'code',
      'saml_authentication_failed',
    ),
  ),
);

String _response({
  required String requestId,
  required String assertionId,
  String email = 'user@example.test',
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="_response-$assertionId" Version="2.0" IssueInstant="2030-01-01T12:00:00Z" Destination="https://sp.example.test/auth/sso/saml/acs/enterprise" InResponseTo="$requestId">
  <saml:Issuer>https://idp.example.test/entity</saml:Issuer>
  <samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>
  <saml:Assertion ID="$assertionId" Version="2.0" IssueInstant="2030-01-01T12:00:00Z">
    <saml:Issuer>https://idp.example.test/entity</saml:Issuer>
    <saml:Subject>
      <saml:NameID Format="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent">signed-name-id</saml:NameID>
      <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
        <saml:SubjectConfirmationData Recipient="https://sp.example.test/auth/sso/saml/acs/enterprise" InResponseTo="$requestId" NotOnOrAfter="2030-01-01T12:05:00Z"/>
      </saml:SubjectConfirmation>
    </saml:Subject>
    <saml:Conditions NotBefore="2030-01-01T11:59:30Z" NotOnOrAfter="2030-01-01T12:05:00Z">
      <saml:AudienceRestriction><saml:Audience>https://sp.example.test/entity</saml:Audience></saml:AudienceRestriction>
    </saml:Conditions>
    <saml:AttributeStatement>
      <saml:Attribute Name="email"><saml:AttributeValue>$email</saml:AttributeValue></saml:Attribute>
    </saml:AttributeStatement>
  </saml:Assertion>
</samlp:Response>''';

final class _Started {
  const _Started(this.requestId, this.relayState);
  final String requestId;
  final String relayState;
}

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
    verifiedDomains: const {'example.test'},
    organizationSlug: 'example',
  );

  @override
  AuthSamlConnection? findByProviderId(String providerId) =>
      providerId == connection.providerId ? connection : null;
  @override
  AuthSamlConnection? findByVerifiedDomain(String domain) =>
      connection.verifiedDomains.contains(domain) ? connection : null;
  @override
  AuthSamlConnection? findByOrganizationSlug(String slug) =>
      slug == connection.organizationSlug ? connection : null;
}

final class _Verifier implements AuthSamlAssertionVerifier {
  const _Verifier({this.signatureAlgorithm = _signatureAlgorithm});
  final String signatureAlgorithm;

  @override
  AuthSamlSignatureProof verify(AuthSamlVerificationInput input) =>
      AuthSamlSignatureProof(
        signedResponseId: null,
        signedAssertionId: input.assertionId,
        signatureAlgorithm: signatureAlgorithm,
        digestAlgorithm: _digestAlgorithm,
        canonicalizationAlgorithm: _canonicalization,
      );
}

final class _Resolver implements AuthSamlIdentityResolver<String> {
  const _Resolver(this.onIdentity);
  final void Function(AuthSamlAccountIdentity identity)? onIdentity;

  @override
  AuthUser resolveOrProvision(AuthSamlIdentityInput<String> input) {
    onIdentity?.call(input.identity);
    return AuthUser(
      id: 'user-1',
      email: 'verified-by-application@example.test',
    );
  }
}

final class _DurableReplayStore implements AuthDurableSamlReplayStore {
  final _delegate = InMemoryAuthSamlReplayStore();

  @override
  Future<void> createAttempt(AuthSamlAuthenticationAttempt attempt) =>
      _delegate.createAttempt(attempt);

  @override
  Future<AuthSamlConsumptionResult> consumeSpInitiated({
    required String providerId,
    required String requestId,
    required String relayStateHash,
    required String browserBindingHash,
    required String assertionId,
    required DateTime assertionExpiresAt,
    required DateTime now,
  }) => _delegate.consumeSpInitiated(
    providerId: providerId,
    requestId: requestId,
    relayStateHash: relayStateHash,
    browserBindingHash: browserBindingHash,
    assertionId: assertionId,
    assertionExpiresAt: assertionExpiresAt,
    now: now,
  );

  @override
  Future<bool> consumeIdpInitiated({
    required String providerId,
    required String assertionId,
    required DateTime assertionExpiresAt,
    required DateTime now,
  }) => _delegate.consumeIdpInitiated(
    providerId: providerId,
    assertionId: assertionId,
    assertionExpiresAt: assertionExpiresAt,
    now: now,
  );
}
