import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'credentials and session APIs compose through the public host',
    () async {
      final credentialsPlugin = const AuthCredentialsClientPlugin();
      final sessionPlugin = const AuthSessionClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: [credentialsPlugin, sessionPlugin],
        httpClient: MockClient((request) async {
          switch (request.url.path) {
            case '/auth/csrf':
              return http.Response(
                jsonEncode({'csrfToken': 'csrf-1'}),
                200,
                headers: {'set-cookie': 'session=s1; Path=/; HttpOnly'},
              );
            case '/auth/signin/credentials':
              expect(request.headers['x-csrf-token'], 'csrf-1');
              expect(request.headers['cookie'], 'session=s1');
              expect(jsonDecode(request.body), {
                'email': 'ada@example.com',
                'password': 'correct horse battery staple',
                '_csrf': 'csrf-1',
              });
              return http.Response(jsonEncode(_sessionJson), 200);
            case '/auth/session':
              return http.Response(jsonEncode(_sessionJson), 200);
            case '/auth/sessions':
              return http.Response(
                jsonEncode({
                  'sessions': [
                    {
                      'id': 'session-1',
                      'userId': 'user-1',
                      'createdAt': '2030-01-01T00:00:00Z',
                      'expiresAt': '2030-01-02T00:00:00Z',
                      'lastUsedAt': '2030-01-01T01:00:00Z',
                      'authenticationMethod': 'credentials',
                      'isCurrent': true,
                      'active': true,
                    },
                  ],
                }),
                200,
              );
            case '/auth/sessions/revoke':
              expect(jsonDecode(request.body), {
                'sessionId': 'session-1',
                '_csrf': 'csrf-1',
              });
              return http.Response('{}', 200);
            case '/auth/sessions/revoke-others':
              expect(jsonDecode(request.body), {'_csrf': 'csrf-1'});
              return http.Response(jsonEncode({'revoked': 2}), 200);
            case '/auth/signout':
              expect(jsonDecode(request.body), {'_csrf': 'csrf-1'});
              return http.Response('{}', 200);
            default:
              fail('Unexpected request: ${request.method} ${request.url}');
          }
        }),
      );

      final credentials = auth.plugins.use(credentialsPlugin);
      final sessions = auth.plugins.use(sessionPlugin);

      final signedIn = await credentials.signIn(
        email: 'ada@example.com',
        password: 'correct horse battery staple',
      );
      final current = await sessions.current();
      final listed = await sessions.list();
      await sessions.revoke('session-1');
      final revoked = await sessions.revokeOthers();
      await sessions.signOut();

      expect(signedIn.user.id, 'user-1');
      expect(current?.user.id, 'user-1');
      expect(listed.single.id, 'session-1');
      expect(revoked, 2);
    },
  );
}

final Map<String, dynamic> _sessionJson = {
  'user': {
    'id': 'user-1',
    'email': 'ada@example.com',
    'roles': ['user'],
    'attributes': {'emailVerified': true},
  },
  'expires': '2030-01-02T00:00:00Z',
  'strategy': 'session',
};
