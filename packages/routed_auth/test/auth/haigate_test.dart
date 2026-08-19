import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

final Set<String> _baselineAbilities = Set<String>.from(gateRegistry.abilities);

void main() {
  tearDown(() {
    final registry = gateRegistry;
    for (final ability in Set<String>.from(registry.abilities)) {
      if (!_baselineAbilities.contains(ability)) {
        Haigate.unregister(ability);
      }
    }
  });

  group('Haigate registry', () {
    test('register rejects duplicate abilities', () {
      Haigate.register('demo', (_) => true);
      addTearDown(() => Haigate.unregister('demo'));

      expect(
        () => Haigate.register('demo', (_) => true),
        throwsA(isA<AuthGateRegistrationException>()),
      );
    });

    test('register rejects empty ability names', () {
      expect(
        () => Haigate.register(' ', (_) => true),
        throwsA(isA<AuthGateRegistrationException>()),
      );
    });

    test('authorize throws GateViolation when denied', () async {
      Haigate.register('deny', (_) => false);
      addTearDown(() => Haigate.unregister('deny'));

      AuthGateViolation<EngineContext>? capturedViolation;

      final engine = testEngine();
      engine.get('/authorize', (ctx) async {
        try {
          await Haigate.authorize('deny', ctx: ctx);
        } catch (error) {
          if (error is AuthGateViolation<EngineContext>) {
            capturedViolation = error;
            return ctx.string('denied');
          }
          rethrow;
        }
        return ctx.string('unexpected');
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final res = await client.get('/authorize');
      res.assertStatus(200);
      expect(res.body, equals('denied'));
      expect(capturedViolation, isA<AuthGateViolation<EngineContext>>());
      expect(capturedViolation?.ability, equals('deny'));
    });

    test('observer receives evaluation payloads', () async {
      Haigate.register('observer-demo', (_) => true);
      addTearDown(() => Haigate.unregister('observer-demo'));

      final evaluations = <AuthGateEvaluation<EngineContext>>[];
      void observer(AuthGateEvaluation<EngineContext> evaluation) {
        evaluations.add(evaluation);
      }

      Haigate.addObserver(observer);
      addTearDown(() => Haigate.removeObserver(observer));

      bool? allowedResult;
      final engine = testEngine();
      engine.get('/check', (ctx) async {
        allowedResult = await Haigate.can('observer-demo', ctx: ctx);
        return ctx.string('ok');
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final res = await client.get('/check');
      res.assertStatus(200);
      expect(allowedResult, isTrue);
      expect(evaluations, hasLength(1));
      expect(evaluations.first.ability, equals('observer-demo'));
      expect(evaluations.first.allowed, isTrue);
    });
  });

  group('Haigate evaluation helpers', () {
    test('any and all evaluate multiple abilities', () async {
      Haigate.register('any.allow', (_) => true);
      Haigate.register('all.deny', (_) => false);
      addTearDown(() {
        Haigate.unregister('any.allow');
        Haigate.unregister('all.deny');
      });

      bool? anyResult;
      bool? allResult;
      final engine = testEngine();
      engine.get('/check', (ctx) async {
        anyResult = await Haigate.any(['all.deny', 'any.allow'], ctx: ctx);
        allResult = await Haigate.all(['all.deny', 'any.allow'], ctx: ctx);
        return ctx.string('ok');
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final res = await client.get('/check');
      res.assertStatus(200);
      expect(anyResult, isTrue);
      expect(allResult, isFalse);
    });

    test(
      'organization checks scope active teams and clear stale selections',
      () async {
        final store = InMemoryAuthOrganizationStore();
        final feature = OrganizationFeature<EngineContext>(
          store: store,
          options: const AuthOrganizationOptions(
            teams: AuthOrganizationTeamsOptions(enabled: true),
          ),
        );
        final owner = AuthUser(id: 'owner', email: 'owner@example.com');

        final engine = testEngine(
          providers: [RoutedSessionsProvider(_haigateSessionConfig())],
        );
        engine.addGlobalMiddleware(sessionMiddleware());
        engine.get('/tenant', (ctx) async {
          final first = (await feature.createOrganization(
            context: ctx,
            user: owner,
            name: 'First',
            slug: 'first',
          )).data;
          final second = (await feature.createOrganization(
            context: ctx,
            user: owner,
            name: 'Second',
            slug: 'second',
          )).data;
          final firstTeam = (await store.listTeams(first.id)).single;
          ctx.request.setAttribute(
            authPrincipalAttribute,
            AuthPrincipal(id: owner.id),
          );
          ctx
            ..setSession('__routed.auth.activeOrganizationId', first.id)
            ..setSession('__routed.auth.activeTeamId', firstTeam.id);

          final explicit = await Haigate.organizationContext(
            ctx: ctx,
            feature: feature,
            organizationId: second.id,
          );
          final allowed = await Haigate.canInOrganization(
            ctx: ctx,
            feature: feature,
            organizationId: second.id,
            resource: 'organization',
            action: 'read',
          );

          ctx
            ..setSession('__routed.auth.activeOrganizationId', second.id)
            ..setSession('__routed.auth.activeTeamId', 'stale-team');
          final recovered = await Haigate.organizationContext(
            ctx: ctx,
            feature: feature,
          );
          return ctx.json({
            'explicitOrganizationMatches':
                explicit.organization.id == second.id,
            'explicitTeamId': explicit.team?.id,
            'allowed': allowed,
            'recoveredOrganizationMatches':
                recovered.organization.id == second.id,
            'recoveredTeamId': recovered.team?.id,
            'activeTeamCleared': !ctx.hasSessionKey(
              '__routed.auth.activeTeamId',
            ),
          });
        });

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async {
          await client.close();
          await engine.close();
        });

        final response = await client.get('/tenant');
        response.assertStatus(200);
        expect(response.json(), {
          'explicitOrganizationMatches': true,
          'explicitTeamId': null,
          'allowed': true,
          'recoveredOrganizationMatches': true,
          'recoveredTeamId': null,
          'activeTeamCleared': true,
        });
      },
    );
  });

  group('Haigate middleware', () {
    test('denies when gate callback returns false', () async {
      Haigate.register('edit-post', (_) => false);
      addTearDown(() => Haigate.unregister('edit-post'));

      final engine = testEngine();
      engine.get(
        '/edit',
        (ctx) => ctx.string('ok'),
        middlewares: [
          Haigate.middleware(['edit-post']),
        ],
      );

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final res = await client.get('/edit');
      expect(res.statusCode, equals(HttpStatus.forbidden));
      expect(res.body, contains('edit-post'));
    });

    test('supports custom denied responses and payload providers', () async {
      Haigate.register('with-payload', (ctx) {
        return ctx.payload == 42;
      });
      Haigate.register('custom-deny', (_) => false);
      addTearDown(() {
        Haigate.unregister('with-payload');
        Haigate.unregister('custom-deny');
      });

      final engine = testEngine();
      engine.get(
        '/payload',
        (ctx) => ctx.string('ok'),
        middlewares: [
          Haigate.middleware(['with-payload'], payloadProvider: (_, _) => 42),
        ],
      );
      engine.get(
        '/custom',
        (ctx) => ctx.string('ok'),
        middlewares: [
          Haigate.middleware(
            ['custom-deny'],
            onDenied: (violation, ctx) async {
              return ctx.json({'error': violation.ability}, statusCode: 418);
            },
          ),
        ],
      );

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final payload = await client.get('/payload');
      payload.assertStatus(200);

      final denied = await client.get('/custom');
      expect(denied.statusCode, equals(418));
      expect(denied.json()['error'], equals('custom-deny'));
    });

    test('allows when principal satisfies role-based gate', () async {
      Haigate.register('manage-posts', (ctx) {
        final principal = ctx.principal;
        if (principal == null) {
          return false;
        }
        return principal.hasRole('editor');
      });
      addTearDown(() => Haigate.unregister('manage-posts'));

      final engine = testEngine();
      engine.addGlobalMiddleware((ctx, next) {
        final roleHeader = ctx.request.headers.value('x-user-roles');
        if (roleHeader != null) {
          ctx.request.setAttribute(
            authPrincipalAttribute,
            AuthPrincipal(
              id: 'user',
              roles: roleHeader.split(',').map((r) => r.trim()).toList(),
            ),
          );
        }
        return next();
      });

      engine.get(
        '/manage',
        (ctx) => ctx.string('ok'),
        middlewares: [
          Haigate.middleware(['manage-posts']),
        ],
      );

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final unauthorized = await client.get('/manage');
      expect(unauthorized.statusCode, equals(HttpStatus.forbidden));

      final authorized = await client.get(
        '/manage',
        headers: {
          'x-user-roles': ['editor'],
        },
      );
      authorized.assertStatus(200);
      expect(authorized.body, equals('ok'));
    });
  });

  group('Haigate provider integration', () {
    test('registers config-defined gates and middleware', () async {
      final engine = testEngine(
        includeDefaultProviders: true,
        providers: [
          AuthServiceProvider(
            configuration: AuthConfig.defaults().copyWith(
              haigate: HaigateConfig(
                enabled: true,
                defaults: const GateDefaults(
                  statusCode: HttpStatus.unauthorized,
                  message: 'Gate denied',
                ),
                abilities: const <String, GateDefinition>{
                  'publish-post': GateDefinition.roles(roles: ['publisher']),
                },
              ),
            ),
          ),
        ],
      );

      engine.addGlobalMiddleware((ctx, next) {
        final roleHeader = ctx.request.headers.value('x-user-roles');
        if (roleHeader != null) {
          ctx.request.setAttribute(
            authPrincipalAttribute,
            AuthPrincipal(
              id: 'viewer',
              roles: roleHeader.split(',').map((r) => r.trim()).toList(),
            ),
          );
        }
        return next();
      });

      engine.get(
        '/publish',
        (ctx) => ctx.string('ok'),
        middlewares: [MiddlewareRef.of('routed.auth.gate.publish-post')],
      );

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
        Haigate.unregister('publish-post');
      });

      final denied = await client.get('/publish');
      expect(denied.statusCode, equals(HttpStatus.unauthorized));
      expect(denied.body, equals('Gate denied'));

      final allowed = await client.get(
        '/publish',
        headers: {
          'x-user-roles': ['publisher'],
        },
      );
      allowed.assertStatus(200);
      expect(allowed.body, equals('ok'));
    });
  });
}

SessionConfig _haigateSessionConfig() {
  final key = base64.encode(List<int>.generate(32, (index) => index + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'haigate_test_session',
    options: SessionOptions(secure: false),
  );
}
