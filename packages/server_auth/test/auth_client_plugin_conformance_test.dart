import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:property_testing/property_testing.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('installed client plugin conformance', () {
    test(
      'covers every independent built-in server/client plugin pair',
      () async {
        final core = InMemoryAuthStore();
        final webAuthnProvider = WebAuthnProvider(
          getUserInfo: (_, _, _) => null,
          getRelyingParty: (_, _) => const WebAuthnRelyingParty(
            id: 'example.test',
            name: 'Example',
            origin: 'https://example.test',
          ),
        );
        final pairs =
            <(AuthServerPlugin<Object>, AuthInstalledClientOperationContract)>[
              (
                AnonymousPlugin<Object>(),
                AuthInstalledClientOperationContract(
                  endpointId: 'anonymous.signIn',
                  plugin: const AuthAnonymousClientPlugin(),
                  invoke: (api) => (api as AuthAnonymousClient).signIn(),
                  response: AuthClientConformanceResponse.json(_sessionJson),
                  malformedResponses: _malformed,
                  verifyResponse: (value) =>
                      expect((value as AuthSession).user.id, 'user-1'),
                ),
              ),
              (
                EmailOtpPlugin<Object>(
                  sendCode: (_) {},
                  rateLimitHashKey: 'client-conformance-email-key-32-bytes',
                ),
                AuthInstalledClientOperationContract(
                  endpointId: 'emailOtp.signIn',
                  plugin: const AuthEmailOtpClientPlugin(),
                  invoke: (api) => (api as AuthEmailOtpClient).signIn(
                    email: 'user@example.test',
                    otp: 'otp-secret-123456',
                  ),
                  response: AuthClientConformanceResponse.json(_sessionJson),
                  malformedResponses: _malformed,
                  sensitiveValues: const <String>['otp-secret-123456'],
                ),
              ),
              (
                PhoneNumberPlugin<Object>(
                  store: InMemoryAuthPhoneNumberStore(),
                  sendCode: (_) {},
                  codeHashKey: 'client-conformance-phone-key-32-bytes',
                ),
                AuthInstalledClientOperationContract(
                  endpointId: 'phoneNumber.sendCode',
                  plugin: const AuthPhoneNumberClientPlugin(),
                  invoke: (api) => (api as AuthPhoneNumberClient).sendCode(
                    phoneNumber: '+15555550123',
                  ),
                  response: const AuthClientConformanceResponse.json(
                    <String, Object?>{
                      'status': 'verification_sent',
                      'expiresAt': '2030-01-01T00:05:00.000Z',
                    },
                  ),
                  malformedResponses: _malformed,
                ),
              ),
              (
                UsernamePlugin<Object>(),
                AuthInstalledClientOperationContract(
                  endpointId: 'username.signIn',
                  plugin: const AuthUsernameClientPlugin(),
                  invoke: (api) => (api as AuthUsernameClient).signIn(
                    identifier: 'user',
                    password: 'password-secret',
                  ),
                  response: AuthClientConformanceResponse.json(
                    <String, Object?>{
                      'status': 'authenticated',
                      'username': 'user',
                      ..._sessionJson,
                    },
                  ),
                  malformedResponses: _malformed,
                  sensitiveValues: const <String>['password-secret'],
                ),
              ),
              (
                AuthApiKeyPlugin<Object>(store: InMemoryAuthApiKeyStore()),
                AuthInstalledClientOperationContract(
                  endpointId: 'apiKey.list',
                  plugin: const AuthApiKeyClientPlugin(),
                  invoke: (api) => (api as AuthApiKeyClient).list(),
                  response: const AuthClientConformanceResponse.json(
                    <String, Object?>{'apiKeys': <Object?>[]},
                  ),
                  malformedResponses: _malformed,
                  verifyResponse: (value) => expect(value, isEmpty),
                ),
              ),
              (
                WebAuthnPlugin<Object>(provider: webAuthnProvider),
                AuthInstalledClientOperationContract(
                  endpointId: 'webauthn.authenticationOptions',
                  plugin: const AuthWebAuthnClientPlugin(),
                  invoke: (api) =>
                      (api as AuthWebAuthnClient).beginAuthentication(),
                  response: const AuthClientConformanceResponse.json(
                    <String, Object?>{
                      'challenge': 'challenge-1',
                      'rpId': 'example.test',
                      'timeout': 60000,
                      'userVerification': 'preferred',
                      'allowCredentials': <Object?>[],
                    },
                  ),
                  malformedResponses: _malformed,
                ),
              ),
              (
                DeviceAuthorizationPlugin<Object>(
                  verificationUri: 'https://example.test/device',
                  validateClient: (_, _, _) => true,
                  issueToken:
                      ({
                        required context,
                        required user,
                        required clientId,
                        required scopes,
                        required authorizationId,
                      }) => const AuthDeviceAccessToken(
                        accessToken: 'unused',
                        expiresIn: Duration(minutes: 5),
                      ),
                ),
                AuthInstalledClientOperationContract(
                  endpointId: 'deviceAuthorization.request',
                  plugin: const AuthDeviceAuthorizationClientPlugin(),
                  invoke: (api) =>
                      (api as AuthDeviceAuthorizationClient).authorize(
                        clientId: 'cli-1',
                        scopes: const <String>['openid'],
                      ),
                  response: const AuthClientConformanceResponse.json(
                    <String, Object?>{
                      'device_code': 'device-1',
                      'user_code': 'ABCD-EFGH',
                      'verification_uri': 'https://example.test/device',
                      'expires_in': 600,
                      'interval': 5,
                    },
                  ),
                  malformedResponses: _malformed,
                ),
              ),
              (
                OrganizationPlugin<Object>(
                  store: InMemoryAuthOrganizationStore(),
                ),
                AuthInstalledClientOperationContract(
                  endpointId: 'organization.checkSlug',
                  plugin: const AuthOrganizationClientPlugin(),
                  invoke: (api) =>
                      (api as AuthOrganizationClient).checkSlug('routed'),
                  response: const AuthClientConformanceResponse.json(
                    <String, Object?>{'available': true},
                  ),
                  malformedResponses: _malformed,
                  verifyResponse: (value) => expect(value, isTrue),
                ),
              ),
              (
                AdminPlugin<Object>(store: InMemoryAuthAdminStore(core)),
                AuthInstalledClientOperationContract(
                  endpointId: 'admin.listUsers',
                  plugin: const AuthAdminClientPlugin(),
                  invoke: (api) => (api as AuthAdminClient).listUsers(limit: 1),
                  response: const AuthClientConformanceResponse.json(
                    <String, Object?>{
                      'items': <Object?>[],
                      'total': 0,
                      'limit': 1,
                      'offset': 0,
                    },
                  ),
                  malformedResponses: _malformed,
                ),
              ),
              (
                AuthLastAuthenticationMethodPlugin<Object>(
                  signingKey: 'last-method-conformance-signing-key-32-bytes',
                  browserStore: _NoopLastMethodStore(),
                  policy: AuthLastAuthenticationMethodPolicy(
                    allowedMethods: <AuthLastAuthenticationMethodId>{
                      AuthLastAuthenticationMethodId.credentials,
                    },
                  ),
                ),
                AuthInstalledClientOperationContract(
                  endpointId: 'lastAuthenticationMethod.read',
                  plugin: const AuthLastAuthenticationMethodClientPlugin(),
                  invoke: (api) =>
                      (api as AuthLastAuthenticationMethodClient).read(),
                  response: const AuthClientConformanceResponse.json(
                    <String, Object?>{
                      'method': 'credentials',
                      'expiresAt': '2030-01-01T00:00:00.000Z',
                    },
                  ),
                  malformedResponses: _malformed,
                ),
              ),
            ];

        for (final (serverPlugin, operation) in pairs) {
          final store = serverPlugin is AdminPlugin<Object>
              ? core
              : InMemoryAuthStore();
          final runtime = AuthRuntime<Object>(
            options: AuthOptions<Object>(
              providers: <AuthProvider>[
                if (serverPlugin is WebAuthnPlugin<Object>) webAuthnProvider,
              ],
              store: store,
              storeMode: AuthStoreMode.ephemeral,
              plugins: <AuthServerPlugin<Object>>[serverPlugin],
            ),
          );
          final suite = AuthPluginConformanceSuite<Object>.fromRuntime(
            runtime,
            installedClientOperations: <AuthInstalledClientOperationContract>[
              operation,
            ],
          );

          final result = await _case(
            suite,
            'clients.installed-contracts',
          ).run();
          expect(result.isPassed, isTrue, reason: operation.endpointId);
        }
      },
    );

    test(
      'executes the installed API against server and client contracts',
      () async {
        const plugin = _EchoClientPlugin();
        final suite = _suite(<AuthInstalledClientOperationContract>[
          AuthInstalledClientOperationContract(
            endpointId: 'echo.read',
            plugin: plugin,
            invoke: (api) => (api as _EchoClient).read('request-value'),
            response: const AuthClientConformanceResponse.json(
              <String, Object?>{'value': 'response-value'},
            ),
            malformedResponses: const <AuthClientConformanceResponse>[
              AuthClientConformanceResponse.raw('[]'),
              AuthClientConformanceResponse.json(<String, Object?>{}),
            ],
            verifyResponse: (value) => expect(value, 'response-value'),
          ),
        ]);

        final result = await _case(suite, 'clients.installed-contracts').run();

        expect(result.isPassed, isTrue);
      },
    );

    test(
      'rejects responses that violate server schema values or types',
      () async {
        final invalidResponses = <Map<String, Object?>>[
          <String, Object?>{'value': 'response', 'status': 'wrong'},
          <String, Object?>{'value': 42},
        ];

        for (final response in invalidResponses) {
          final suite = _suite(<AuthInstalledClientOperationContract>[
            AuthInstalledClientOperationContract(
              endpointId: 'echo.read',
              plugin: const _EchoClientPlugin(),
              invoke: (api) => (api as _EchoClient).read('request-value'),
              response: AuthClientConformanceResponse.json(response),
            ),
          ]);

          await expectLater(
            _case(suite, 'clients.installed-contracts').run,
            throwsA(
              isA<AuthPluginConformanceFailure>().having(
                (failure) => failure.cause.toString(),
                'cause',
                contains('server response contract'),
              ),
            ),
          );
        }
      },
    );

    test('rejects duplicate executable operation IDs', () async {
      const plugin = _EchoClientPlugin();
      final operation = AuthInstalledClientOperationContract(
        endpointId: 'echo.read',
        plugin: plugin,
        invoke: (api) => (api as _EchoClient).read('value'),
        response: const AuthClientConformanceResponse.json(<String, Object?>{
          'value': 'response',
        }),
      );
      final suite = _suite(<AuthInstalledClientOperationContract>[
        operation,
        operation,
      ]);

      await expectLater(
        _case(suite, 'clients.installed-contracts').run(),
        throwsA(isA<AuthPluginConformanceFailure>()),
      );
    });

    test('client registry rejects duplicate plugin IDs', () {
      final transport = AuthClientTransport(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => AuthClientPluginRegistry(
          context: AuthClientPluginContext(transport: transport),
          plugins: const <AuthClientPlugin<Object>>[
            _EchoClientPlugin(),
            _DuplicateEchoClientPlugin(),
          ],
        ),
        throwsStateError,
      );
    });

    test('hostile response secrets never enter public results', () async {
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 1, maxLength: 96),
        (secret) async {
          const plugin = _EchoClientPlugin();
          final suite = _suite(<AuthInstalledClientOperationContract>[
            AuthInstalledClientOperationContract(
              endpointId: 'echo.read',
              plugin: plugin,
              invoke: (api) => (api as _EchoClient).read('safe-request'),
              response: AuthClientConformanceResponse.json(<String, Object?>{
                'value': 'safe-response',
                'credential': secret,
              }),
              malformedResponses: <AuthClientConformanceResponse>[
                AuthClientConformanceResponse.json(<String, Object?>{
                  'credential': secret,
                }),
              ],
              sensitiveValues: <String>[secret],
            ),
          ]);

          final result = await _case(
            suite,
            'clients.installed-contracts',
          ).run();
          expect(result.isPassed, isTrue);
        },
        PropertyConfig(numTests: 200, seed: 20260820),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.error?.toString());
    });
  });
}

