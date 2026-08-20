import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('account and password plugins expose the complete lifecycle', () async {
    var csrfCalls = 0;
    final accountPlugin = const AuthAccountClientPlugin();
    final passwordPlugin = const AuthPasswordClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [accountPlugin, passwordPlugin],
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          csrfCalls += 1;
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-$csrfCalls'}),
            200,
          );
        }
        if (request.url.path == '/auth/accounts' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'accounts': [
                {
                  'provider_id': 'github',
                  'provider_account_id': 'github-1',
                  'user_id': 'user-1',
                  'metadata': {'login': 'ada'},
                },
              ],
            }),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['x-csrf-token'], body['_csrf']);
        switch (request.url.path) {
          case '/auth/accounts/unlink':
            expect(body, {
              'providerId': 'github',
              'providerAccountId': 'github-1',
              'currentPassword': 'current-password',
              '_csrf': 'csrf-1',
            });
            return http.Response('{}', 200);
          case '/auth/email/change/request':
            expect(body, {
              'newEmail': 'new@example.com',
              'currentPassword': 'current-password',
              'identifier': 'ada@example.com',
              '_csrf': 'csrf-1',
            });
            return http.Response('{}', 200);
          case '/auth/email/change/confirm':
            expect(body, {'token': 'email-change-token', '_csrf': 'csrf-1'});
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'user-1',
                  'email': 'new@example.com',
                  'roles': <String>[],
                  'attributes': {'emailVerified': true},
                },
              }),
              200,
            );
          case '/auth/password/change':
            expect(body, {
              'identifier': 'new@example.com',
              'currentPassword': 'current-password',
              'newPassword': 'new-password',
              '_csrf': 'csrf-2',
            });
            return http.Response('{}', 200);
          case '/auth/account/delete':
            expect(body, {
              'currentPassword': 'new-password',
              '_csrf': 'csrf-3',
            });
            return http.Response('{}', 200);
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      }),
    );
    final accounts = auth.plugins.use(accountPlugin);
    final passwords = auth.plugins.use(passwordPlugin);

    final linked = await accounts.linked();
    await accounts.unlink(
      providerId: 'github',
      providerAccountId: 'github-1',
      currentPassword: 'current-password',
    );
    await passwords.requestEmailChange(
      newEmail: 'new@example.com',
      currentPassword: 'current-password',
      identifier: 'ada@example.com',
    );
    final updated = await passwords.confirmEmailChange(
      token: 'email-change-token',
    );
    await passwords.change(
      identifier: 'new@example.com',
      currentPassword: 'current-password',
      newPassword: 'new-password',
    );
    await accounts.delete(currentPassword: 'new-password');

    expect(linked.single.providerId, 'github');
    expect(linked.single.providerAccountId, 'github-1');
    expect(linked.single.metadata['login'], 'ada');
    expect(updated.email, 'new@example.com');
    expect(updated.attributes['emailVerified'], isTrue);
    expect(csrfCalls, 3);
  });
}
