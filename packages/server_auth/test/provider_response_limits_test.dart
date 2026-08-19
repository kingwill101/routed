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
}