const List<AuthClientConformanceResponse> _malformed =
    <AuthClientConformanceResponse>[AuthClientConformanceResponse.raw('[]')];

final Map<String, Object?> _sessionJson = <String, Object?>{
  'status': 'authenticated',
  'user': <String, Object?>{
    'id': 'user-1',
    'email': 'user@example.test',
    'roles': <String>['user'],
    'attributes': <String, Object?>{},
  },
  'expires': '2030-01-01T00:00:00.000Z',
  'strategy': 'session',
};

final class _NoopLastMethodStore
    implements AuthLastAuthenticationMethodBrowserStore<Object> {
  @override
  String? readCookie(Object context, String name) => null;

  @override
  void writeCookie(Object context, AuthLastAuthenticationMethodCookie cookie) {}
}

AuthPluginConformanceSuite<Object> _suite(
  Iterable<AuthInstalledClientOperationContract> operations,
) {
  final runtime = AuthRuntime<Object>(
    options: AuthOptions<Object>(
      providers: const <AuthProvider>[],
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      plugins: const <AuthServerPlugin<Object>>[_EchoServerPlugin()],
    ),
  );
  return AuthPluginConformanceSuite<Object>.fromRuntime(
    runtime,
    installedClientOperations: operations,
  );
}

AuthPluginConformanceCase _case(
  AuthPluginConformanceSuite<Object> suite,
  String id,
) => suite.cases.singleWhere((value) => value.id == id);

