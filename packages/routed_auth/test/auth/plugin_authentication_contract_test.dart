import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

const _password = 'safe-password-123';
const _phoneHashKey = '0123456789abcdef0123456789abcdef';

final class _Hasher implements PasswordHasher {
  @override
  String hash(String password) => 'hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) =>
      PasswordVerification(
        matches: encodedHash == 'hash:$password',
        needsRehash: false,
      );
}

final class _RejectAuthenticationPlugin
    implements
        AuthServerPlugin<EngineContext>,
        AuthAuthenticationPolicyContributor<EngineContext> {
  const _RejectAuthenticationPlugin();

  @override
  String get id => 'test_reject_authentication';

  @override
  void configure(AuthServerPluginContext<EngineContext> context) {}

  @override
  void enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<EngineContext> request,
  ) {
    if (request.phase == AuthAuthenticationPolicyPhase.beforeSessionIssue) {
      throw AuthFlowException('account_unavailable');
    }
  }
}

final class _Counter {
  int sessionCallbacks = 0;
}

final class _PreparedPlugin {
  const _PreparedPlugin({
    required this.manager,
    required this.authenticate,
    required this.counter,
  });

  final AuthManager manager;
  final Future<TestResponse> Function(TestClient client) authenticate;
  final _Counter counter;
}

final class _PluginCase {
  const _PluginCase(this.id, this.prepare);

  final String id;
  final Future<_PreparedPlugin> Function({
    required AuthSessionStrategy strategy,
    required bool exposeToken,
    required bool rejectAuthentication,
  })
  prepare;
}

void main() {
  final cases = <_PluginCase>[
    _PluginCase('anonymous', _prepareAnonymous),
    _PluginCase('email_otp', _prepareEmailOtp),
    _PluginCase('phone_number', _preparePhone),
    _PluginCase('username', _prepareUsername),
    _PluginCase('webauthn', _prepareWebAuthn),
  ];

  group('host-owned plugin authentication contract', () {
    for (final pluginCase in cases) {
      for (final strategy in AuthSessionStrategy.values) {
        for (final exposeToken in <bool>[false, true]) {
          test(
            '${pluginCase.id} ${strategy.name} exposeToken=$exposeToken',
            () async {
              final prepared = await pluginCase.prepare(
                strategy: strategy,
                exposeToken: exposeToken,
                rejectAuthentication: false,
              );
              final fixture = await _fixture(prepared.manager);
              var signInEvents = 0;
              var sessionEvents = 0;
              final events = await fixture.engine.container
                  .make<EventManager>();
              events.listen<AuthSignInEvent>((_) => signInEvents++);
              events.listen<AuthSessionEvent>((_) => sessionEvents++);

              final response = await prepared.authenticate(fixture.client);
              response.assertStatus(HttpStatus.ok);
              final body = response.json();
              expect(body['contractMarker'], pluginCase.id);
              expect(body['strategy'], strategy.name);
              expect(body['user'], isA<Map<String, dynamic>>());
              expect(prepared.counter.sessionCallbacks, 1);
              expect(signInEvents, 1);
              expect(sessionEvents, 1);

              final cookieName = strategy == AuthSessionStrategy.jwt
                  ? prepared.manager.options.jwtOptions.cookieName
                  : 'plugin_contract_session';
              final authCookie = response.cookie(cookieName);
              expect(authCookie, isNotNull);
              if (strategy == AuthSessionStrategy.jwt && exposeToken) {
                expect(body['token'], authCookie!.value);
              } else {
                expect(body, isNot(contains('token')));
                expect(response.body, isNot(contains('token')));
              }

              final followUp = await fixture.client.get(
                '/auth/session',
                headers: <String, List<String>>{
                  HttpHeaders.cookieHeader: <String>[
                    '${authCookie!.name}=${authCookie.value}',
                  ],
                },
              );
              followUp.assertStatus(HttpStatus.ok);
              expect(
                followUp.json()['user']['id'],
                (body['user'] as Map<String, dynamic>)['id'],
              );
              expect(prepared.counter.sessionCallbacks, 2);
              expect(signInEvents, 1);
              expect(sessionEvents, 2);
            },
          );
        }
      }

      test(
        '${pluginCase.id} central policy rejection issues no auth',
        () async {
          final prepared = await pluginCase.prepare(
            strategy: AuthSessionStrategy.jwt,
            exposeToken: true,
            rejectAuthentication: true,
          );
          final fixture = await _fixture(prepared.manager);
          var signInEvents = 0;
          var sessionEvents = 0;
          final events = await fixture.engine.container.make<EventManager>();
          events.listen<AuthSignInEvent>((_) => signInEvents++);
          events.listen<AuthSessionEvent>((_) => sessionEvents++);

          final response = await prepared.authenticate(fixture.client);
          expect(response.statusCode, isNot(HttpStatus.ok));
          expect(response.json()['error'], 'account_unavailable');
          expect(
            response.cookie(prepared.manager.options.jwtOptions.cookieName),
            isNull,
          );
          expect(response.body, isNot(contains('token')));
          expect(prepared.counter.sessionCallbacks, 0);
          expect(signInEvents, 0);
          expect(sessionEvents, 0);
        },
      );
    }
  });
}

