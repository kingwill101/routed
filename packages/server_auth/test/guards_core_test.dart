import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('GuardResult allow/deny constructors set expected values', () {
    const allowed = GuardResult<String>.allow();
    const denied = GuardResult<String>.deny('blocked');

    expect(allowed.allowed, isTrue);
    expect(allowed.response, isNull);
    expect(denied.allowed, isFalse);
    expect(denied.response, equals('blocked'));
  });

  test('AuthGuard typedef supports async handlers', () async {
    Future<GuardResult<String>> handler(String ctx) async {
      if (ctx == 'ok') return const GuardResult<String>.allow();
      return const GuardResult<String>.deny('unauthorized');
    }

    final AuthGuard<String, String> typed = handler;

    final denied = await typed('nope');
    final allowed = await typed('ok');

    expect(denied.allowed, isFalse);
    expect(denied.response, equals('unauthorized'));
    expect(allowed.allowed, isTrue);
  });

  test('AuthGuardRegistry registers and resolves guards', () async {
    final registry = AuthGuardRegistry<String, String>();
    registry.register(' admin ', (ctx) async {
      if (ctx == 'ok') return const GuardResult<String>.allow();
      return const GuardResult<String>.deny('blocked');
    });

    final handler = registry.resolve('admin');
    expect(handler, isNotNull);

    final denied = await handler!('no');
    final allowed = await handler('ok');
    expect(denied.allowed, isFalse);
    expect(allowed.allowed, isTrue);
    expect(registry.names, contains('admin'));
  });

  test('AuthGuardRegistry supports explicit duplicate override', () async {
    final registry = AuthGuardRegistry<String, String>();
    registry.register('auth', (_) => const GuardResult<String>.deny('x'));
    registry.register(
      'auth',
      (_) => const GuardResult<String>.allow(),
      overrideExisting: true,
    );

    final result = await registry.resolve('auth')!('ignored');
    expect(result.allowed, isTrue);
  });

  test('AuthGuardService returns first denied response', () async {
    final service = AuthGuardService<String, String>();
    service.register('a', (_) => const GuardResult<String>.allow());
    service.register('b', (_) => const GuardResult<String>.deny('blocked'));

    final denied = await service.firstDenied(['a', 'b'], 'ctx');
    expect(denied, equals('blocked'));
  });

  test('AuthGuardService can build fallback denied response', () async {
    final service = AuthGuardService<String, String>();
    service.register('auth', (_) => const GuardResult<String>.deny());

    final denied = await service.firstDenied(
      ['auth'],
      'ctx',
      onDenied: (_, name) => 'denied by $name',
    );

    expect(denied, equals('denied by auth'));
  });

  test('AuthGuardService returns null when all guards pass', () async {
    final service = AuthGuardService<String, String>();
    service.register('auth', (_) => const GuardResult<String>.allow());

    final denied = await service.firstDenied(['auth'], 'ctx');
    expect(denied, isNull);
  });

  test(
    'requireAuthenticatedGuard allows with principal and denies otherwise',
    () async {
      final guard = requireAuthenticatedGuard<String, String>(
        principalResolver: (ctx) =>
            ctx == 'ok' ? AuthPrincipal(id: 'u1') : null,
        onDenied: (_) => 'auth required',
      );

      final denied = await guard('nope');
      final allowed = await guard('ok');

      expect(denied.allowed, isFalse);
      expect(denied.response, equals('auth required'));
      expect(allowed.allowed, isTrue);
      expect(allowed.response, isNull);
    },
  );

  test('requireRolesGuard validates roles with any/all semantics', () async {
    final anyGuard = requireRolesGuard<_Ctx, String>(
      ['admin', 'support'],
      principalResolver: (ctx) => ctx.principal,
      any: true,
      onUnauthenticated: (_) => 'unauthorized',
      onForbidden: (_) => 'forbidden',
    );

    final allGuard = requireRolesGuard<_Ctx, String>(
      ['admin', 'support'],
      principalResolver: (ctx) => ctx.principal,
      any: false,
      onUnauthenticated: (_) => 'unauthorized',
      onForbidden: (_) => 'forbidden',
    );

    final unauthenticated = await anyGuard(const _Ctx());
    final anyAllowed = await anyGuard(
      _Ctx(
        principal: AuthPrincipal(id: 'u1', roles: ['support']),
      ),
    );
    final allDenied = await allGuard(
      _Ctx(
        principal: AuthPrincipal(id: 'u1', roles: ['support']),
      ),
    );
    final allAllowed = await allGuard(
      _Ctx(
        principal: AuthPrincipal(id: 'u1', roles: ['support', 'admin']),
      ),
    );

    expect(unauthenticated.allowed, isFalse);
    expect(unauthenticated.response, equals('unauthorized'));
    expect(anyAllowed.allowed, isTrue);
    expect(allDenied.allowed, isFalse);
    expect(allDenied.response, equals('forbidden'));
    expect(allAllowed.allowed, isTrue);
  });

  test(
    'requireRolesGuard allows authenticated principal when roles are empty',
    () async {
      final guard = requireRolesGuard<_Ctx, String>(
        const <String>[],
        principalResolver: (ctx) => ctx.principal,
        onUnauthenticated: (_) => 'unauthorized',
      );

      final denied = await guard(const _Ctx());
      final allowed = await guard(
        _Ctx(
          principal: AuthPrincipal(id: 'u1', roles: ['member']),
        ),
      );

      expect(denied.allowed, isFalse);
      expect(denied.response, equals('unauthorized'));
      expect(allowed.allowed, isTrue);
    },
  );

  test(
    'syncManagedGuardDefinitions registers built guards and removes stale managed entries',
    () async {
      final registry = AuthGuardRegistry<String, String>();
      registry.register('legacy', (_) => const GuardResult<String>.allow());

      final managed = <String>{'legacy'};
      final registered = syncManagedGuardDefinitions<String, String, String>(
        registry,
        const <String, String>{' auth ': 'allow', 'skip': 'ignore'},
        buildGuard: (_, definition) {
          if (definition == 'ignore') {
            return null;
          }
          return (_) => const GuardResult<String>.deny('blocked');
        },
        managed: managed,
      );

      expect(registered, equals(const <String>{'auth'}));
      expect(registry.resolve('auth'), isNotNull);
      expect(registry.resolve('legacy'), isNull);
      expect(managed, equals(const <String>{'auth'}));

      final result = await registry.resolve('auth')!('ctx');
      expect(result.allowed, isFalse);
      expect(result.response, equals('blocked'));
    },
  );

  test('syncManagedGuardDefinitions honors preserved guard names', () {
    final registry = AuthGuardRegistry<String, String>();
    registry.register(
      'authenticated',
      (_) => const GuardResult<String>.allow(),
    );

    final managed = <String>{'authenticated'};
    final registered = syncManagedGuardDefinitions<String, String, String>(
      registry,
      const <String, String>{},
      buildGuard: (_, _) =>
          (_) => const GuardResult<String>.allow(),
      managed: managed,
      preserve: const <String>{'authenticated'},
    );

    expect(registered, isEmpty);
    expect(registry.resolve('authenticated'), isNotNull);
    expect(managed, isEmpty);
  });

  test('syncManagedGuards unregisters stale guard registrations', () {
    final registry = AuthGuardRegistry<String, String>();
    registry.register('keep', (_) => const GuardResult<String>.allow());
    registry.register('remove', (_) => const GuardResult<String>.allow());

    final managed = <String>{'keep', 'remove'};
    syncManagedGuards<String, String>(
      registry,
      managed: managed,
      nextManaged: const <String>{'keep'},
    );

    expect(registry.resolve('keep'), isNotNull);
    expect(registry.resolve('remove'), isNull);
    expect(managed, equals(const <String>{'keep'}));
  });

  test('syncManagedGuards preserves protected guard names', () {
    final registry = AuthGuardRegistry<String, String>();
    registry.register(
      'authenticated',
      (_) => const GuardResult<String>.allow(),
    );

    final managed = <String>{'authenticated'};
    syncManagedGuards<String, String>(
      registry,
      managed: managed,
      nextManaged: const <String>{},
      preserve: const <String>{'authenticated'},
    );

    expect(registry.resolve('authenticated'), isNotNull);
    expect(managed, isEmpty);
  });
}

class _Ctx {
  const _Ctx({this.principal});

  final AuthPrincipal? principal;
}
