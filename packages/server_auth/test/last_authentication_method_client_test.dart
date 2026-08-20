import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'independent client plugin exposes only the typed read projection',
    () async {
      final httpClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/auth/last-authentication-method');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'method': 'oauth:google',
            'expiresAt': '2026-08-20T12:05:00.000Z',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      addTearDown(httpClient.close);

      const plugin = AuthLastAuthenticationMethodClientPlugin();
      final client = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: httpClient,
        plugins: const <AuthClientPlugin<dynamic>>[plugin],
      );
      final api = client.plugins.use(plugin);
      final result = await api.read();

      expect(
        result?.method,
        AuthLastAuthenticationMethodId.oauthProvider('google'),
      );
      expect(result?.expiresAt, DateTime.utc(2026, 8, 20, 12, 5));
      expect(
        client.plugins.ids,
        contains(authLastAuthenticationMethodPluginId),
      );
      expect(
        () => client.plugins.use(
          const AuthLastAuthenticationMethodClientPlugin(),
        ),
        returnsNormally,
      );
    },
  );

  test('optional client APIs remain absent unless explicitly installed', () {
    final client = AuthClient(baseUrl: Uri.parse('https://example.test'));
    expect(
      () =>
          client.plugins.use(const AuthLastAuthenticationMethodClientPlugin()),
      throwsStateError,
    );
  });

  test(
    'client rejects a response that attempts to serialize extra or secret fields',
    () async {
      final httpClient = MockClient((_) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'method': 'credentials',
            'expiresAt': '2026-08-20T12:05:00.000Z',
            'token': 'secret-token',
          }),
          200,
        );
      });
      addTearDown(httpClient.close);
      final client = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: httpClient,
        plugins: const <AuthClientPlugin<dynamic>>[
          AuthLastAuthenticationMethodClientPlugin(),
        ],
      );

      expect(
        () => client.plugins
            .use(const AuthLastAuthenticationMethodClientPlugin())
            .read(),
        throwsFormatException,
      );
    },
  );

  test('client rejects loosely coerced method and expiry values', () async {
    final httpClient = MockClient((_) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'method': <String>['credentials'],
          'expiresAt': 20260820,
        }),
        200,
      );
    });
    addTearDown(httpClient.close);
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: httpClient,
      plugins: const <AuthClientPlugin<dynamic>>[
        AuthLastAuthenticationMethodClientPlugin(),
      ],
    );

    await expectLater(
      client.plugins
          .use(const AuthLastAuthenticationMethodClientPlugin())
          .read(),
      throwsFormatException,
    );
  });
}
