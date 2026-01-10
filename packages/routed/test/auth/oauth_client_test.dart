import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routed/src/auth/providers/github.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  test('OAuth2Client parses form-encoded token responses', () async {
    final client = MockClient((request) async {
      expect(request.url.path, equals('/token'));
      return http.Response(
        'access_token=abc&token_type=bearer&expires_in=3600',
        200,
        headers: {
          HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
        },
      );
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      clientId: 'id',
      clientSecret: 'secret',
      httpClient: client,
    );

    final token = await oauth.exchangeAuthorizationCode(
      code: 'code',
      redirectUri: Uri.parse('https://app/callback'),
    );

    expect(token.accessToken, equals('abc'));
  });

  test('OAuth2Client includes credentials when basic auth disabled', () async {
    final client = MockClient((request) async {
      final body = request.body;
      final parsed = Uri.splitQueryString(body);
      expect(parsed['client_id'], equals('id'));
      expect(parsed['client_secret'], equals('secret'));
      return http.Response(jsonEncode({'access_token': 'abc'}), 200);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      clientId: 'id',
      clientSecret: 'secret',
      useBasicAuth: false,
      httpClient: client,
    );

    final token = await oauth.exchangeAuthorizationCode(
      code: 'code',
      redirectUri: Uri.parse('https://app/callback'),
    );

    expect(token.accessToken, equals('abc'));
  });

  test('OAuth2Client fetchUserInfo returns JSON payload', () async {
    final client = MockClient((request) async {
      expect(
        request.headers[HttpHeaders.authorizationHeader],
        equals('Bearer token'),
      );
      return http.Response(jsonEncode({'id': 'user'}), 200);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      httpClient: client,
    );

    final profile = await oauth.fetchUserInfo(
      Uri.parse('https://auth.test/user'),
      'token',
    );
    expect(profile['id'], equals('user'));
  });

  test('OAuth2Client throws on non-success token response', () async {
    final client = MockClient((request) async {
      return http.Response('error', 401);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      httpClient: client,
    );

    expect(
      oauth.clientCredentials(),
      throwsA(
        isA<OAuth2Exception>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('OAuth2Client throws on empty token response', () async {
    final client = MockClient((request) async {
      return http.Response('  ', 200);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      httpClient: client,
    );

    expect(oauth.clientCredentials(), throwsA(isA<OAuth2Exception>()));
  });

  test('OAuth2Client parses JSON response without content-type', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'access_token': 'json-token'}), 200);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      httpClient: client,
    );

    final token = await oauth.clientCredentials();
    expect(token.accessToken, equals('json-token'));
  });

  test('OAuth2Client fetchUserInfo throws on error', () async {
    final client = MockClient((request) async {
      return http.Response('nope', 500);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      httpClient: client,
    );

    expect(
      oauth.fetchUserInfo(Uri.parse('https://auth.test/user'), 'token'),
      throwsA(isA<OAuth2Exception>()),
    );
  });

  test('OAuth2Client refreshes tokens with additional parameters', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'access_token': 'refreshed'}), 200);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      clientId: 'client-id',
      clientSecret: 'client-secret',
      httpClient: client,
    );

    final token = await oauth.refreshToken(
      refreshToken: 'refresh-token',
      scope: 'read',
      additionalParameters: const {'prompt': 'consent'},
    );

    expect(token.accessToken, equals('refreshed'));
    expect(captured.bodyFields['grant_type'], equals('refresh_token'));
    expect(captured.bodyFields['refresh_token'], equals('refresh-token'));
    expect(captured.bodyFields['scope'], equals('read'));
    expect(captured.bodyFields['prompt'], equals('consent'));
  });

  test('OAuth2Client includes default headers and code verifier', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'access_token': 'abc'}), 200);
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      clientId: 'client-id',
      clientSecret: 'client-secret',
      defaultHeaders: const {'X-Test': '1'},
      httpClient: client,
    );

    await oauth.exchangeAuthorizationCode(
      code: 'code',
      redirectUri: Uri.parse('https://app.test/callback'),
      codeVerifier: 'verifier',
      scope: 'read',
      additionalParameters: const {'prompt': 'login'},
    );

    expect(captured.headers['X-Test'], equals('1'));
    expect(captured.bodyFields['code_verifier'], equals('verifier'));
    expect(captured.bodyFields['scope'], equals('read'));
    expect(captured.bodyFields['prompt'], equals('login'));
  });

  test('OAuth2Client parses JSON response with content-type', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'access_token': 'typed'}),
        200,
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    });

    final oauth = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      httpClient: client,
    );

    final token = await oauth.clientCredentials();
    expect(token.accessToken, equals('typed'));
  });

  test('OAuthTokenResponse provides defaults for missing fields', () {
    final token = OAuthTokenResponse.fromJson({});
    expect(token.accessToken, equals(''));
    expect(token.tokenType, equals('Bearer'));
    expect(token.expiresIn, isNull);
  });

  test('OAuthIntrospectionResult exposes claims', () {
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final result = OAuthIntrospectionResult(
      active: true,
      raw: {
        'sub': 'user-1',
        'scope': 'read',
        'exp': nowSeconds,
        'nbf': nowSeconds,
      },
    );

    expect(result.subject, equals('user-1'));
    expect(result.scope, equals('read'));
    expect(result.expiresAt, isNotNull);
    expect(result.notBefore, isNotNull);
  });

  test('OAuthIntrospectionResult ignores invalid timestamps', () {
    final result = OAuthIntrospectionResult(
      active: true,
      raw: {'exp': 'invalid', 'nbf': 'invalid'},
    );

    expect(result.expiresAt, isNull);
    expect(result.notBefore, isNull);
  });

  group('GitHub provider', () {
    test('GitHubEmail parses defaults', () {
      final email = GitHubEmail.fromJson({
        'email': 'user@example.com',
        'primary': true,
        'verified': false,
      });

      expect(email.email, equals('user@example.com'));
      expect(email.primary, isTrue);
      expect(email.verified, isFalse);
      expect(email.visibility, equals('private'));
    });

    test('GitHubPlan roundtrip', () {
      final plan = GitHubPlan.fromJson({
        'collaborators': 2,
        'name': 'pro',
        'space': 100,
        'private_repos': 10,
      });

      expect(plan.collaborators, equals(2));
      expect(plan.toJson()['private_repos'], equals(10));
    });

    test('GitHubProfile parses and serializes', () {
      final profile = GitHubProfile.fromJson({
        'login': 'octocat',
        'id': 1,
        'node_id': 'node',
        'avatar_url': 'avatar',
        'url': 'api',
        'html_url': 'html',
        'followers_url': 'followers',
        'following_url': 'following',
        'gists_url': 'gists',
        'starred_url': 'starred',
        'subscriptions_url': 'subs',
        'organizations_url': 'orgs',
        'repos_url': 'repos',
        'events_url': 'events',
        'received_events_url': 'received',
        'type': 'User',
        'site_admin': false,
        'public_repos': 1,
        'public_gists': 2,
        'followers': 3,
        'following': 4,
        'created_at': '2024-01-01',
        'updated_at': '2024-01-02',
        'two_factor_authentication': true,
        'plan': {
          'collaborators': 1,
          'name': 'pro',
          'space': 100,
          'private_repos': 2,
        },
      });

      final serialized = profile.toJson();
      expect(serialized['login'], equals('octocat'));
      expect(serialized['plan']['name'], equals('pro'));
    });

    test('githubProvider builds enterprise endpoints', () {
      final provider = githubProvider(
        const GitHubProviderOptions(
          clientId: 'client',
          clientSecret: 'secret',
          redirectUri: 'https://app.test/auth/callback/github',
          enterpriseBaseUrl: 'https://github.enterprise',
        ),
      );

      expect(
        provider.authorizationEndpoint.toString(),
        equals('https://github.enterprise/login/oauth/authorize'),
      );
      expect(
        provider.tokenEndpoint.toString(),
        equals('https://github.enterprise/login/oauth/access_token'),
      );
      expect(
        provider.userInfoEndpoint.toString(),
        equals('https://github.enterprise/api/v3/user'),
      );
    });

    test('githubProvider maps profiles into users', () {
      final provider = githubProvider(
        const GitHubProviderOptions(
          clientId: 'client',
          clientSecret: 'secret',
          redirectUri: 'https://app.test/auth/callback/github',
        ),
      );
      final profile = GitHubProfile.fromJson({
        'login': 'octocat',
        'id': 99,
        'node_id': 'node',
        'avatar_url': 'avatar',
        'url': 'api',
        'html_url': 'html',
        'followers_url': 'followers',
        'following_url': 'following',
        'gists_url': 'gists',
        'starred_url': 'starred',
        'subscriptions_url': 'subs',
        'organizations_url': 'orgs',
        'repos_url': 'repos',
        'events_url': 'events',
        'received_events_url': 'received',
        'type': 'User',
        'site_admin': false,
        'public_repos': 1,
        'public_gists': 2,
        'followers': 3,
        'following': 4,
        'created_at': '2024-01-01',
        'updated_at': '2024-01-02',
        'two_factor_authentication': true,
        'email': 'octo@example.com',
      });

      final user = provider.mapProfile(profile);
      expect(user.id, equals('99'));
      expect(user.email, equals('octo@example.com'));
      expect(user.attributes['login'], equals('octocat'));
    });

    test('githubProvider fetches primary email when missing', () async {
      final provider = githubProvider(
        const GitHubProviderOptions(
          clientId: 'client',
          clientSecret: 'secret',
          redirectUri: 'https://app.test/auth/callback/github',
        ),
      );
      final profile = GitHubProfile.fromJson({
        'login': 'octocat',
        'id': 99,
        'node_id': 'node',
        'avatar_url': 'avatar',
        'url': 'api',
        'html_url': 'html',
        'followers_url': 'followers',
        'following_url': 'following',
        'gists_url': 'gists',
        'starred_url': 'starred',
        'subscriptions_url': 'subs',
        'organizations_url': 'orgs',
        'repos_url': 'repos',
        'events_url': 'events',
        'received_events_url': 'received',
        'type': 'User',
        'site_admin': false,
        'public_repos': 1,
        'public_gists': 2,
        'followers': 3,
        'following': 4,
        'created_at': '2024-01-01',
        'updated_at': '2024-01-02',
        'two_factor_authentication': true,
      });

      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/user/emails'));
        return http.Response(
          jsonEncode([
            {
              'email': 'primary@example.com',
              'primary': true,
              'verified': true,
              'visibility': 'public',
            },
          ]),
          200,
        );
      });

      final engine = testEngine();
      engine.get('/profile', (ctx) async {
        final updated = await provider.enrichProfile(
          ctx,
          OAuthTokenResponse(
            accessToken: 'token',
            tokenType: 'Bearer',
            expiresIn: 3600,
            raw: const <String, dynamic>{},
          ),
          client,
          profile,
        );
        return ctx.json(updated.toJson());
      });

      await engine.initialize();
      final testClient = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async {
        await testClient.close();
        await engine.close();
      });

      final response = await testClient.get('/profile');
      final updated = GitHubProfile.fromJson(
        response.json() as Map<String, dynamic>,
      );

      expect(updated.email, equals('primary@example.com'));
    });

    test('githubProvider skips email fetch when present', () async {
      final provider = githubProvider(
        const GitHubProviderOptions(
          clientId: 'client',
          clientSecret: 'secret',
          redirectUri: 'https://app.test/auth/callback/github',
        ),
      );
      final profile = GitHubProfile.fromJson({
        'login': 'octocat',
        'id': 99,
        'node_id': 'node',
        'avatar_url': 'avatar',
        'url': 'api',
        'html_url': 'html',
        'followers_url': 'followers',
        'following_url': 'following',
        'gists_url': 'gists',
        'starred_url': 'starred',
        'subscriptions_url': 'subs',
        'organizations_url': 'orgs',
        'repos_url': 'repos',
        'events_url': 'events',
        'received_events_url': 'received',
        'type': 'User',
        'site_admin': false,
        'public_repos': 1,
        'public_gists': 2,
        'followers': 3,
        'following': 4,
        'created_at': '2024-01-01',
        'updated_at': '2024-01-02',
        'two_factor_authentication': true,
        'email': 'octo@example.com',
      });

      final client = MockClient((request) async {
        return http.Response('nope', 500);
      });

      final engine = testEngine();
      engine.get('/profile', (ctx) async {
        final updated = await provider.enrichProfile(
          ctx,
          OAuthTokenResponse(
            accessToken: 'token',
            tokenType: 'Bearer',
            expiresIn: 3600,
            raw: const <String, dynamic>{},
          ),
          client,
          profile,
        );
        return ctx.json(updated.toJson());
      });

      await engine.initialize();
      final testClient = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async {
        await testClient.close();
        await engine.close();
      });

      final response = await testClient.get('/profile');
      final updated = GitHubProfile.fromJson(
        response.json() as Map<String, dynamic>,
      );

      expect(updated.email, equals('octo@example.com'));
    });
  });
}