Future<_PreparedPlugin> _prepareAnonymous({
  required AuthSessionStrategy strategy,
  required bool exposeToken,
  required bool rejectAuthentication,
}) async {
  final counter = _Counter();
  final manager = _manager(
    id: 'anonymous',
    store: InMemoryAuthStore(),
    strategy: strategy,
    exposeToken: exposeToken,
    counter: counter,
    plugins: <AuthServerPlugin<EngineContext>>[
      AnonymousPlugin<EngineContext>(),
      if (rejectAuthentication) const _RejectAuthenticationPlugin(),
    ],
  );
  return _PreparedPlugin(
    manager: manager,
    counter: counter,
    authenticate: (client) =>
        client.postJson('/auth/sign-in/anonymous', const <String, dynamic>{}),
  );
}

Future<_PreparedPlugin> _prepareEmailOtp({
  required AuthSessionStrategy strategy,
  required bool exposeToken,
  required bool rejectAuthentication,
}) async {
  final counter = _Counter();
  String? deliveredCode;
  final plugin = EmailOtpPlugin<EngineContext>(
    secret: 'plugin-contract-email-key-not-for-production-use',
    generateOtp: (_) => '123456',
    sendCode: (delivery) => deliveredCode = delivery.code,
  );
  final manager = _manager(
    id: 'email_otp',
    store: InMemoryAuthStore(),
    strategy: strategy,
    exposeToken: exposeToken,
    counter: counter,
    plugins: <AuthServerPlugin<EngineContext>>[
      plugin,
      if (rejectAuthentication) const _RejectAuthenticationPlugin(),
    ],
  );
  return _PreparedPlugin(
    manager: manager,
    counter: counter,
    authenticate: (client) async {
      final sent = await client.postJson(
        '/auth/email-otp/send-verification-otp',
        const <String, dynamic>{
          'email': 'email-otp@example.com',
          'type': 'sign-in',
        },
      );
      sent.assertStatus(HttpStatus.ok);
      return client.postJson('/auth/sign-in/email-otp', <String, dynamic>{
        'email': 'email-otp@example.com',
        'otp': deliveredCode,
      });
    },
  );
}

Future<_PreparedPlugin> _preparePhone({
  required AuthSessionStrategy strategy,
  required bool exposeToken,
  required bool rejectAuthentication,
}) async {
  final counter = _Counter();
  String? deliveredCode;
  final plugin = PhoneNumberPlugin<EngineContext>(
    store: InMemoryAuthPhoneNumberStore(),
    codeHashKey: _phoneHashKey,
    allowSignUp: true,
    generateCode: (_) => '123456',
    sendCode: (delivery) => deliveredCode = delivery.code,
  );
  final manager = _manager(
    id: 'phone_number',
    store: InMemoryAuthStore(),
    strategy: strategy,
    exposeToken: exposeToken,
    counter: counter,
    plugins: <AuthServerPlugin<EngineContext>>[
      plugin,
      if (rejectAuthentication) const _RejectAuthenticationPlugin(),
    ],
  );
  return _PreparedPlugin(
    manager: manager,
    counter: counter,
    authenticate: (client) async {
      final sent = await client.postJson(
        '/auth/phone-number/send-code',
        const <String, dynamic>{'phoneNumber': '+18765551234'},
      );
      sent.assertStatus(HttpStatus.ok);
      return client.postJson(
        '/auth/phone-number/verify-code',
        <String, dynamic>{'phoneNumber': '+18765551234', 'code': deliveredCode},
      );
    },
  );
}

