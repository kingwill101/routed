import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('two-factor plugin exposes its complete typed client API', () async {
    final seen = <String>[];
    const plugin = AuthTwoFactorClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((request) async {
        seen.add(request.url.path);
        if (request.url.path == '/auth/csrf') {
          return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
        }
        if (request.method == 'POST') {
          expect(request.headers['x-csrf-token'], 'csrf-1');
          expect(jsonDecode(request.body)['_csrf'], 'csrf-1');
        }
        switch (request.url.path) {
          case '/auth/2fa/status':
            return http.Response(
              jsonEncode({'enabled': true, 'recoveryCodesRemaining': 4}),
              200,
            );
          case '/auth/2fa/enroll':
            expect(jsonDecode(request.body)['accountLabel'], 'ada@example.com');
            return http.Response(
              jsonEncode({
                'secret': 'JBSWY3DPEHPK3PXP',
                'otpauthUri':
                    'otpauth://totp/server_auth:ada@example.com?secret=JBSWY3DPEHPK3PXP',
                'expiresAt': '2030-01-01T00:10:00Z',
              }),
              200,
            );
          case '/auth/2fa/enroll/verify':
            expect(jsonDecode(request.body)['code'], '123456');
            return http.Response(
              jsonEncode({
                'recoveryCodes': ['ENROLL-CODE'],
              }),
              200,
            );
          case '/auth/2fa/verify':
            expect(jsonDecode(request.body)['code'], '123456');
            return http.Response('{}', 200);
          case '/auth/2fa/challenge/verify':
            expect(jsonDecode(request.body), {
              'challengeToken': 'challenge-1',
              'code': '123456',
              'trustDevice': true,
              '_csrf': 'csrf-1',
            });
            return http.Response(jsonEncode(_sessionJson), 200);
          case '/auth/2fa/challenge/recovery-code':
            expect(jsonDecode(request.body), {
              'challengeToken': 'challenge-2',
              'recoveryCode': 'RECOVERY-CODE',
              '_csrf': 'csrf-1',
            });
            return http.Response(jsonEncode(_sessionJson), 200);
          case '/auth/2fa/trusted-devices/revoke':
          case '/auth/2fa/step-up/revoke':
            return http.Response('{}', 200);
          case '/auth/2fa/step-up':
            expect(jsonDecode(request.body)['code'], '123456');
            return http.Response(
              jsonEncode({
                'verified': true,
                'expiresAt': '2030-01-01T00:05:00Z',
              }),
              200,
            );
          case '/auth/2fa/recovery-code':
            expect(jsonDecode(request.body)['recoveryCode'], 'RECOVERY-CODE');
            return http.Response('{}', 200);
          case '/auth/2fa/recovery-codes/regenerate':
            expect(jsonDecode(request.body)['code'], '123456');
            return http.Response(
              jsonEncode({
                'recoveryCodes': ['REGENERATED-CODE'],
              }),
              200,
            );
          case '/auth/2fa/disable':
            expect(jsonDecode(request.body)['code'], '123456');
            return http.Response('{}', 200);
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      }),
    );
    final client = auth.plugins.use(plugin);

    final status = await client.status();
    final enrollment = await client.beginEnrollment(
      accountLabel: 'ada@example.com',
    );
    final enrollmentCodes = await client.verifyEnrollment(code: '123456');
    await client.verify(code: '123456');
    final totpSession = await client.verifyChallenge(
      challengeToken: 'challenge-1',
      code: '123456',
      trustDevice: true,
    );
    final recoverySession = await client.verifyRecoveryChallenge(
      challengeToken: 'challenge-2',
      recoveryCode: 'RECOVERY-CODE',
    );
    await client.revokeTrustedDevices();
    final stepUp = await client.verifyStepUp(code: '123456');
    await client.revokeStepUp();
    await client.useRecoveryCode(code: 'RECOVERY-CODE');
    final regenerated = await client.regenerateRecoveryCodes(code: '123456');
    await client.disable(code: '123456');

    expect(status.enabled, isTrue);
    expect(status.recoveryCodesRemaining, 4);
    expect(enrollment.otpauthUri.scheme, 'otpauth');
    expect(enrollmentCodes.codes, ['ENROLL-CODE']);
    expect(totpSession.user.id, 'user-1');
    expect(recoverySession.user.id, 'user-1');
    expect(stepUp.expiresAt, DateTime.utc(2030, 1, 1, 0, 5));
    expect(regenerated.codes, ['REGENERATED-CODE']);
    expect(
      seen,
      containsAll(<String>[
        '/auth/2fa/trusted-devices/revoke',
        '/auth/2fa/recovery-codes/regenerate',
        '/auth/2fa/disable',
      ]),
    );
  });
}

final Map<String, dynamic> _sessionJson = {
  'user': {
    'id': 'user-1',
    'email': 'ada@example.com',
    'roles': <String>[],
    'attributes': <String, dynamic>{},
  },
  'expires': '2030-01-01T01:00:00Z',
  'strategy': 'session',
};
