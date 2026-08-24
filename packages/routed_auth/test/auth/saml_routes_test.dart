import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  test(
    'Routed serves metadata and completes SAML through host session issuance',
    () async {
      final store = InMemoryAuthStore();
      final user = await store.users.create(
        AuthUser(id: 'saml-user', email: 'application-verified@example.test'),
      );
      final plugin = AuthSamlPlugin<EngineContext>(
        connections: _Catalog(),
        replayStore: InMemoryAuthSamlReplayStore(),
        assertionVerifier: const _Verifier(),
        identityResolver: _Resolver(user),
        browserBindingResolver: (context) => context.sessionId,
        clock: () => DateTime.parse('2030-01-01T12:00:00Z'),
        options: const AuthSamlOptions(allowInMemoryStoreForTesting: true),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [plugin],
          enforceCsrf: false,
        ),
      );
      final key = base64.encode(List<int>.generate(32, (index) => index + 1));
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        providers: [
          RoutedSessionsProvider(
            SessionConfig.cookie(
              appKey: 'base64:$key',
              cookieName: 'saml_route_session',
              options: SessionOptions(
                secure: false,
                httpOnly: true,
                sameSite: SameSite.lax,
              ),
            ),
          ),
        ],
      );
      engine.addGlobalMiddleware(sessionMiddleware());
      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
      AuthRoutes(manager).register(engine.defaultRouter);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final metadata = await client.get('/auth/sso/saml/metadata/enterprise');
      metadata.assertStatus(HttpStatus.ok);
      expect(
        metadata.headers['content-type']?.single,
        contains('application/samlmetadata+xml'),
      );
      expect(metadata.body, contains('WantAssertionsSigned="true"'));

      final started = await client.postJson('/auth/sso/saml/sign-in', {
        'providerId': 'enterprise',
        'callbackUrl': '/dashboard',
      });
      started.assertStatus(HttpStatus.ok);
      final sessionCookie = started.cookie('saml_route_session')!;
      final fields = Map<String, dynamic>.from(started.json()['fields'] as Map);
      final requestXml = utf8.decode(
        base64.decode(fields['SAMLRequest'] as String),
      );
      final requestId = RegExp(
        ' ID="([^"]+)"',
      ).firstMatch(requestXml)!.group(1)!;
      final response = _response(requestId);
      final form = Uri(
        queryParameters: {
          'SAMLResponse': base64.encode(utf8.encode(response)),
          'RelayState': fields['RelayState'] as String,
        },
      ).query;
      final completed = await client.post(
        '/auth/sso/saml/acs/enterprise',
        form,
        headers: {
          HttpHeaders.contentTypeHeader: ['application/x-www-form-urlencoded'],
          HttpHeaders.cookieHeader: [
            '${sessionCookie.name}=${sessionCookie.value}',
          ],
        },
      );
      completed.assertStatus(HttpStatus.found);
      expect(completed.headers['location'], ['/dashboard']);
      expect(completed.cookie('saml_route_session'), isNotNull);
    },
  );
}

String _response(String requestId) {
  // The fixture must retain its exact XML bytes, including the missing lead.
  // ignore: leading_newlines_in_multiline_strings
  return '''<?xml version="1.0"?>
<samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="_response" Version="2.0" IssueInstant="2030-01-01T12:00:00Z" Destination="https://sp.example.test/auth/sso/saml/acs/enterprise" InResponseTo="$requestId">
<saml:Issuer>https://idp.example.test/entity</saml:Issuer>
<samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>
<saml:Assertion ID="_assertion" Version="2.0" IssueInstant="2030-01-01T12:00:00Z">
<saml:Issuer>https://idp.example.test/entity</saml:Issuer>
<saml:Subject><saml:NameID Format="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent">stable-subject</saml:NameID><saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer"><saml:SubjectConfirmationData Recipient="https://sp.example.test/auth/sso/saml/acs/enterprise" InResponseTo="$requestId" NotOnOrAfter="2030-01-01T12:05:00Z"/></saml:SubjectConfirmation></saml:Subject>
<saml:Conditions NotBefore="2030-01-01T11:59:30Z" NotOnOrAfter="2030-01-01T12:05:00Z"><saml:AudienceRestriction><saml:Audience>https://sp.example.test/entity</saml:Audience></saml:AudienceRestriction></saml:Conditions>
</saml:Assertion></samlp:Response>''';
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
  );
  @override
  AuthSamlConnection? findByProviderId(String providerId) =>
      providerId == 'enterprise' ? connection : null;
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

final class _Resolver implements AuthSamlIdentityResolver<EngineContext> {
  const _Resolver(this.user);
  final AuthUser user;
  @override
  AuthUser resolveOrProvision(AuthSamlIdentityInput<EngineContext> input) {
    expect(input.identity.nameId, 'stable-subject');
    return user;
  }
}
