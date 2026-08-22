import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

OAuthTokenResponse _token() {
  return OAuthTokenResponse(
    accessToken: 'access-token',
    tokenType: 'Bearer',
    expiresIn: 300,
    raw: const <String, dynamic>{},
  );
}

void main() {
  test('custom user-info callbacks use the provider timeout', () async {
    final provider = OAuthProvider<Map<String, dynamic>>(
      id: 'custom',
      name: 'Custom',
      clientId: 'client-id',
      clientSecret: 'client-secret',
      authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      userInfoEndpoint: Uri.parse('https://auth.test/userinfo'),
      requestTimeout: const Duration(milliseconds: 1),
      userInfoRequest: (_, _, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return <String, dynamic>{'sub': 'user-1'};
      },
      redirectUri: 'https://app.test/callback/custom',
      profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
    );

    await expectLater(
      loadOAuthProfile(
        provider,
        token: _token(),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'userinfo_failed',
        ),
      ),
    );
  });

  test('GitHub email enrichment rejects oversized responses', () async {
    final provider = githubProvider(
      const GitHubProviderOptions(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'https://app.test/callback/github',
      ),
    );
    final profile = GitHubProfile.fromJson(const <String, dynamic>{
      'login': 'octocat',
      'id': 1,
    });
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'emails': 'x' * maxOAuthResponseCharacters,
        }),
        200,
      );
    });

    final enriched = await provider.enrichProfile(
      null,
      _token(),
      client,
      profile,
    );

    expect(requests, equals(1));
    expect(enriched.email, isNull);
  });

  test('GitHub user-info requests include GitHub API headers', () async {
    final provider = githubProvider(
      const GitHubProviderOptions(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'https://app.test/callback/github',
      ),
    );
    late http.BaseRequest request;
    final client = MockClient((received) async {
      request = received;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 1,
          'login': 'octocat',
          'name': 'The Octocat',
          'email': 'octo@example.com',
        }),
        200,
      );
    });

    final profile = await loadOAuthProfile(
      provider,
      token: _token(),
      httpClient: client,
    );

    expect(profile['id'], equals(1));
    expect(request.url, equals(Uri.parse('https://api.github.com/user')));
    expect(request.headers['Authorization'], equals('Bearer access-token'));
    expect(request.headers['Accept'], equals('application/vnd.github+json'));
    expect(request.headers['User-Agent'], equals('server_auth'));
    expect(request.headers['X-GitHub-Api-Version'], equals('2022-11-28'));
  });

  test(
    'Dropbox user-info rejects oversized responses before decoding',
    () async {
      final provider = dropboxProvider(
        const DropboxProviderOptions(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          redirectUri: 'https://app.test/callback/dropbox',
        ),
      );
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{
            'name': 'x' * maxOAuthResponseCharacters,
          }),
          200,
        ),
      );

      await expectLater(
        provider.userInfoRequest!(_token(), client, provider.userInfoEndpoint!),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'dropbox_userinfo_failed',
          ),
        ),
      );
    },
  );

  test(
    'Dropbox profile preserves current-account data and identity mapping',
    () {
      final provider = dropboxProvider(
        const DropboxProviderOptions(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          redirectUri: 'https://app.test/callback/dropbox',
        ),
      );
      final profile = DropboxProfile.fromJson(<String, dynamic>{
        'account_id': 'dbid:AA123',
        'email': 'dropbox@example.com',
        'email_verified': true,
        'name': <String, dynamic>{
          'display_name': 'Dropbox User',
          'given_name': 'Dropbox',
          'surname': 'User',
        },
        'profile_photo_url': 'https://cdn.example.test/avatar.png',
        'disabled': false,
        'country': 'JM',
        'locale': 'en',
        'is_paired': true,
        'account_type': <String, dynamic>{'.tag': 'pro'},
      });

      final user = provider.mapProfile(profile);
      expect(user.id, equals('dbid:AA123'));
      expect(user.email, equals('dropbox@example.com'));
      expect(user.name, equals('Dropbox User'));
      expect(user.image, equals('https://cdn.example.test/avatar.png'));
      expect(user.attributes['account_id'], equals('dbid:AA123'));
      expect(user.attributes['email_verified'], isTrue);
      expect(user.attributes['account_type'], <String, dynamic>{'.tag': 'pro'});
    },
  );

  test('Dropbox user-info uses the current-account POST contract', () async {
    final provider = dropboxProvider(
      const DropboxProviderOptions(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'https://app.test/callback/dropbox',
      ),
    );
    late http.Request request;
    final client = MockClient((received) async {
      request = received;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'account_id': 'dbid:AA123',
          'email': 'dropbox@example.com',
          'name': <String, dynamic>{'display_name': 'Dropbox User'},
          'account_type': <String, dynamic>{'.tag': 'basic'},
        }),
        200,
      );
    });

    final profile = await loadOAuthProfile(
      provider,
      token: _token(),
      httpClient: client,
    );

    expect(request.method, equals('POST'));
    expect(
      request.url,
      equals(
        Uri.parse('https://api.dropboxapi.com/2/users/get_current_account'),
      ),
    );
    expect(request.headers['Authorization'], equals('Bearer access-token'));
    expect(request.headers['Content-Type'], equals('application/json'));
    expect(request.body, equals('null'));
    expect(profile['account_id'], equals('dbid:AA123'));
  });
}
