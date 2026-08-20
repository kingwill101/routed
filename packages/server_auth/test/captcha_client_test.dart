import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'captcha client sends its token without adding it to attributes',
    () async {
      final plugin = const AuthCaptchaClientPlugin();
      final client = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: const [AuthCaptchaClientPlugin()],
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/csrf') {
            return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
          }
          expect(request.url.path, '/auth/signin/credentials');
          expect(jsonDecode(request.body), {
            'email': 'ada@example.com',
            'password': 'correct horse battery staple',
            'captchaToken': 'captcha-secret',
            '_csrf': 'csrf-1',
          });
          return http.Response(
            jsonEncode({
              'user': {'id': 'user-1', 'roles': <String>[], 'attributes': {}},
              'expires': '2030-01-01T00:00:00.000Z',
              'strategy': 'session',
            }),
            200,
          );
        }),
      );

      final session = await client.plugins
          .use(plugin)
          .signIn(
            email: 'ada@example.com',
            password: 'correct horse battery staple',
            captchaToken: 'captcha-secret',
          );

      expect(session.user.id, 'user-1');
    },
  );

  test(
    'captcha client explicit fields override untrusted attributes',
    () async {
      final plugin = const AuthCaptchaClientPlugin();
      final client = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: const [AuthCaptchaClientPlugin()],
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/csrf') {
            return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
          }
          final body = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          expect(body['email'], 'real@example.com');
          expect(body['password'], 'real-password');
          expect(body['captchaToken'], 'real-captcha');
          return http.Response(
            jsonEncode({
              'user': {'id': 'user-1', 'roles': <String>[], 'attributes': {}},
              'expires': '2030-01-01T00:00:00.000Z',
              'strategy': 'session',
            }),
            200,
          );
        }),
      );

      await client.plugins
          .use(plugin)
          .register(
            email: 'real@example.com',
            password: 'real-password',
            captchaToken: 'real-captcha',
            attributes: {
              'email': 'attacker@example.com',
              'password': 'attacker-password',
              'captchaToken': 'attacker-captcha',
            },
          );
    },
  );
}
