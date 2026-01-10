import 'package:routed/routed.dart';
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

final Set<String> _baselineAbilities = Set<String>.from(
  GateRegistry.instance.abilities,
);

void main() {
  tearDown(() {
    final registry = GateRegistry.instance;
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
        throwsA(isA<GateRegistrationException>()),
      );
    });

    test('register rejects empty ability names', () {
      expect(
        () => Haigate.register(' ', (_) => true),
        throwsA(isA<GateRegistrationException>()),
      );
    });

    test('authorize throws GateViolation when denied', () async {
      Haigate.register('deny', (_) => false);
      addTearDown(() => Haigate.unregister('deny'));

      GateViolation? capturedViolation;

      final engine = testEngine();
      engine.get('/authorize', (ctx) async {
        try {
          await Haigate.authorize('deny', ctx: ctx);
        } catch (error) {
          if (error is GateViolation) {
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
      expect(capturedViolation, isA<GateViolation>());
      expect(capturedViolation?.ability, equals('deny'));
    });

    test('observer receives evaluation payloads', () async {
      Haigate.register('observer-demo', (_) => true);
      addTearDown(() => Haigate.unregister('observer-demo'));

      final evaluations = <GateEvaluation>[];
      void observer(GateEvaluation evaluation) {
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
        configItems: {
          'http': {
            'features': {
              'auth': {'enabled': true},
            },
          },
          'auth': {
            'features': {
              'haigate': {'enabled': true},
            },
            'gates': {
              'defaults': {
                'denied_status': HttpStatus.unauthorized,
                'denied_message': 'Gate denied',
              },
              'abilities': {
                'publish-post': {
                  'roles': ['publisher'],
                },
              },
            },
          },
        },
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
