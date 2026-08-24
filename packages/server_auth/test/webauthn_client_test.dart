import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('WebAuthn plugin exposes typed ceremony helpers', () async {
    final requests = <http.BaseRequest>[];
    const plugin = AuthWebAuthnClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/csrf') {
          return http.Response(
            jsonEncode(<String, dynamic>{'csrfToken': 'csrf-1'}),
            200,
            headers: <String, String>{
              'content-type': 'application/json',
              'set-cookie': 'session=session-1; Path=/',
            },
          );
        }
        if (request.url.path == '/auth/webauthn/register/options') {
          expect(jsonDecode(request.body), {'_csrf': 'csrf-1'});
          return http.Response(
            jsonEncode(<String, dynamic>{
              'challenge': 'registration-challenge',
              'rp': <String, dynamic>{'id': 'example.test', 'name': 'Example'},
              'user': <String, dynamic>{
                'id': 'dXNlci0x',
                'name': 'ada@example.test',
                'displayName': 'Ada',
              },
              'pubKeyCredParams': const <Object?>[
                <String, dynamic>{'type': 'public-key', 'alg': -7},
              ],
              'timeout': 300000,
              'attestation': 'none',
              'excludeCredentials': const <Object?>[],
              'authenticatorSelection': <String, dynamic>{
                'userVerification': 'preferred',
              },
            }),
            200,
          );
        }
        if (request.url.path == '/auth/webauthn/register/verify') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['_csrf'], 'csrf-1');
          expect(body['credential']['name'], 'Laptop');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'credential': <String, dynamic>{
                'credential_id': 'credential-1',
                'public_key': 'cose-key',
                'counter': 0,
                'user_id': 'user-1',
                'transports': ['internal'],
                'created_at': '2030-01-01T00:00:00Z',
                'last_used_at': null,
                'name': 'Laptop',
              },
            }),
            200,
          );
        }
        if (request.url.path == '/auth/webauthn/authenticate/options') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {'userId': 'user-1', '_csrf': 'csrf-1'});
          return http.Response(
            jsonEncode(<String, dynamic>{
              'challenge': 'authentication-challenge',
              'rpId': 'example.test',
              'timeout': 300000,
              'userVerification': 'preferred',
              'allowCredentials': [
                <String, dynamic>{'type': 'public-key', 'id': 'credential-1'},
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/auth/webauthn/authenticate/verify') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['_csrf'], 'csrf-1');
          expect(body['userId'], 'user-1');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'authenticated',
              'expires': '2030-01-01T01:00:00Z',
              'strategy': 'jwt',
              'token': 'webauthn-jwt',
              'user': <String, dynamic>{
                'id': 'user-1',
                'email': 'ada@example.test',
                'roles': const <String>[],
                'attributes': const <String, dynamic>{},
              },
              'credential': <String, dynamic>{
                'credential_id': 'credential-1',
                'public_key': 'cose-key',
                'counter': 1,
                'user_id': 'user-1',
                'transports': ['internal'],
                'created_at': '2030-01-01T00:00:00Z',
                'last_used_at': '2030-01-01T00:01:00Z',
                'name': 'Laptop',
              },
            }),
            200,
          );
        }
        if (request.url.path == '/auth/webauthn/credentials' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'credentials': [
                <String, dynamic>{
                  'credential_id': 'credential-1',
                  'public_key': 'cose-key',
                  'counter': 1,
                  'user_id': 'user-1',
                  'transports': ['internal'],
                  'created_at': '2030-01-01T00:00:00Z',
                  'last_used_at': '2030-01-01T00:01:00Z',
                  'name': 'Laptop',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/auth/webauthn/credentials/rename') {
          expect(jsonDecode(request.body), {
            'credentialId': 'credential-1',
            'name': 'Desktop',
            '_csrf': 'csrf-1',
          });
          return http.Response(
            jsonEncode(<String, dynamic>{
              'credential': <String, dynamic>{
                'credential_id': 'credential-1',
                'public_key': 'cose-key',
                'counter': 1,
                'user_id': 'user-1',
                'transports': ['internal'],
                'created_at': '2030-01-01T00:00:00Z',
                'last_used_at': '2030-01-01T00:01:00Z',
                'name': 'Desktop',
              },
            }),
            200,
          );
        }
        expect(request.url.path, '/auth/webauthn/credentials/delete');
        expect(jsonDecode(request.body), {
          'credentialId': 'credential-1',
          '_csrf': 'csrf-1',
        });
        return http.Response('{}', 200);
      }),
    );
    final client = auth.plugins.use(plugin);

    final registration = await client.beginRegistration();
    expect(registration.challenge, 'registration-challenge');
    expect(registration.relyingPartyId, 'example.test');
    expect(registration.publicKey['pubKeyCredParams'], isNotEmpty);

    final saved = await client.completeRegistration(
      credential: <String, dynamic>{'id': 'credential-1'},
      name: 'Laptop',
    );
    expect(saved.credentialId, 'credential-1');
    expect(saved.transports, ['internal']);

    final authentication = await client.beginAuthentication(userId: 'user-1');
    expect(authentication.allowCredentials, ['credential-1']);
    final result = await client.completeAuthentication(
      credential: <String, dynamic>{'id': 'credential-1'},
      userId: 'user-1',
    );
    expect(result.user.id, 'user-1');
    expect(result.credential.counter, 1);
    expect(result.session.user.id, 'user-1');
    expect(result.session.token, 'webauthn-jwt');

    final credentials = await client.list();
    expect(credentials.single.name, 'Laptop');
    final renamed = await client.rename(
      credentialId: 'credential-1',
      name: 'Desktop',
    );
    expect(renamed.name, 'Desktop');
    await client.delete(credentialId: 'credential-1');
    expect(
      requests.map((request) => request.url.path),
      contains('/auth/webauthn/authenticate/verify'),
    );
  });
}
