import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:property_testing/property_testing.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (index) => index + 1));
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

final class _RecordingAuthStore implements AuthStore {
  _RecordingAuthStore() : _delegate = InMemoryAuthStore() {
    sessions = _RecordingSessionStore(_delegate.sessions, this);
  }

  final InMemoryAuthStore _delegate;
  @override
  late final _RecordingSessionStore sessions;
  final List<String> rotations = <String>[];
  final List<AuthSessionRecord> issuedSessions = <AuthSessionRecord>[];

  @override
  AuthUserStore get users => _delegate.users;

  @override
  AuthCredentialStore get credentials => _delegate.credentials;

  @override
  AuthAccountStore get accounts => _delegate.accounts;

  @override
  AuthOAuthChallengeStore get oauthChallenges => _delegate.oauthChallenges;

  @override
  AuthPasswordResetTokenStore get passwordResetTokens =>
      _delegate.passwordResetTokens;

  @override
  AuthJwtVersionStore get jwtVersions => _delegate.jwtVersions;

  @override
  AuthVerificationTokenStore get verificationTokens =>
      _delegate.verificationTokens;
}

final class _RecordingSessionStore implements AuthSessionStore {
  _RecordingSessionStore(this._delegate, this._owner);

  final AuthSessionStore _delegate;
  final _RecordingAuthStore _owner;

  @override
  Future<AuthSessionRecord?> find(String tokenHash) async =>
      await _delegate.find(tokenHash);

  @override
  Future<AuthSessionRecord> create(AuthSessionRecord session) async {
    final created = await _delegate.create(session);
    _owner.issuedSessions.add(created);
    return created;
  }

  @override
  Future<AuthSessionRecord?> touch(
    String tokenHash,
    DateTime lastUsedAt,
  ) async => await _delegate.touch(tokenHash, lastUsedAt);

  @override
  Future<List<AuthSessionRecord>> listForUser(String userId) async =>
      await _delegate.listForUser(userId);

  @override
  Future<AuthSessionRecord?> revoke(
    String tokenHash, {
    DateTime? revokedAt,
  }) async => await _delegate.revoke(tokenHash, revokedAt: revokedAt);

  @override
  Future<AuthSessionRecord?> revokeById(
    String userId,
    String sessionId, {
    DateTime? revokedAt,
  }) async =>
      await _delegate.revokeById(userId, sessionId, revokedAt: revokedAt);

  @override
  Future<int> revokeAllForUser(String userId, {DateTime? revokedAt}) async =>
      await _delegate.revokeAllForUser(userId, revokedAt: revokedAt);

  @override
  Future<int> revokeAllForUserExcept(
    String userId,
    String currentSessionId, {
    DateTime? revokedAt,
  }) async => await _delegate.revokeAllForUserExcept(
    userId,
    currentSessionId,
    revokedAt: revokedAt,
  );

  @override
  Future<AuthSessionRecord?> rotate({
    required String previousTokenHash,
    required AuthSessionRecord replacement,
  }) async {
    final result = await _delegate.rotate(
      previousTokenHash: previousTokenHash,
      replacement: replacement,
    );
    _owner.rotations.add(
      '$previousTokenHash -> ${replacement.tokenHash} '
      '(matched=${result != null})',
    );
    if (result != null) {
      _owner.issuedSessions.add(result);
    }
    return result;
  }
}

final class _SessionState {
  const _SessionState({required this.authenticated, required this.hasCookie});

  final bool authenticated;
  final bool hasCookie;

  _SessionState copyWith({bool? authenticated, bool? hasCookie}) {
    return _SessionState(
      authenticated: authenticated ?? this.authenticated,
      hasCookie: hasCookie ?? this.hasCookie,
    );
  }
}

final class _AuthStatefulSut {
  _AuthStatefulSut({
    required this.manager,
    required this.client,
    required this.store,
  });

  final AuthManager manager;
  final TestClient client;
  final _RecordingAuthStore store;
  String? sessionCookie;

