import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('anonymous client plugin exposes sign-in and deletion', () async {
    final plugin = const AuthAnonymousClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/sign-in/anonymous') {
          expect(jsonDecode(request.body), isEmpty);
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'anon-1',
                'email': null,
                'roles': [],
                'isAnonymous': true,
                'attributes': {},
              },
              'expires': '2030-01-01T00:00:00Z',
              'strategy': 'jwt',
              'token': 'anonymous-jwt',
            }),
            200,
          );
        }
        if (request.url.path == '/auth/csrf') {
          return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
        }
        expect(request.url.path, '/auth/delete-anonymous-user');
        expect(request.headers['x-csrf-token'], 'csrf-1');
        expect(jsonDecode(request.body), {'_csrf': 'csrf-1'});
        return http.Response(jsonEncode({'status': 'anonymous_deleted'}), 200);
      }),
    );
    final client = auth.plugins.use(plugin);

    final session = await client.signIn();
    await client.deleteUser();

    expect(session.user.isAnonymous, isTrue);
    expect(session.token, 'anonymous-jwt');
  });
}
