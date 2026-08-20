import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'username client is opt-in and uses only its typed operations',
    () async {
      const plugin = AuthUsernameClientPlugin();
      final requests = <http.Request>[];
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: const <AuthClientPlugin<Object>>[plugin],
        httpClient: MockClient((request) async {
          requests.add(request);
          final input = jsonDecode(request.body) as Map<String, dynamic>;
          final registering = request.url.path.endsWith('/username/register');
          expect(input['password'], 'safe-password-123');
          expect(input['captchaToken'], 'opaque-captcha');
          if (registering) {
            expect(input['username'], 'Ada');
            expect(input['email'], 'ada@example.com');
          } else {
            expect(input['identifier'], 'Ada');
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'authenticated',
              'username': 'ada',
              'user': <String, dynamic>{
                'id': 'user-1',
                'email': 'ada@example.com',
                'roles': <String>[],
                'attributes': <String, dynamic>{'username': 'ada'},
              },
              'expires': '2030-01-01T00:00:00Z',
              'strategy': 'jwt',
              'token': 'jwt-token',
            }),
            200,
          );
        }),
      );

      expect(auth.plugins.ids, ['username']);
      final username = auth.plugins.use(plugin);
      final registered = await username.register(
        username: 'Ada',
        email: 'ada@example.com',
        password: 'safe-password-123',
        captchaToken: 'opaque-captcha',
      );
      final signedIn = await username.signIn(
        identifier: 'Ada',
        password: 'safe-password-123',
        captchaToken: 'opaque-captcha',
      );

      expect(requests.map((request) => request.url.path), [
        '/auth/username/register',
        '/auth/username/sign-in',
      ]);
      expect(registered.username, 'ada');
      expect(signedIn.session.user.attributes['username'], 'ada');
      expect(signedIn.session.token, 'jwt-token');
    },
  );

  test('username client exposes a typed two-factor challenge', () async {
    const plugin = AuthUsernameClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: const <AuthClientPlugin<Object>>[plugin],
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'two_factor_required',
            'challengeToken': 'challenge-secret',
            'expiresAt': '2030-01-01T00:05:00Z',
          }),
          202,
        ),
      ),
    );

    await expectLater(
      auth.plugins
          .use(plugin)
          .signIn(identifier: 'ada', password: 'safe-password-123'),
      throwsA(
        isA<AuthClientTwoFactorRequiredException>()
            .having(
              (error) => error.challengeToken,
              'challengeToken',
              'challenge-secret',
            )
            .having(
              (error) => error.expiresAt,
              'expiresAt',
              DateTime.utc(2030, 1, 1, 0, 5),
            ),
      ),
    );
  });
}