  static Future<_AuthStatefulSut> create() async {
    final store = _RecordingAuthStore();
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.durable,
        providers: [
          CredentialsProvider(
            authorize: (_, _, credentials) async {
              if (credentials.username == 'user' &&
                  credentials.password == 'pass') {
                return AuthUser(id: 'user-1', email: 'user@example.com');
              }
              return null;
            },
          ),
        ],
        sessionStrategy: AuthSessionStrategy.session,
        enforceCsrf: false,
      ),
    );
    final engine = Engine(
      config: EngineConfig(
        security: const EngineSecurityFeatures(csrfProtection: false),
      ),
      providers: [
        ...Engine.defaultProviders,
        RoutedSessionsProvider(_sessionConfig()),
      ],
    );
    engine.addGlobalMiddleware(sessionMiddleware());
    engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    return _AuthStatefulSut(
      manager: manager,
      client: TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      ),
      store: store,
    );
  }

  Future<void> close() => client.close();

  Future<void> ensureCookie() async {
    if (sessionCookie != null) return;
    final response = await client.get('/auth/csrf');
    final cookie = response.cookie('test_session');
    expect(cookie, isNotNull);
    sessionCookie = cookie!.value;
  }

  Map<String, List<String>> get cookieHeaders => {
    HttpHeaders.cookieHeader: ['test_session=${sessionCookie!}'],
  };

  Future<dynamic> sessionResponse() {
    final headers = sessionCookie == null ? null : cookieHeaders;
    return client.get('/auth/session', headers: headers);
  }
}

final class _LoginCommand extends Command<_SessionState, _AuthStatefulSut> {
  _LoginCommand(this.valid);

  final bool valid;
  String? _nextCookie;
  String? _previousCookie;

  @override
  Future<void> run(_AuthStatefulSut sut) async {
    await sut.ensureCookie();
    _previousCookie = sut.sessionCookie;
    final response = await sut.client.postJson('/auth/signin/credentials', {
      'username': 'user',
      'password': valid ? 'pass' : 'wrong-password',
    }, headers: sut.cookieHeaders);

    expect(response.statusCode, valid ? 200 : HttpStatus.unauthorized);
    if (!valid) return;

    final cookie = response.cookie('test_session');
    expect(cookie, isNotNull);
    _nextCookie = cookie!.value;

    if (_previousCookie != null && _previousCookie != _nextCookie) {
      final replay = await sut.client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: ['test_session=$_previousCookie'],
        },
      );
      expect(replay.statusCode, lessThan(500));
      expect(
        replay.body,
        isNot(contains('user-1')),
        reason:
            'rotated session replayed: '
            '${hashOpaqueToken(_previousCookie!)} -> ${hashOpaqueToken(_nextCookie!)}; '
            'rotations=${sut.store.rotations}',
      );
    }
    sut.sessionCookie = _nextCookie;
  }

  @override
  _SessionState update(_SessionState model) {
    if (!valid) return model.copyWith(hasCookie: true);
    return _SessionState(authenticated: true, hasCookie: true);
  }

  @override
  Future<void> postcondition(_SessionState model, _AuthStatefulSut sut) async {
    final response = await sut.sessionResponse();
    expect(response.statusCode, lessThan(500));
    if (model.authenticated) {
      expect(response.body, contains('user-1'));
    }
  }

  @override
  String toString() => valid ? 'login(valid)' : 'login(invalid)';
}

final class _LogoutCommand extends Command<_SessionState, _AuthStatefulSut> {
  String? _revokedCookie;

  @override
  Future<void> run(_AuthStatefulSut sut) async {
    await sut.ensureCookie();
    _revokedCookie = sut.sessionCookie;
    final response = await sut.client.post(
      '/auth/signout',
      '',
      headers: sut.cookieHeaders,
    );
    expect(response.statusCode, HttpStatus.ok);

    final replay = await sut.client.get(
      '/auth/session',
      headers: {
        HttpHeaders.cookieHeader: ['test_session=$_revokedCookie'],
      },
    );
    expect(replay.statusCode, lessThan(500));
    expect(
      replay.body,
      isNot(contains('user-1')),
      reason: 'revoked session replayed: ${hashOpaqueToken(_revokedCookie!)}',
    );
    sut.sessionCookie = null;
  }

