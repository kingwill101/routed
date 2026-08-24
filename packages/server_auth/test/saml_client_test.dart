import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('SAML client API is independently selected and typed', () async {
    final requests = <http.Request>[];
    const clientPlugin = AuthSamlClientPlugin();
    final client = AuthClient(
      baseUrl: Uri.parse('https://app.example.test'),
      plugins: [clientPlugin],
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/csrf') {
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-1'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/auth/sso/saml/sign-in') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['providerId'], 'enterprise');
          expect(body['_csrf'], 'csrf-1');
          return http.Response(
            jsonEncode({
              'providerId': 'enterprise',
              'binding': 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
              'destination': 'https://idp.example.test/sso',
              'fields': {'SAMLRequest': 'request', 'RelayState': 'relay'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/auth/sso/saml/metadata/enterprise') {
          return http.Response(
            '<md:EntityDescriptor/>',
            200,
            headers: {'content-type': 'application/samlmetadata+xml'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    final saml = client.plugins.use(clientPlugin);
    final form = await saml.signIn(
      AuthSamlSignInRequest(
        providerId: 'enterprise',
        callbackUrl: Uri(path: '/dashboard'),
      ),
    );
    expect(form.providerId, 'enterprise');
    expect(form.destination, Uri.parse('https://idp.example.test/sso'));
    expect(form.fields['RelayState'], 'relay');
    expect(
      await saml.serviceProviderMetadata('enterprise'),
      '<md:EntityDescriptor/>',
    );
    expect(requests, hasLength(3));
  });

  test('SAML API is absent when its client plugin is not installed', () {
    final client = AuthClient(baseUrl: Uri.parse('https://app.example.test'));
    expect(
      () => client.plugins.use(const AuthSamlClientPlugin()),
      throwsA(isA<StateError>()),
    );
  });
}
