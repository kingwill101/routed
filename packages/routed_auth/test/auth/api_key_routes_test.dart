import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  test('manages API keys and authenticates API-key middleware', () async {
    final store = InMemoryAuthStore();
    final user = AuthUser(id: 'user-1', email: 'user@example.com');
    await store.users.create(user);
    final feature = AuthApiKeyPlugin<EngineContext>(
      store: InMemoryAuthApiKeyStore(),
      sessionExchangeEnabled: true,
      keyIdGenerator: _queuedGenerator(['key-id', 'rotated-id']),
      secretGenerator: _queuedGenerator(['secret', 'rotated-secret']),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider(authorize: (_, _, _) => user)],
        plugins: [feature],
      ),
    );
    final engine = testEngine(
      providers: [RoutedSessionsProvider(_sessionConfig())],
    );
    engine.addGlobalMiddleware(sessionMiddleware());
    engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
    AuthRoutes(manager).register(engine.defaultRouter);
    engine.get(
      '/private',
      (ctx) => ctx.json({
        'userId': SessionAuth.current(ctx)?.id,
        'canRead': currentApiKey(ctx)?.allowsScope('jobs:read') == true,
      }),
      middlewares: [
        apiKeyAuthentication(plugin: feature, userStore: store.users),
      ],
    );
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final csrfResponse = await client.get('/auth/csrf');
    final csrf = csrfResponse.json()['csrfToken'] as String;
    final sessionCookie = csrfResponse.cookie('test_session')!;
    final signIn = await client.postJson(
      '/auth/signin/credentials',
      {'email': 'user@example.com', 'password': 'secret', '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookie(sessionCookie)],
      },
    );
    signIn.assertStatus(HttpStatus.ok);
    final authCookie = signIn.cookie('test_session')!;

    final created = await client.postJson(
      '/auth/api-keys/create',
      {
        'name': 'worker',
        'scopes': ['jobs:read'],
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookie(authCookie)],
      },
    );
    created.assertStatus(HttpStatus.ok);
    final createdBody = created.json();
    final rawKey = createdBody['apiKey'] as String;
    final keyId = createdBody['id'] as String;
    expect(rawKey, isNotEmpty);
    expect(createdBody, isNot(contains('secretHash')));

    final listed = await client.get(
      '/auth/api-keys/list',
      headers: {
        HttpHeaders.cookieHeader: [_cookie(authCookie)],
      },
    );
    listed.assertStatus(HttpStatus.ok);
    expect(listed.json()['apiKeys'], hasLength(1));
    expect(jsonEncode(listed.json()), isNot(contains(rawKey)));

    final privateClient = TestClient(RoutedRequestHandler(engine));
    addTearDown(privateClient.close);
    final privateResponse = await privateClient.get(
      '/private',
      headers: {
        'x-api-key': [rawKey],
      },
    );
    privateResponse.assertStatus(HttpStatus.ok);
    expect(privateResponse.json()['userId'], 'user-1');
    expect(privateResponse.json()['canRead'], isTrue);

    final malformedAuthorization = await privateClient.get(
      '/private',
      headers: {
        'authorization': ['ApiKey'],
      },
    );
    malformedAuthorization.assertStatus(HttpStatus.unauthorized);

    final exchanged = await privateClient.postJson(
      '/auth/api-keys/exchange',
      const <String, dynamic>{},
      headers: {
        'x-api-key': [rawKey],
      },
    );
    exchanged.assertStatus(HttpStatus.ok);
    expect(exchanged.json()['user']['id'], 'user-1');
    final exchangedCookie = exchanged.cookie('test_session');
    expect(exchangedCookie, isNotNull);

    final exchangedSession = await client.get(
      '/auth/session',
      headers: {
        HttpHeaders.cookieHeader: [_cookie(exchangedCookie!)],
      },
    );
    exchangedSession.assertStatus(HttpStatus.ok);
    expect(exchangedSession.json()['user']['id'], 'user-1');
    final sessions = await store.sessions.listForUser('user-1');
    expect(
      sessions.any((session) => session.authenticationMethod == 'api_key'),
      isTrue,
    );

    final rotated = await client.postJson(
      '/auth/api-keys/rotate',
      {'id': keyId, '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookie(authCookie)],
      },
    );
    rotated.assertStatus(HttpStatus.ok);
    final rotatedKey = rotated.json()['apiKey'] as String;
    expect(rotatedKey, isNot(rawKey));

    final oldKeyResponse = await privateClient.get(
      '/private',
      headers: {
        'x-api-key': [rawKey],
      },
    );
    oldKeyResponse.assertStatus(HttpStatus.unauthorized);
    final newKeyResponse = await privateClient.get(
      '/private',
      headers: {
        'authorization': ['ApiKey $rotatedKey'],
      },
    );
    newKeyResponse.assertStatus(HttpStatus.ok);

    final revoked = await client.postJson(
      '/auth/api-keys/revoke',
      {'id': keyId, '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookie(authCookie)],
      },
    );
    revoked.assertStatus(HttpStatus.ok);
  });
}

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (i) => i + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'test_session',
    options: SessionOptions(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

String _cookie(Cookie cookie) => '${cookie.name}=${cookie.value}';

AuthApiKeyTokenGenerator _queuedGenerator(List<String> values) {
  var index = 0;
  return ({int length = 32}) {
    if (index >= values.length) throw StateError('token queue exhausted');
    return values[index++];
  };
}