  @override
  _SessionState update(_SessionState model) =>
      _SessionState(authenticated: false, hasCookie: false);

  @override
  Future<void> postcondition(_SessionState model, _AuthStatefulSut sut) async {
    final response = await sut.sessionResponse();
    expect(response.statusCode, lessThan(500));
    expect(response.body, isNot(contains('user-1')));
  }

  @override
  String toString() => 'logout()';
}

final class _RevokeCommand extends Command<_SessionState, _AuthStatefulSut> {
  @override
  Future<void> run(_AuthStatefulSut sut) async {
    await sut.ensureCookie();
    final issuedSessions = sut.store.issuedSessions;
    if (issuedSessions.isNotEmpty) {
      await sut.manager.store.sessions.revoke(issuedSessions.last.tokenHash);
    }

    final replay = await sut.sessionResponse();
    expect(replay.statusCode, lessThan(500));
    expect(replay.body, isNot(contains('user-1')));
  }

  @override
  _SessionState update(_SessionState model) =>
      _SessionState(authenticated: false, hasCookie: true);

  @override
  Future<void> postcondition(_SessionState model, _AuthStatefulSut sut) async {
    final response = await sut.sessionResponse();
    expect(response.statusCode, lessThan(500));
    expect(response.body, isNot(contains('user-1')));
  }

  @override
  String toString() => 'revoke-current()';
}

final class _CheckSessionCommand
    extends Command<_SessionState, _AuthStatefulSut> {
  bool _authenticated = false;

  @override
  Future<void> run(_AuthStatefulSut sut) async {
    final response = await sut.sessionResponse();
    expect(response.statusCode, lessThan(500));
    _authenticated = response.body.contains('user-1');
  }

  @override
  _SessionState update(_SessionState model) => model;

  @override
  Future<void> postcondition(_SessionState model, _AuthStatefulSut sut) async {
    expect(_authenticated, equals(model.authenticated));
  }

  @override
  String toString() => 'check-session()';
}

void main() {
  test(
    'stateful auth commands preserve session and replay invariants',
    () async {
      final builder =
          StatefulPropertyBuilder.create<_SessionState, _AuthStatefulSut>(
                initialModel: () =>
                    const _SessionState(authenticated: false, hasCookie: false),
                setupSut: _AuthStatefulSut.create,
                teardownSut: (sut) => sut.close(),
              )
              .withCommands(Gen.constant(0).map((_) => _LoginCommand(true)))
              .withCommands(Gen.constant(0).map((_) => _LoginCommand(false)))
              .withCommands(Gen.constant(0).map((_) => _LogoutCommand()))
              .withCommands(Gen.constant(0).map((_) => _RevokeCommand()))
              .withCommands(Gen.constant(0).map((_) => _CheckSessionCommand()))
              .withConfig(
                StatefulPropertyConfig(
                  numTests: 20,
                  maxCommandSequenceLength: 12,
                  random: Random(20260819),
                ),
              );

      final result = await builder.run();
      expect(
        result.success,
        isTrue,
        reason:
            'Stateful property failed: ${result.error}; '
            'input=${result.failingInput}',
      );
    },
  );

  test(
    'property: concurrent session refreshes preserve authentication',
    () async {
      final runner = PropertyTestRunner<int>(Gen.integer(min: 2, max: 16), (
        requestCount,
      ) async {
        final sut = await _AuthStatefulSut.create();
        try {
          await _LoginCommand(true).run(sut);
          final responses = await Future.wait(
            List.generate(requestCount, (_) => sut.sessionResponse()),
          );
          for (final response in responses) {
            expect(response.statusCode, lessThan(500));
            expect(response.body, contains('user-1'));
          }
        } finally {
          await sut.close();
        }
      }, PropertyConfig(numTests: 12, seed: 20260820));

      final result = await runner.run();
      expect(
        result.success,
        isTrue,
        reason:
            'Concurrent session property failed: ${result.error}; '
            'input=${result.failingInput}',
      );
    },
  );
}
