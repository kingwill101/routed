import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'AuthClient exposes email OTP flows with typed response parsing',
    () async {
      final client = AuthClientCore(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/email-otp/send-verification-otp') {
            expect(jsonDecode(request.body), {
              'email': 'ada@example.com',
              'type': 'sign-in',
            });
            return http.Response(
              jsonEncode({'status': 'verification_sent'}),
              200,
            );
          }
          if (request.url.path == '/auth/sign-in/email-otp') {
            expect(jsonDecode(request.body), {
              'email': 'ada@example.com',
              'otp': '123456',
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
          }
          if (request.url.path == '/auth/csrf') {
            return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
          }
          expect(request.url.path, '/auth/email-otp/verify-email');
          expect(request.headers['x-csrf-token'], 'csrf-1');
          expect(jsonDecode(request.body), {
            'otp': '123456',
            '_csrf': 'csrf-1',
          });
          return http.Response(
            jsonEncode({
              'status': 'email_verified',
              'user': {
                'id': 'user-1',
                'email': 'ada@example.com',
                'roles': [],
                'attributes': {'emailVerified': true},
              },
            }),
            200,
          );
        }),
      );

      await client.sendEmailOtp(
        email: 'ada@example.com',
        type: AuthEmailOtpType.signIn,
      );
      final session = await client.signInWithEmailOtp(
        email: 'ada@example.com',
        otp: '123456',
      );
      final user = await client.verifyEmailWithOtp(otp: '123456');

      expect(session.user.id, 'user-1');
      expect(user.attributes['emailVerified'], isTrue);
    },
  );
}