Future<_PreparedPlugin> _prepareUsername({
  required AuthSessionStrategy strategy,
  required bool exposeToken,
  required bool rejectAuthentication,
}) async {
  final counter = _Counter();
  final store = InMemoryAuthStore();
  final now = DateTime.now().toUtc();
  final user = AuthUser(
    id: 'username-user',
    email: 'username@example.com',
    attributes: const <String, dynamic>{'username': 'username-user'},
  );
  await store.registerUsername(
    AuthUsernameRegistrationCommand(
      user: user,
      credential: AuthPasswordCredential(
        id: 'username-credential',
        userId: user.id,
        identifier: 'username-user',
        passwordHash: 'hash:$_password',
        createdAt: now,
        updatedAt: now,
      ),
    ),
  );
  final manager = _manager(
    id: 'username',
    store: store,
    strategy: strategy,
    exposeToken: exposeToken,
    counter: counter,
    passwordHasher: _Hasher(),
    plugins: <AuthServerPlugin<EngineContext>>[
      UsernamePlugin<EngineContext>(),
      if (rejectAuthentication) const _RejectAuthenticationPlugin(),
    ],
  );
  return _PreparedPlugin(
    manager: manager,
    counter: counter,
    authenticate: (client) =>
        client.postJson('/auth/username/sign-in', const <String, dynamic>{
          'identifier': 'username-user',
          'password': _password,
        }),
  );
}

Future<_PreparedPlugin> _prepareWebAuthn({
  required AuthSessionStrategy strategy,
  required bool exposeToken,
  required bool rejectAuthentication,
}) async {
  final counter = _Counter();
  final store = InMemoryAuthStore();
  final user = AuthUser(id: 'webauthn-user', email: 'webauthn@example.com');
  await store.users.create(user);
  final keyPair = _KeyPair.create();
  final credentialId = base64UrlNoPadding(
    List<int>.generate(16, (index) => index + 1),
  );
  await store.webAuthnAuthenticators.create(
    WebAuthnAuthenticator(
      credentialId: credentialId,
      publicKey: base64UrlNoPadding(keyPair.cosePublicKey),
      counter: 0,
      userId: user.id,
      createdAt: DateTime.now().toUtc(),
    ),
  );
  final provider = WebAuthnProvider(
    getUserInfo: (_, _, _) => null,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'localhost',
      name: 'Plugin contract test',
      origin: 'http://localhost',
    ),
  );
  final manager = _manager(
    id: 'webauthn',
    store: store,
    strategy: strategy,
    exposeToken: exposeToken,
    counter: counter,
    providers: <AuthProvider>[provider],
    plugins: <AuthServerPlugin<EngineContext>>[
      WebAuthnPlugin<EngineContext>(provider: provider),
      if (rejectAuthentication) const _RejectAuthenticationPlugin(),
    ],
  );
  return _PreparedPlugin(
    manager: manager,
    counter: counter,
    authenticate: (client) async {
      final options = await client.postJson(
        '/auth/webauthn/authenticate/options',
        <String, dynamic>{'userId': user.id},
      );
      expect(options.statusCode, HttpStatus.ok, reason: options.body);
      return client
          .postJson('/auth/webauthn/authenticate/verify', <String, dynamic>{
            'userId': user.id,
            'credential': _browserAssertion(
              challenge: options.json()['challenge'] as String,
              credentialId: credentialId,
              keyPair: keyPair,
            ),
          });
    },
  );
}

AuthManager _manager({
  required String id,
  required InMemoryAuthStore store,
  required AuthSessionStrategy strategy,
  required bool exposeToken,
  required _Counter counter,
  required List<AuthServerPlugin<EngineContext>> plugins,
  List<AuthProvider> providers = const <AuthProvider>[],
  PasswordHasher? passwordHasher,
}) {
  return AuthManager(
    AuthOptions<EngineContext>(
      store: store,
      storeMode: AuthStoreMode.ephemeral,
      providers: providers,
      plugins: plugins,
      passwordHasher: passwordHasher,
      sessionStrategy: strategy,
      jwtOptions: JwtSessionOptions(secret: 'contract-secret-$id'),
      exposeJwtTokenInSessionResponse: exposeToken,
      enforceCsrf: false,
      callbacks: AuthCallbacks<EngineContext>(
        session: (context) {
          counter.sessionCallbacks++;
          return <String, dynamic>{...context.payload, 'contractMarker': id};
        },
      ),
    ),
  );
}

