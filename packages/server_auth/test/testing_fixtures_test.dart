import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('deterministic test primitives', () {
    test(
      'clock, sequence, delivery failure, and gate are controllable',
      () async {
        final clock = AuthTestClock(DateTime.utc(2030));
        expect(clock(), DateTime.utc(2030));
        expect(
          clock.advance(const Duration(minutes: 5)),
          DateTime.utc(2030, 1, 1, 0, 5),
        );

        final sequence = AuthTestSequence<String>(<String>['one', 'two']);
        expect(sequence.next(), 'one');
        expect(sequence.remaining, 1);

        final deliveries = AuthTestDeliveryLog<String>();
        final gate = AuthTestGate();
        deliveries.gateNext(gate);
        final pending = deliveries.capture('payload');
        await gate.entered;
        expect(deliveries.latest, 'payload');
        gate.release();
        await pending;

        deliveries.failNext(StateError('provider unavailable'));
        await expectLater(
          deliveries.capture('failed-payload'),
          throwsStateError,
        );
        expect(deliveries.values, <String>['payload', 'failed-payload']);
      },
    );
  });

  group('credentials fixture', () {
    test(
      'exercises provider callbacks and the real credentials client codec',
      () async {
        final fixture = AuthCredentialsProviderFixture();
        final accepted = await fixture.provider.authorize!(
          Object(),
          fixture.provider,
          fixture.credentials,
        );
        final rejected = await fixture.provider.authorize!(
          Object(),
          fixture.provider,
          AuthCredentials(email: fixture.email, password: 'wrong'),
        );

        expect(accepted?.id, fixture.user.id);
        expect(rejected, isNull);
        expect(fixture.authorizationAttempts, hasLength(2));
        expect(fixture.authorizationAttempts.first.password, isNull);

        final http = AuthTestHttpClient();
        http.enqueueJson(
          method: 'GET',
          path: '/auth/csrf',
          response: <String, dynamic>{'csrfToken': 'fixture-csrf'},
        );
        http.enqueueJson(
          method: 'POST',
          path: '/auth/signin/credentials',
          expectedRequest: <String, dynamic>{
            'email': fixture.email,
            'password': fixture.password,
            '_csrf': 'fixture-csrf',
          },
          response: _session(fixture.user),
        );
        const plugin = AuthCredentialsClientPlugin();
        final auth = _client(http, <AuthClientPlugin<Object>>[plugin]);

        final session = await auth.plugins
            .use(plugin)
            .signIn(email: fixture.email, password: fixture.password);
        expect(session.user.id, fixture.user.id);
        expect(http.pendingResponses, 0);
      },
    );
  });

  group('portable OTP endpoint fixtures', () {
    test(
      'email OTP runs client to real server codecs and rejects replay',
      () async {
        final clock = AuthTestClock(DateTime.utc(2030));
        final delivery = AuthEmailOtpFixture<Object>();
        final plugin = delivery.plugin();
        final store = InMemoryAuthStore();
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const <AuthProvider>[],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: <AuthServerPlugin<Object>>[plugin],
          ),
        );
        final sessions = AuthTestSessionControl(clock: clock.call);
        final endpoint = AuthPluginEndpointFixture<Object>(
          endpoints: plugin.endpoints,
          invocation: (_) => AuthOperationInvocation<Object>(
            context: Object(),
            user: null,
            sessionControl: sessions,
          ),
        );
        final http = AuthTestHttpClient(fallback: endpoint.respond);
        const clientPlugin = AuthEmailOtpClientPlugin();
        final auth = _client(http, <AuthClientPlugin<Object>>[clientPlugin]);
        final client = auth.plugins.use(clientPlugin);

        await client.sendVerificationOtp(
          email: 'Ada@Example.Test',
          type: AuthEmailOtpType.signIn,
        );
        final code = delivery.deliveries.latest.code;
        final session = await client.signIn(
          email: 'ada@example.test',
          otp: code,
        );

        expect(session.user.email, 'ada@example.test');
        expect(sessions.authenticationMethods, <String>['email_otp']);
        await expectLater(
          client.signIn(email: 'ada@example.test', otp: code),
          throwsA(
            isA<AuthClientException>().having(
              (error) => error.code,
              'code',
              'invalid_otp',
            ),
          ),
        );
      },
    );

    test(
      'phone OTP runs real codecs and one concurrent verification wins',
      () async {
        final clock = AuthTestClock(DateTime.utc(2030));
        final delivery = AuthPhoneOtpFixture<Object>(
          codes: const <String>['123456', '654321'],
        );
        final plugin = delivery.plugin();
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const <AuthProvider>[],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            plugins: <AuthServerPlugin<Object>>[plugin],
          ),
        );
        final sessions = AuthTestSessionControl(clock: clock.call);
        final endpoint = AuthPluginEndpointFixture<Object>(
          endpoints: plugin.endpoints,
          invocation: (_) => AuthOperationInvocation<Object>(
            context: Object(),
            user: null,
            sessionControl: sessions,
          ),
        );
        final http = AuthTestHttpClient(fallback: endpoint.respond);
        const clientPlugin = AuthPhoneNumberClientPlugin();
        final auth = _client(http, <AuthClientPlugin<Object>>[clientPlugin]);
        final client = auth.plugins.use(clientPlugin);

        await client.sendCode(phoneNumber: '+18765551234');
        final signedIn = await client.verifyCode(
          phoneNumber: '+18765551234',
          code: delivery.deliveries.latest.code,
          name: 'Fixture User',
        );
        expect(signedIn.session.user.id, isNotEmpty);
        await expectLater(
          client.verifyCode(phoneNumber: '+18765551234', code: '123456'),
          throwsA(isA<AuthClientException>()),
        );

        await plugin.issueCode(
          context: Object(),
          phoneNumber: '+18765550000',
          now: clock(),
        );
        final outcomes = await runAuthTestConcurrently<String>(16, (_) async {
          try {
            await plugin.verifyCode(
              context: Object(),
              phoneNumber: '+18765550000',
              code: '654321',
              now: clock(),
            );
            return 'verified';
          } on AuthFlowException catch (error) {
            return error.code;
          }
        });
        expect(outcomes.where((value) => value == 'verified'), hasLength(1));
        expect(
          outcomes.where((value) => value == 'invalid_phone_code'),
          hasLength(15),
        );
      },
    );
  });

  group('OAuth and OIDC fixture', () {
    test(
      'uses real token and userinfo codecs with captured requests',
      () async {
        final fixture = AuthOAuthProviderFixture();
        final http = AuthTestHttpClient();
        http.enqueue(
          method: 'POST',
          path: '/token',
          respond: (request) {
            expect(request.body, contains('code=fixture-code'));
            expect(
              request.body,
              isNot(contains('fixture-client-secret-not-a-secret')),
            );
            return AuthTestHttpResponse.json(fixture.tokenResponse());
          },
        );
        http.enqueue(
          method: 'GET',
          path: '/userinfo',
          respond: (request) {
            expect(request.headers['authorization'], 'Bearer fixture-access');
            return AuthTestHttpResponse.json(fixture.userInfoResponse());
          },
        );

        final token = await exchangeOAuthAuthorizationCode(
          fixture.provider,
          code: 'fixture-code',
          codeVerifier: 'fixture-verifier',
          httpClient: http,
        );
        final profile = await loadOAuthProfile(
          fixture.provider,
          token: token,
          httpClient: http,
        );
        final user = fixture.provider.mapProfile(profile);

        expect(token.accessToken, 'fixture-access');
        expect(user.id, 'fixture-account');
        expect(http.pendingResponses, 0);
        expect(
          AuthOAuthProviderFixture(type: AuthProviderType.oidc).provider.type,
          AuthProviderType.oidc,
        );
      },
    );
  });

  group('scripted typed plugin clients', () {
    test(
      'WebAuthn fixture exercises options, assertion, and failure codecs',
      () async {
        const fixture = AuthWebAuthnClientFixture();
        final http = AuthTestHttpClient();
        http.enqueueJson(
          method: 'GET',
          path: '/auth/csrf',
          response: <String, dynamic>{'csrfToken': 'fixture-csrf'},
        );
        http.enqueueJson(
          method: 'POST',
          path: '/auth/webauthn/authenticate/options',
          expectedRequest: <String, dynamic>{'_csrf': 'fixture-csrf'},
          response: fixture.authenticationOptions(),
        );
        http.enqueueOneTimeJson(
          method: 'POST',
          path: '/auth/webauthn/authenticate/verify',
          expectedRequest: <String, dynamic>{
            'credential': fixture.assertion(),
            '_csrf': 'fixture-csrf',
          },
          response: fixture.authenticationResult(),
          replayCode: 'webauthn_challenge_invalid',
        );
        const plugin = AuthWebAuthnClientPlugin();
        final auth = _client(http, <AuthClientPlugin<Object>>[plugin]);
        final client = auth.plugins.use(plugin);

        final options = await client.beginAuthentication();
        final result = await client.completeAuthentication(
          credential: fixture.assertion(),
        );
        expect(options.relyingPartyId, 'example.test');
        expect(result.credential.credentialId, fixture.credentialId);
        await expectLater(
          client.completeAuthentication(credential: fixture.assertion()),
          throwsA(
            isA<AuthClientException>().having(
              (error) => error.code,
              'code',
              'webauthn_challenge_invalid',
            ),
          ),
        );
      },
    );

    test('API-key fixture preserves one-time raw-key semantics', () async {
      const fixture = AuthApiKeyClientFixture();
      final http = AuthTestHttpClient();
      http.enqueueJson(
        method: 'GET',
        path: '/auth/csrf',
        response: <String, dynamic>{'csrfToken': 'fixture-csrf'},
      );
      http.enqueueJson(
        method: 'POST',
        path: '/auth/api-keys/create',
        expectedRequest: <String, dynamic>{
          'name': 'Fixture key',
          'scopes': <String>['tasks:read'],
          'expiresAt': null,
          '_csrf': 'fixture-csrf',
        },
        response: fixture.issued(),
      );
      http.enqueueJson(
        method: 'GET',
        path: '/auth/api-keys/list',
        response: fixture.list(),
      );
      const plugin = AuthApiKeyClientPlugin();
      final auth = _client(http, <AuthClientPlugin<Object>>[plugin]);
      final client = auth.plugins.use(plugin);

      final issued = await client.create(
        name: 'Fixture key',
        scopes: const <String>['tasks:read'],
      );
      final listed = await client.list();
      expect(issued.key, contains('fixture-raw-key'));
      expect(listed.single.keyPrefix, isNot(contains(issued.key)));
      expect(fixture.list().toString(), isNot(contains(issued.key)));
    });

    test(
      'two-factor fixture exercises enrollment, status, and replay failure',
      () async {
        final fixture = AuthTwoFactorClientFixture(DateTime.utc(2030));
        final http = AuthTestHttpClient();
        http.enqueueJson(
          method: 'GET',
          path: '/auth/csrf',
          response: <String, dynamic>{'csrfToken': 'fixture-csrf'},
        );
        http.enqueueJson(
          method: 'POST',
          path: '/auth/2fa/enroll',
          expectedRequest: <String, dynamic>{
            'accountLabel': 'Fixture User',
            '_csrf': 'fixture-csrf',
          },
          response: fixture.enrollment(),
        );
        http.enqueueJson(
          method: 'GET',
          path: '/auth/2fa/status',
          response: fixture.status(),
        );
        http.enqueueOneTimeJson(
          method: 'POST',
          path: '/auth/2fa/enroll/verify',
          expectedRequest: <String, dynamic>{
            'code': '123456',
            '_csrf': 'fixture-csrf',
          },
          response: fixture.recoveryCodes(),
          replayCode: 'two_factor_enrollment_missing',
        );
        const plugin = AuthTwoFactorClientPlugin();
        final auth = _client(http, <AuthClientPlugin<Object>>[plugin]);
        final client = auth.plugins.use(plugin);

        final enrollment = await client.beginEnrollment(
          accountLabel: 'Fixture User',
        );
        final status = await client.status();
        final recovery = await client.verifyEnrollment(code: '123456');
        expect(enrollment.secret, 'JBSWY3DPEHPK3PXP');
        expect(status.enabled, isTrue);
        expect(recovery.codes, hasLength(2));
        await expectLater(
          client.verifyEnrollment(code: '123456'),
          throwsA(
            isA<AuthClientException>().having(
              (error) => error.code,
              'code',
              'two_factor_enrollment_missing',
            ),
          ),
        );
      },
    );
  });
}

AuthClient _client(
  AuthTestHttpClient http,
  List<AuthClientPlugin<Object>> plugins,
) => AuthClient(
  baseUrl: Uri.parse('https://app.example.test'),
  httpClient: http,
  plugins: plugins,
);

Map<String, dynamic> _session(AuthUser user) => <String, dynamic>{
  ...AuthSession(
    user: user,
    expiresAt: DateTime.utc(2030, 1, 1, 1),
    strategy: AuthSessionStrategy.session,
  ).toJson(),
};
