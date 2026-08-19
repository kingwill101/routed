import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthClient exposes anonymous sign-in and deletion', () async {
    final client = AuthClientCore(
      baseUrl: Uri.parse('https://example.test'),
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
              'strategy': 'session',
            }),
            200,
          );
        }
        if (request.url.path == '/auth/csrf') {
          return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
        }
        expect(request.url.path, '/auth/delete-anonymous-user');
        expect(jsonDecode(request.body), {'_csrf': 'csrf-1'});
        return http.Response(jsonEncode({'status': 'anonymous_deleted'}), 200);
      }),
    );

    final session = await client.signInAnonymously();
    await client.deleteAnonymousUser();

    expect(session.user.isAnonymous, isTrue);
  });
}