final class _Fixture {
  const _Fixture(this.engine, this.client);

  final Engine engine;
  final TestClient client;
}

Future<_Fixture> _fixture(AuthManager manager) async {
  final key = base64.encode(List<int>.generate(32, (index) => index + 1));
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: <ServiceProvider>[
      RoutedSessionsProvider(
        SessionConfig.cookie(
          appKey: 'base64:$key',
          cookieName: 'plugin_contract_session',
          options: SessionOptions(
            path: '/',
            secure: false,
            httpOnly: true,
            sameSite: SameSite.lax,
          ),
        ),
      ),
    ],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  await engine.initialize();
  final client = TestClient(RoutedRequestHandler(engine));
  addTearDown(() async {
    await client.close();
    await engine.close();
  });
  return _Fixture(engine, client);
}

final class _KeyPair {
  _KeyPair._(this.privateKey, this.x, this.y);

  factory _KeyPair.create() {
    final parameters = ECDomainParameters('secp256r1');
    final point = (parameters.G * BigInt.one)!;
    return _KeyPair._(
      ECPrivateKey(BigInt.one, parameters),
      Uint8List.fromList(_bigIntBytes(point.x!.toBigInteger()!, 32)),
      Uint8List.fromList(_bigIntBytes(point.y!.toBigInteger()!, 32)),
    );
  }

  final ECPrivateKey privateKey;
  final Uint8List x;
  final Uint8List y;

  List<int> get cosePublicKey => <int>[
    0xa5,
    0x01,
    0x02,
    0x03,
    0x26,
    0x20,
    0x01,
    0x21,
    0x58,
    0x20,
    ...x,
    0x22,
    0x58,
    0x20,
    ...y,
  ];
}

Map<String, dynamic> _browserAssertion({
  required String challenge,
  required String credentialId,
  required _KeyPair keyPair,
}) {
  final authenticatorData = <int>[
    ...crypto.sha256.convert(utf8.encode('localhost')).bytes,
    0x05,
    0,
    0,
    0,
    1,
  ];
  final clientData = utf8.encode(
    jsonEncode(<String, dynamic>{
      'type': 'webauthn.get',
      'challenge': challenge,
      'origin': 'http://localhost',
      'crossOrigin': false,
    }),
  );
  final signature = _signDerEs256(<int>[
    ...authenticatorData,
    ...crypto.sha256.convert(clientData).bytes,
  ], keyPair);
  return <String, dynamic>{
    'id': credentialId,
    'rawId': credentialId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientData),
      'authenticatorData': base64UrlNoPadding(authenticatorData),
      'signature': base64UrlNoPadding(signature),
    },
  };
}

Uint8List _signDerEs256(List<int> message, _KeyPair keyPair) {
  final random = FortunaRandom()
    ..seed(
      KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i + 1))),
    );
  final signer = ECDSASigner(SHA256Digest())
    ..init(
      true,
      ParametersWithRandom(
        PrivateKeyParameter<ECPrivateKey>(keyPair.privateKey),
        random,
      ),
    );
  final signature = signer.generateSignature(Uint8List.fromList(message));
  if (signature is! ECSignature) throw StateError('Expected ECDSA signature');
  final r = _derInteger(signature.r);
  final s = _derInteger(signature.s);
  return Uint8List.fromList(<int>[0x30, r.length + s.length, ...r, ...s]);
}

List<int> _derInteger(BigInt value) {
  var bytes = _bigIntBytes(value, 32);
  while (bytes.length > 1 && bytes.first == 0) {
    bytes = bytes.sublist(1);
  }
  if (bytes.first & 0x80 != 0) bytes = <int>[0, ...bytes];
  return <int>[0x02, bytes.length, ...bytes];
}

List<int> _bigIntBytes(BigInt value, int length) {
  final bytes = List<int>.filled(length, 0);
  var remaining = value;
  for (var index = length - 1; index >= 0; index--) {
    bytes[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return bytes;
}
