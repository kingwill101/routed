import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('phone client is opt-in and parses typed responses', () async {
    const plugin = AuthPhoneNumberClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: const <AuthClientPlugin<Object>>[plugin],
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/phone-number/send-code') {
          expect(jsonDecode(request.body), <String, dynamic>{
            'phoneNumber': '+18765551234',
          });
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'verification_sent',
              'expiresAt': '2030-01-01T00:05:00Z',
            }),
            200,
          );
        }
        expect(request.url.path, '/auth/phone-number/verify-code');
        expect(jsonDecode(request.body), <String, dynamic>{
          'phoneNumber': '+18765551234',
          'code': '123456',
          'name': 'Ada',
        });
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'authenticated',
            'phoneNumber': '+18765551234',
            'user': <String, dynamic>{
              'id': 'user-1',
              'roles': <String>[],
              'attributes': <String, dynamic>{'phoneNumberVerified': true},
            },
            'expires': '2030-01-01T01:00:00Z',
            'strategy': 'jwt',
            'token': 'jwt-token',
          }),
          200,
        );
      }),
    );

    expect(auth.plugins.ids, <String>['phone_number']);
    final phone = auth.plugins.use(plugin);
    final issued = await phone.sendCode(phoneNumber: '+18765551234');
    final signedIn = await phone.verifyCode(
      phoneNumber: '+18765551234',
      code: '123456',
      name: 'Ada',
    );

    expect(issued.expiresAt, DateTime.utc(2030, 1, 1, 0, 5));
    expect(signedIn.phoneNumber, '+18765551234');
    expect(signedIn.session.user.id, 'user-1');
    expect(signedIn.session.token, 'jwt-token');
  });
}