final class _EchoClientPlugin implements AuthClientPlugin<_EchoClient> {
  const _EchoClientPlugin();

  @override
  String get id => 'echo';

  @override
  _EchoClient install(AuthClientPluginContext context) =>
      _EchoClient(context.transport);
}

final class _DuplicateEchoClientPlugin
    implements AuthClientPlugin<_EchoClient> {
  const _DuplicateEchoClientPlugin();

  @override
  String get id => 'echo';

  @override
  _EchoClient install(AuthClientPluginContext context) =>
      _EchoClient(context.transport);
}

final class _EchoClient {
  const _EchoClient(this._transport);

  final AuthClientTransport _transport;

  Future<String> read(String requestValue) async {
    final response = await _transport.request(
      'POST',
      '/echo',
      body: <String, dynamic>{'value': requestValue},
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['value'] is! String) {
      throw const FormatException('Invalid echo response');
    }
    return decoded['value'] as String;
  }
}

final class _EchoServerPlugin
    implements
        AuthServerPlugin<Object>,
        AuthEndpointContributor<Object>,
        AuthClientOperationContributor {
  const _EchoServerPlugin();

  @override
  String get id => 'echo';

  @override
  Iterable<AuthEndpointDescriptor<Object>> get endpoints =>
      <AuthEndpointDescriptor<Object>>[
        TypedAuthEndpointDescriptor<
          Object,
          Map<String, dynamic>,
          Map<String, dynamic>
        >(
          id: 'echo.read',
          method: AuthOperationMethod.post,
          path: '/echo',
          semantics: const AuthOperationSemantics.readOnly(),
          requestCodec: AuthOperationCodec<Map<String, dynamic>>(
            decode: (value) {
              if (value['value'] is! String) {
                throw const FormatException('Invalid echo request');
              }
              return value;
            },
            encode: (value) => value,
            schema: const <String, Object?>{
              'type': 'object',
              'required': <String>['value'],
            },
          ),
          responseCodec: AuthOperationCodec<Map<String, dynamic>>(
            decode: (value) => value,
            encode: (value) => value,
            schema: const <String, Object?>{
              'type': 'object',
              'required': <String>['value'],
              'properties': <String, Object?>{
                'value': <String, Object?>{'type': 'string'},
                'status': <String, Object?>{'const': 'ok'},
              },
            },
          ),
          rateLimitOperation: const AuthRateLimitOperation('echo', 'read'),
          handler: (_, request) => request,
        ),
      ];

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations =>
      const <AuthClientOperationDescriptor>[
        AuthClientOperationDescriptor(
          id: 'echo.read',
          method: AuthOperationMethod.post,
          path: '/echo',
        ),
      ];

  @override
  void configure(AuthServerPluginContext<Object> context) {}
}
