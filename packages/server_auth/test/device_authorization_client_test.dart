import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'device client uses unconstrained endpoints and parses RFC 8628 data',
    () async {
      final requests = <http.BaseRequest>[];
      final plugin = const AuthDeviceAuthorizationClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: [plugin],
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
      final client = auth.plugins.use(plugin);

      final authorization = await client.authorize(
        clientId: 'cli-1',
        scopes: const ['openid', 'profile'],
      );
      final token = await client.poll(
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

  test('device approval and denial use the CSRF mutation contract', () async {
    final plugin = const AuthDeviceAuthorizationClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
        }
        expect(request.headers['x-csrf-token'], 'csrf-1');
        expect(jsonDecode(request.body), {
          'user_code': 'ABCD-2345',
          '_csrf': 'csrf-1',
        });
        expect(
          request.url.path,
          anyOf('/auth/oauth/device/approve', '/auth/oauth/device/deny'),
        );
        return http.Response('{}', 200);
      }),
    );
    final client = auth.plugins.use(plugin);

    await client.approve(userCode: 'ABCD-2345');
    await client.deny(userCode: 'ABCD-2345');
  });

  test('device client preserves RFC error codes', () async {
    final plugin = const AuthDeviceAuthorizationClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'authorization_pending'}), 400),
      ),
    );
    final client = auth.plugins.use(plugin);

    await expectLater(
      client.poll(clientId: 'cli-1', deviceCode: 'device-raw'),
      throwsA(
        isA<AuthClientException>().having(
          (error) => error.code,
          'code',
          'authorization_pending',
        ),
      ),
    );
  });

  test(
    'automatic polling honors interval, pending, slow_down, and Retry-After',
    () async {
      final time = _FakePollingTime(DateTime.utc(2026, 1, 1));
      var polls = 0;
      final plugin = const AuthDeviceAuthorizationClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: [plugin],
        httpClient: MockClient((_) async {
          polls += 1;
          if (polls == 1) {
            return http.Response(
              jsonEncode({'error': 'authorization_pending'}),
              400,
              headers: {'retry-after': '7'},
            );
          }
          if (polls == 2) {
            return http.Response(
              jsonEncode({'error': 'slow_down'}),
              400,
              headers: {'retry-after': '8'},
            );
          }
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'token_type': 'Bearer',
              'expires_in': 300,
              'scope': 'openid',
            }),
            200,
          );
        }),
      );
      final client = auth.plugins.use(plugin);

      final token = await client.pollUntilComplete(
        clientId: 'cli-1',
        authorization: _authorization(receivedAt: time.now()),
        options: AuthDeviceAuthorizationPollingOptions(
          clock: time.now,
          delay: time.delay,
        ),
      );

      expect(token.accessToken, 'access-1');
      expect(polls, 3);
      expect(time.delays, const [
        Duration(seconds: 5),
        Duration(seconds: 7),
        Duration(seconds: 12),
      ]);
    },
  );

  test('automatic polling stops at authorization expiry', () async {
    final time = _FakePollingTime(DateTime.utc(2026, 1, 1));
    var polls = 0;
    final plugin = const AuthDeviceAuthorizationClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((_) async {
        polls += 1;
        return http.Response(
          jsonEncode({'error': 'authorization_pending'}),
          400,
        );
      }),
    );
    final client = auth.plugins.use(plugin);

    await expectLater(
      client.pollUntilComplete(
        clientId: 'cli-1',
        authorization: _authorization(
          receivedAt: time.now(),
          expiresIn: const Duration(seconds: 11),
        ),
        options: AuthDeviceAuthorizationPollingOptions(
          clock: time.now,
          delay: time.delay,
        ),
      ),
      throwsA(
        isA<AuthDeviceAuthorizationPollingStoppedException>()
            .having(
              (error) => error.reason,
              'reason',
              AuthDeviceAuthorizationPollingStopReason.authorizationExpired,
            )
            .having((error) => error.attempts, 'attempts', 2),
      ),
    );

    expect(polls, 2);
    expect(time.delays, const [
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 1),
    ]);
  });

  test('automatic polling honors a caller deadline before expiry', () async {
    final time = _FakePollingTime(DateTime.utc(2026, 1, 1));
    var polls = 0;
    final plugin = const AuthDeviceAuthorizationClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((_) async {
        polls += 1;
        return http.Response('{}', 500);
      }),
    );
    final client = auth.plugins.use(plugin);

    await expectLater(
      client.pollUntilComplete(
        clientId: 'cli-1',
        authorization: _authorization(receivedAt: time.now()),
        options: AuthDeviceAuthorizationPollingOptions(
          deadline: time.now().add(const Duration(seconds: 3)),
          clock: time.now,
          delay: time.delay,
        ),
      ),
      throwsA(
        isA<AuthDeviceAuthorizationPollingStoppedException>().having(
          (error) => error.reason,
          'reason',
          AuthDeviceAuthorizationPollingStopReason.deadlineReached,
        ),
      ),
    );

    expect(polls, 0);
    expect(time.delays, const [Duration(seconds: 3)]);
  });

  test('automatic polling can be cancelled during a wait', () async {
    final time = _FakePollingTime(DateTime.utc(2026, 1, 1));
    final controller = AuthDeviceAuthorizationPollingController();
    var polls = 0;
    final plugin = const AuthDeviceAuthorizationClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((_) async {
        polls += 1;
        return http.Response('{}', 500);
      }),
    );
    final client = auth.plugins.use(plugin);

    await expectLater(
      client.pollUntilComplete(
        clientId: 'cli-1',
        authorization: _authorization(receivedAt: time.now()),
        options: AuthDeviceAuthorizationPollingOptions(
          controller: controller,
          clock: time.now,
          delay: (duration) async {
            await time.delay(duration);
            controller.cancel();
          },
        ),
      ),
      throwsA(
        isA<AuthDeviceAuthorizationPollingStoppedException>().having(
          (error) => error.reason,
          'reason',
          AuthDeviceAuthorizationPollingStopReason.cancelled,
        ),
      ),
    );

    expect(polls, 0);
    expect(time.delays, const [Duration(seconds: 5)]);
  });

  test('automatic polling supports caller-controlled stopping', () async {
    final time = _FakePollingTime(DateTime.utc(2026, 1, 1));
    final contexts = <AuthDeviceAuthorizationPollingContext>[];
    var polls = 0;
    final plugin = const AuthDeviceAuthorizationClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient((_) async {
        polls += 1;
        return http.Response(
          jsonEncode({'error': 'authorization_pending'}),
          400,
        );
      }),
    );
    final client = auth.plugins.use(plugin);

    await expectLater(
      client.pollUntilComplete(
        clientId: 'cli-1',
        authorization: _authorization(receivedAt: time.now()),
        options: AuthDeviceAuthorizationPollingOptions(
          clock: time.now,
          delay: time.delay,
          shouldContinue: (context) {
            contexts.add(context);
            return context.attempts == 0;
          },
        ),
      ),
      throwsA(
        isA<AuthDeviceAuthorizationPollingStoppedException>().having(
          (error) => error.reason,
          'reason',
          AuthDeviceAuthorizationPollingStopReason.stoppedByCaller,
        ),
      ),
    );

    expect(polls, 1);
    expect(time.delays, const [Duration(seconds: 5)]);
    expect(contexts, hasLength(2));
    expect(contexts.last.lastError?.code, 'authorization_pending');
  });
}

AuthClientDeviceAuthorization _authorization({
  required DateTime receivedAt,
  Duration expiresIn = const Duration(minutes: 10),
  Duration interval = const Duration(seconds: 5),
}) {
  return AuthClientDeviceAuthorization(
    deviceCode: 'device-raw',
    userCode: 'ABCD-2345',
    verificationUri: 'https://example.test/device',
    expiresIn: expiresIn,
    interval: interval,
    receivedAt: receivedAt,
  );
}

final class _FakePollingTime {
  _FakePollingTime(this._now);

  DateTime _now;
  final List<Duration> delays = <Duration>[];

  DateTime now() => _now;

  Future<void> delay(Duration duration) async {
    delays.add(duration);
    _now = _now.add(duration);
  }
}
