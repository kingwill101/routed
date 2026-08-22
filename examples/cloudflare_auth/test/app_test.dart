import 'dart:convert';

import 'package:routed_auth_sqlite/routed_auth_sqlite.dart';
import 'package:routed_cloudflare_auth_example/app.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

const _origin = 'https://example.test';
const _sessionKey =
    'base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==';

final _csrfInput = RegExp(r'name="_csrf" value="([^"]+)"');

String _csrfFromHtml(String html) {
  final match = _csrfInput.firstMatch(html);
  expect(match, isNotNull);
  return match!.group(1)!;
}

String _rawApiKeyFromHtml(String html) {
  final match = RegExp(
    r'rka\.[A-Za-z0-9_-]+\.[A-Za-z0-9_=-]+',
  ).firstMatch(html);
  expect(match, isNotNull);
  return match!.group(0)!;
}

String _apiKeyId(String rawKey) => rawKey.split('.')[1];

Future<TestResponse> _postForm(
  TestClient client,
  String path,
  Map<String, String> values,
) {
  return client.post(
    path,
    Uri(queryParameters: values).query,
    headers: <String, List<String>>{
      'content-type': ['application/x-www-form-urlencoded'],
      'origin': [_origin],
    },
  );
}

void main() {
  late SqliteAuthStore store;
  late Engine engine;
  late TestClient client;

  setUp(() async {
    store = await SqliteAuthStore.openInMemory();
    engine = await createEngine(
      store: store,
      origin: Uri.parse(_origin),
      sessionKey: _sessionKey,
    );
    client = TestClient.inMemory(RoutedRequestHandler(engine));
  });

  tearDown(() async {
    await client.close();
    await engine.close();
    store.close();
  });

  test('boots the documented health and provider routes', () async {
    final home = await client.get('/');
    home.assertStatus(HttpStatus.ok);
    expect(home.headerValue('content-type'), contains('text/html'));
    expect(home.body, contains('<title>Routed Cloudflare Auth</title>'));
    expect(home.body, contains('D1 for auth storage'));
    expect(home.body, contains('href="/auth/providers"'));

    final health = await client.getJson('/health');
    health.assertStatus(HttpStatus.ok).assertJson((json) {
      json.where('ok', true).where('store', 'cloudflare_d1');
    });

    final providers = await client.getJson('/auth/providers');
    providers.assertStatus(HttpStatus.ok).assertJson((json) {
      json.has('providers');
    });
  });

  test(
    'registers and authenticates a user through the session cookie',
    () async {
      final unauthenticated = await client.get('/account');
      unauthenticated.assertStatus(HttpStatus.unauthorized);

      final csrf = await client.get('/auth/csrf');
      csrf.assertStatus(HttpStatus.ok);
      final csrfToken = (csrf.json() as Map<String, dynamic>)['csrfToken'];
      expect(csrfToken, isA<String>());

      final registered = await client.postJson(
        '/auth/register/credentials',
        <String, Object?>{
          'email': 'worker@example.test',
          'password': 'a deliberately long password',
          '_csrf': csrfToken,
        },
        headers: <String, List<String>>{
          'origin': [_origin],
        },
      );
      registered.assertStatus(HttpStatus.ok);
      expect(registered.json()['user']['email'], 'worker@example.test');

      final account = await client.getJson('/account');
      account.assertStatus(HttpStatus.ok).assertJson((json) {
        json.where('authenticated', true).where('email', 'worker@example.test');
      });

      final session = await client.get('/auth/session');
      session.assertStatus(HttpStatus.ok);
      expect(jsonDecode(session.body)['user']['email'], 'worker@example.test');
    },
  );

  test('serves signup, login, dashboard, and logout browser flows', () async {
    final signupPage = await client.get('/signup');
    signupPage.assertStatus(HttpStatus.ok);
    expect(signupPage.body, contains('<form action="/signup"'));
    expect(signupPage.body, contains('name="_csrf"'));
    expect(signupPage.body, isNot(contains('class="alert"')));
    expect(signupPage.body, isNot(contains('<div class="social-divider">')));

    final signup = await _postForm(client, '/signup', <String, String>{
      '_csrf': _csrfFromHtml(signupPage.body),
      'email': 'browser@example.test',
      'password': 'a deliberately long password',
    });
    signup.assertStatus(HttpStatus.found);
    expect(signup.headerValue('location'), '/dashboard');

    final dashboard = await client.get('/dashboard');
    dashboard.assertStatus(HttpStatus.ok);
    expect(dashboard.body, contains('Good to see you.'));
    expect(dashboard.body, contains('browser@example.test'));
    expect(dashboard.body, contains('Session strategy'));

    final profilePage = await client.get('/settings/profile');
    profilePage.assertStatus(HttpStatus.ok);
    expect(profilePage.body, contains('Account settings'));
    expect(profilePage.body, contains('browser@example.test'));
    expect(profilePage.body, contains('No external accounts are linked yet.'));

    final profileUpdate =
        await _postForm(client, '/settings/profile', <String, String>{
          '_csrf': _csrfFromHtml(profilePage.body),
          'name': 'Browser User',
          'image': 'https://example.test/avatars/browser.png',
        });
    profileUpdate.assertStatus(HttpStatus.found);
    expect(
      profileUpdate.headerValue('location'),
      '/settings/profile?updated=1',
    );

    final updatedProfile = await client.get(
      profileUpdate.headerValue('location'),
    );
    updatedProfile.assertStatus(HttpStatus.ok);
    expect(updatedProfile.body, contains('Profile saved.'));
    expect(updatedProfile.body, contains('value="Browser User"'));
    expect(
      updatedProfile.body,
      contains('https://example.test/avatars/browser.png'),
    );

    final updatedSession = await client.get('/auth/session');
    updatedSession.assertStatus(HttpStatus.ok);
    expect(updatedSession.body, contains('Browser User'));

    final sessionsPage = await client.get('/settings/sessions');
    sessionsPage.assertStatus(HttpStatus.ok);
    expect(sessionsPage.body, contains('This browser'));
    expect(sessionsPage.body, contains('Revoke other sessions'));

    final revokeOthers = await _postForm(
      client,
      '/settings/sessions/revoke-others',
      <String, String>{'_csrf': _csrfFromHtml(sessionsPage.body)},
    );
    revokeOthers.assertStatus(HttpStatus.found);
    expect(
      revokeOthers.headerValue('location'),
      '/settings/sessions?revoked=0',
    );

    final invalidProfilePage = await client.get('/settings/profile');
    final invalidProfile =
        await _postForm(client, '/settings/profile', <String, String>{
          '_csrf': _csrfFromHtml(invalidProfilePage.body),
          'name': 'Browser User',
          'image': 'javascript:alert(1)',
        });
    invalidProfile.assertStatus(HttpStatus.badRequest);
    expect(
      invalidProfile.body,
      contains('Profile image must be an HTTP or HTTPS URL.'),
    );

    final apiKeysPage = await client.get('/settings/api-keys');
    apiKeysPage.assertStatus(HttpStatus.ok);
    expect(apiKeysPage.body, contains('Service keys.'));
    expect(apiKeysPage.body, contains('Issue service key'));

    final createdApiKey =
        await _postForm(client, '/settings/api-keys/create', <String, String>{
          '_csrf': _csrfFromHtml(apiKeysPage.body),
          'name': 'browser deploy bot',
          'scopes': 'profile:read, deploy:read',
        });
    createdApiKey.assertStatus(HttpStatus.ok);
    expect(createdApiKey.body, contains('Copy this key now.'));
    final rawApiKey = _rawApiKeyFromHtml(createdApiKey.body);
    expect(createdApiKey.body, contains('browser deploy bot'));

    final serviceAccount = await client.get(
      '/service/account',
      headers: <String, List<String>>{
        'x-api-key': [rawApiKey],
      },
    );
    serviceAccount.assertStatus(HttpStatus.ok).assertJson((json) {
      json
          .where('authenticated', true)
          .where('scopes', contains('profile:read'));
    });

    final listedApiKeys = await client.get('/settings/api-keys');
    listedApiKeys.assertStatus(HttpStatus.ok);
    expect(listedApiKeys.body, contains('browser deploy bot'));
    expect(listedApiKeys.body, isNot(contains(rawApiKey)));
    final apiKeyId = _apiKeyId(rawApiKey);

    final rotatedApiKey =
        await _postForm(client, '/settings/api-keys/rotate', <String, String>{
          '_csrf': _csrfFromHtml(listedApiKeys.body),
          'id': apiKeyId,
          'name': 'browser deploy bot rotated',
        });
    rotatedApiKey.assertStatus(HttpStatus.ok);
    final rotatedRawApiKey = _rawApiKeyFromHtml(rotatedApiKey.body);
    expect(rotatedRawApiKey, isNot(rawApiKey));
    (await client.get(
      '/service/account',
      headers: <String, List<String>>{
        'x-api-key': [rawApiKey],
      },
    )).assertStatus(HttpStatus.unauthorized);
    (await client.get(
      '/service/account',
      headers: <String, List<String>>{
        'x-api-key': [rotatedRawApiKey],
      },
    )).assertStatus(HttpStatus.ok);

    final revokedApiKey =
        await _postForm(client, '/settings/api-keys/revoke', <String, String>{
          '_csrf': _csrfFromHtml(rotatedApiKey.body),
          'id': _apiKeyId(rotatedRawApiKey),
        });
    revokedApiKey.assertStatus(HttpStatus.ok);
    (await client.get(
      '/service/account',
      headers: <String, List<String>>{
        'x-api-key': [rotatedRawApiKey],
      },
    )).assertStatus(HttpStatus.unauthorized);

    final passwordPage = await client.get('/settings/password');
    passwordPage.assertStatus(HttpStatus.ok);
    expect(passwordPage.body, contains('Change your password.'));
    expect(passwordPage.body, contains('Changing a password signs out'));

    final mismatchedPassword =
        await _postForm(client, '/settings/password', <String, String>{
          '_csrf': _csrfFromHtml(passwordPage.body),
          'current_password': 'a deliberately long password',
          'new_password': 'a new deliberately long password',
          'new_password_confirmation': 'a different deliberately long password',
        });
    mismatchedPassword.assertStatus(HttpStatus.badRequest);
    expect(mismatchedPassword.body, contains('new passwords do not match'));

    final wrongPasswordPage = await client.get('/settings/password');
    final wrongPassword =
        await _postForm(client, '/settings/password', <String, String>{
          '_csrf': _csrfFromHtml(wrongPasswordPage.body),
          'current_password': 'not the current password',
          'new_password': 'a new deliberately long password',
          'new_password_confirmation': 'a new deliberately long password',
        });
    wrongPassword.assertStatus(HttpStatus.badRequest);
    expect(wrongPassword.body, contains('current password is not correct'));
    (await client.get('/dashboard')).assertStatus(HttpStatus.ok);

    final changePasswordPage = await client.get('/settings/password');
    final changedPassword =
        await _postForm(client, '/settings/password', <String, String>{
          '_csrf': _csrfFromHtml(changePasswordPage.body),
          'current_password': 'a deliberately long password',
          'new_password': 'a new deliberately long password',
          'new_password_confirmation': 'a new deliberately long password',
        });
    changedPassword.assertStatus(HttpStatus.found);
    expect(
      changedPassword.headerValue('location'),
      '/login?password_changed=1',
    );
    expect(
      changedPassword.headers[HttpHeaders.setCookieHeader],
      anyElement(contains('Max-Age=0')),
    );

    final passwordChangedLogin = await client.get(
      changedPassword.headerValue('location'),
    );
    passwordChangedLogin.assertStatus(HttpStatus.ok);
    expect(
      passwordChangedLogin.body,
      contains('Password changed. Sign in again to continue.'),
    );
    final relogin = await _postForm(client, '/login', <String, String>{
      '_csrf': _csrfFromHtml(passwordChangedLogin.body),
      'email': 'browser@example.test',
      'password': 'a new deliberately long password',
    });
    relogin.assertStatus(HttpStatus.found);
    final reloginDashboard = await client.get('/dashboard');
    reloginDashboard.assertStatus(HttpStatus.ok);

    final logout = await _postForm(client, '/logout', <String, String>{
      '_csrf': _csrfFromHtml(reloginDashboard.body),
    });
    logout.assertStatus(HttpStatus.found);
    expect(logout.headerValue('location'), '/');
    expect(
      logout.headers[HttpHeaders.setCookieHeader],
      anyElement(contains('routed_session=')),
    );
    expect(
      logout.headers[HttpHeaders.setCookieHeader],
      anyElement(contains('Max-Age=0')),
    );

    final protectedAfterLogout = await client.get('/dashboard');
    protectedAfterLogout.assertStatus(HttpStatus.found);
    expect(protectedAfterLogout.headerValue('location'), '/login');

    final loginPage = await client.get('/login');
    loginPage.assertStatus(HttpStatus.ok);
    expect(loginPage.body, contains('<form action="/login"'));

    final login = await _postForm(client, '/login', <String, String>{
      '_csrf': _csrfFromHtml(loginPage.body),
      'email': 'browser@example.test',
      'password': 'a new deliberately long password',
    });
    login.assertStatus(HttpStatus.found);
    expect(login.headerValue('location'), '/dashboard');
    (await client.get('/dashboard')).assertStatus(HttpStatus.ok);

    final user = await store.users.findByEmail('browser@example.test');
    expect(user, isNotNull);
    final activeSessions = (await store.sessions.listForUser(
      user!.id,
    )).where((session) => session.isActive()).toList(growable: false);
    expect(activeSessions, hasLength(1));
    await store.sessions.revokeById(user.id, activeSessions.single.id);

    final staleDashboard = await client.get('/dashboard');
    staleDashboard.assertStatus(HttpStatus.found);
    expect(staleDashboard.headerValue('location'), '/login');
  });

  test('returns a safe message for invalid browser credentials', () async {
    final loginPage = await client.get('/login');
    final response = await _postForm(client, '/login', <String, String>{
      '_csrf': _csrfFromHtml(loginPage.body),
      'email': 'missing@example.test',
      'password': 'a deliberately long password',
    });

    response.assertStatus(HttpStatus.unauthorized);
    expect(response.body, contains('That email or password is not correct.'));
    expect(response.body, isNot(contains('AuthFlowException')));
  });

  test('builds social providers from host values with local callback URLs', () {
    final providers = socialProvidersFromValues(
      origin: Uri.parse('http://127.0.0.1:8081'),
      githubClientId: 'github-client-id',
      githubClientSecret: 'github-client-secret',
      dropboxClientId: 'dropbox-client-id',
      dropboxClientSecret: 'dropbox-client-secret',
      telegramBotToken: '123456:telegram-secret',
      telegramBotUsername: 'routed_demo_bot',
    );

    expect(providers.map((provider) => provider.id), <String>[
      'github',
      'dropbox',
      'telegram',
    ]);
    expect(
      (providers[1] as OAuthProvider).redirectUri,
      'http://127.0.0.1:8081/auth/callback/dropbox',
    );
  });

  test(
    'renders configured GitHub, Dropbox, and Telegram sign-in options',
    () async {
      final socialStore = await SqliteAuthStore.openInMemory();
      final socialEngine = await createEngine(
        store: socialStore,
        origin: Uri.parse(_origin),
        sessionKey: _sessionKey,
        socialProviders: <AuthProvider>[
          githubProvider(
            const GitHubProviderOptions(
              clientId: 'github-client-id',
              clientSecret: 'github-client-secret',
              redirectUri: 'https://example.test/auth/callback/github',
            ),
          ),
          dropboxProvider(
            const DropboxProviderOptions(
              clientId: 'dropbox-client-id',
              clientSecret: 'dropbox-client-secret',
              redirectUri: 'https://example.test/auth/callback/dropbox',
            ),
          ),
          telegramProvider(
            const TelegramProviderOptions(
              botToken: '123456:telegram-secret',
              botUsername: 'routed_demo_bot',
              redirectUri: 'https://example.test/auth/callback/telegram',
            ),
          ),
        ],
      );
      final socialClient = TestClient.inMemory(
        RoutedRequestHandler(socialEngine),
      );
      try {
        final loginPage = await socialClient.get('/login');
        loginPage.assertStatus(HttpStatus.ok);
        expect(loginPage.body, contains('Continue with GitHub'));
        expect(loginPage.body, contains('Continue with Dropbox'));
        expect(
          loginPage.body,
          contains('/auth/signin/dropbox?callbackUrl=%2Fdashboard'),
        );
        expect(loginPage.body, contains('telegram.org/js/telegram-widget.js'));
        expect(loginPage.body, contains('routed_demo_bot'));
        expect(loginPage.body, isNot(contains('class="alert"')));

        final dropboxSignIn = await socialClient.get(
          '/auth/signin/dropbox?callbackUrl=%2Fdashboard',
        );
        dropboxSignIn.assertStatus(HttpStatus.movedTemporarily);
        final authorization = Uri.parse(
          dropboxSignIn.headers[HttpHeaders.locationHeader]!.single,
        );
        expect(
          authorization.origin + authorization.path,
          'https://www.dropbox.com/oauth2/authorize',
        );
        expect(authorization.queryParameters['client_id'], 'dropbox-client-id');
        expect(
          authorization.queryParameters['redirect_uri'],
          'https://example.test/auth/callback/dropbox',
        );
        expect(authorization.queryParameters['scope'], 'account_info.read');
        expect(authorization.queryParameters['state'], isNotEmpty);
        expect(
          dropboxSignIn.headers[HttpHeaders.setCookieHeader],
          anyElement(contains('routed_session=')),
        );
      } finally {
        await socialClient.close();
        await socialEngine.close();
        socialStore.close();
      }
    },
  );
}
