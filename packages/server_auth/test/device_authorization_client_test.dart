import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:server_auth/src/core/client.dart' show AuthClientCore;
import 'package:test/test.dart';

void main() {
  test(
    'device client uses unconstrained endpoints and parses RFC 8628 data',
    () async {
      final requests = <http.BaseRequest>[];
      final client = AuthClientCore(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/auth/oauth/device/authorize') {
            expect(jsonDecode(request.body), {
              'client_id': 'cli-1',
              'scope': 'openid profile',
            });
            expect(request.headers.containsKey('x-csrf-token'), isFalse);
            return http.Response(
              jsonEncode({
                'device_code': 'device-raw',
                'user_code': 'ABCD-2345',
                'verification_uri': 'https://example.test/device',
                'verification_uri_complete':
                    'https://example.test/device?user_code=ABCD-2345',
                'expires_in': 600,
                'interval': 5,
              }),
              200,
            );
          }
          expect(request.url.path, '/auth/oauth/token');
          expect(jsonDecode(request.body), {
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'client_id': 'cli-1',
            'device_code': 'device-raw',
          });
          expect(request.headers.containsKey('x-csrf-token'), isFalse);
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'token_type': 'Bearer',
              'expires_in': 300,
              'scope': 'openid profile',
              'refresh_token': 'refresh-1',
            }),
            200,
          );
        }),
      );

      final authorization = await client.requestDeviceAuthorization(
        clientId: 'cli-1',
        scopes: const ['openid', 'profile'],
      );
      final token = await client.pollDeviceToken(
        clientId: 'cli-1',
        deviceCode: authorization.deviceCode,
      );

      expect(authorization.userCode, 'ABCD-2345');
      expect(authorization.expiresIn, const Duration(minutes: 10));
      expect(authorization.verificationUriComplete, contains('user_code'));
      expect(token.accessToken, 'access-1');
      expect(token.refreshToken, 'refresh-1');
      expect(token.scopes, ['openid', 'profile']);
      expect(requests.map((request) => request.url.path), [
        '/auth/oauth/device/authorize',
        '/auth/oauth/token',
      ]);
    },
  );

  test('device approval uses the normal CSRF mutation contract', () async {
    final client = AuthClientCore(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
        }
        expect(request.url.path, '/auth/oauth/device/approve');
        expect(request.headers['x-csrf-token'], 'csrf-1');
        expect(jsonDecode(request.body), {
          'user_code': 'ABCD-2345',
          '_csrf': 'csrf-1',
        });
        return http.Response('{}', 200);
      }),
    );

    await client.approveDeviceAuthorization(userCode: 'ABCD-2345');
  });

  test('device client preserves RFC error codes', () async {
    final client = AuthClientCore(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'authorization_pending'}), 400),
      ),
    );

    await expectLater(
      client.pollDeviceToken(clientId: 'cli-1', deviceCode: 'device-raw'),
      throwsA(
        isA<AuthClientException>().having(
          (error) => error.code,
          'code',
          'authorization_pending',
        ),
      ),
    );
  });
}
