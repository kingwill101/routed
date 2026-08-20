import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('client installs only the selected typed plugins', () {
    final organization = AuthOrganizationClientPlugin();
    final admin = AuthAdminClientPlugin();
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [organization],
    );

    final api = client.plugins.use(organization);

    expect(api, isA<AuthOrganizationClient>());
    expect(client.plugins.ids, ['organization']);
    expect(client.plugins.contains('admin'), isFalse);
    expect(client.plugins.use(organization), same(api));
    expect(
      () => client.plugins.use(admin),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('is not installed'),
        ),
      ),
    );
  });

  test('client rejects duplicate plugin IDs', () {
    expect(
      () => AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: const [AuthEmailOtpClientPlugin(), AuthEmailOtpClientPlugin()],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('already installed'),
        ),
      ),
    );
  });

  test('built-in optional APIs have distinct installable plugin IDs', () {
    final plugins = <AuthClientPlugin<dynamic>>[
      const AuthProviderClientPlugin(),
      const AuthCredentialsClientPlugin(),
      const AuthOAuthClientPlugin(),
      const AuthSessionClientPlugin(),
      const AuthAnonymousClientPlugin(),
      const AuthDeviceAuthorizationClientPlugin(),
      const AuthEmailOtpClientPlugin(),
      const AuthPhoneNumberClientPlugin(),
      const AuthCaptchaClientPlugin(),
      const AuthMagicLinkClientPlugin(),
      const AuthApiKeyClientPlugin(),
      const AuthWebAuthnClientPlugin(),
      const AuthTwoFactorClientPlugin(),
      const AuthAccountClientPlugin(),
      const AuthPasswordClientPlugin(),
      const AuthOrganizationClientPlugin(),
      const AuthAdminClientPlugin(),
    ];
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: plugins,
    );

    expect(client.plugins.ids, hasLength(plugins.length));
    expect(
      client.plugins.use(const AuthProviderClientPlugin()),
      isA<AuthProviderClient>(),
    );
    expect(
      client.plugins.use(const AuthCredentialsClientPlugin()),
      isA<AuthCredentialsClient>(),
    );
    expect(
      client.plugins.use(const AuthSessionClientPlugin()),
      isA<AuthSessionClient>(),
    );
    expect(
      client.plugins.use(const AuthWebAuthnClientPlugin()),
      isA<AuthWebAuthnClient>(),
    );
    expect(
      client.plugins.use(const AuthTwoFactorClientPlugin()),
      isA<AuthTwoFactorClient>(),
    );
  });

  test('magic-link plugin owns the email provider client contract', () async {
    final plugin = AuthMagicLinkClientPlugin();
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
        }
        if (request.url.path == '/auth/signin/email') {
          expect(request.headers['x-csrf-token'], 'csrf-1');
          expect(jsonDecode(request.body), {
            'email': 'ada@example.com',
            'callbackUrl': 'https://example.test/welcome',
            '_csrf': 'csrf-1',
          });
          return http.Response(
            jsonEncode({'email': 'ada@example.com', 'status': 'sent'}),
            200,
          );
        }
        expect(request.url.path, '/auth/callback/email');
        expect(request.url.queryParameters, {
          'email': 'ada@example.com',
          'token': 'token-1',
        });
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user-1',
              'email': 'ada@example.com',
              'roles': [],
              'attributes': {'emailVerified': true},
            },
            'expires': '2030-01-01T00:00:00Z',
            'strategy': 'session',
          }),
          200,
        );
      }),
    );

    final magicLink = client.plugins.use(plugin);
    final sent = await magicLink.send(
      email: 'ada@example.com',
      callbackUrl: 'https://example.test/welcome',
    );
    final result = await magicLink.verify(email: sent.email, token: 'token-1');

    expect(sent.email, 'ada@example.com');
    expect(result.session?.user.id, 'user-1');
    expect(result.session?.user.attributes['emailVerified'], isTrue);
  });
}
