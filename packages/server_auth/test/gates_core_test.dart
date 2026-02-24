import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthGateRegistrationException exposes message', () {
    final error = AuthGateRegistrationException('duplicate');
    expect(error.message, equals('duplicate'));
    expect(error.toString(), contains('duplicate'));
  });

  test('AuthGateViolation stores ability/context payload', () {
    final violation = AuthGateViolation<String>(
      ability: 'posts.publish',
      context: 'ctx-1',
      message: 'denied',
      payload: {'id': 1},
    );

    expect(violation.ability, equals('posts.publish'));
    expect(violation.context, equals('ctx-1'));
    expect(violation.message, equals('denied'));
    expect(violation.payload, isA<Map<String, Object>>());
  });

  test(
    'AuthGateEvaluationContext and AuthGateEvaluation are constructible',
    () {
      final principal = AuthPrincipal(id: 'u1', roles: const ['admin']);
      final ctx = AuthGateEvaluationContext<String>(
        context: 'context',
        principal: principal,
        payload: 7,
      );
      final eval = AuthGateEvaluation<String>(
        ability: 'posts.publish',
        allowed: true,
        context: ctx.context,
        principal: ctx.principal,
        payload: ctx.payload,
      );

      expect(eval.allowed, isTrue);
      expect(eval.principal?.id, equals('u1'));
      expect(eval.payload, equals(7));
    },
  );

  test('AuthGateRegistry registers and resolves trimmed abilities', () {
    final registry = AuthGateRegistry<String>();
    registry.register(' posts.publish ', (_) => true);

    expect(registry.resolve('posts.publish'), isNotNull);
    expect(registry.abilities, contains('posts.publish'));
  });

  test('AuthGateRegistry rejects duplicate ability by default', () {
    final registry = AuthGateRegistry<String>();
    registry.register('posts.publish', (_) => true);

    expect(
      () => registry.register('posts.publish', (_) => false),
      throwsA(isA<AuthGateRegistrationException>()),
    );
  });

  test('AuthGateRegistry can ignore duplicate registration attempts', () async {
    final registry = AuthGateRegistry<String>();
    registry.register('posts.publish', (_) => false);
    registry.register('posts.publish', (_) => true, overrideExisting: false);

    final callback = registry.resolve('posts.publish');
    expect(callback, isNotNull);

    final allowed = await callback!(
      AuthGateEvaluationContext<String>(context: 'ctx', principal: null),
    );
    expect(allowed, isFalse);
  });

  test('AuthGateService evaluates gates and notifies observers', () async {
    final registry = AuthGateRegistry<String>();
    final service = AuthGateService<String>(registry: registry);
    final evaluations = <AuthGateEvaluation<String>>[];

    service.addObserver(evaluations.add);
    service.register('posts.publish', (_) => true);

    final allowed = await service.can(
      'posts.publish',
      context: 'ctx-1',
      principal: AuthPrincipal(id: 'u1'),
      payload: {'id': 1},
    );

    expect(allowed, isTrue);
    expect(evaluations, hasLength(1));
    expect(evaluations.single.ability, equals('posts.publish'));
    expect(evaluations.single.allowed, isTrue);
    expect(evaluations.single.context, equals('ctx-1'));
  });

  test(
    'AuthGateService principal resolver and authorize work as expected',
    () async {
      final service = AuthGateService<String>(
        principalResolver: (context) =>
            context == 'auth' ? AuthPrincipal(id: 'u1') : null,
      );

      service.register('auth-only', (ctx) => ctx.principal != null);
      service.register('always-deny', (_) => false);

      expect(await service.can('auth-only', context: 'auth'), isTrue);
      expect(await service.can('auth-only', context: 'guest'), isFalse);

      await expectLater(
        service.authorize('always-deny', context: 'ctx'),
        throwsA(isA<AuthGateViolation<String>>()),
      );
    },
  );

  test('AuthGateService any/all evaluate multiple abilities', () async {
    final service = AuthGateService<String>();
    service.register('a', (_) => true);
    service.register('b', (_) => false);

    expect(await service.any(const ['b', 'a'], context: 'ctx'), isTrue);
    expect(await service.all(const ['a', 'b'], context: 'ctx'), isFalse);
  });

  test(
    'AuthGateService firstDenied returns violation payload details',
    () async {
      final service = AuthGateService<String>();
      service.register('a', (_) => true);
      service.register('b', (_) => false);

      final denied = await service.firstDenied(
        const ['a', 'b'],
        context: 'ctx',
        payloadResolver: (context, ability) => '$context:$ability',
        message: 'blocked',
      );

      expect(denied, isNotNull);
      expect(denied!.ability, equals('b'));
      expect(denied.context, equals('ctx'));
      expect(denied.message, equals('blocked'));
      expect(denied.payload, equals('ctx:b'));
    },
  );
}
