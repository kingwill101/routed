import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

class _Project {
  _Project({required this.ownerId});

  final String ownerId;
}

class _ProjectPolicy extends Policy<_Project> {
  @override
  Future<bool> canCreate(AuthPrincipal? principal) async => principal != null;

  @override
  Future<bool> canDelete(AuthPrincipal? principal, _Project resource) async {
    return principal?.id == resource.ownerId;
  }

  @override
  Future<bool> canUpdate(AuthPrincipal? principal, _Project resource) async {
    return principal?.id == resource.ownerId;
  }

  @override
  Future<bool> canView(AuthPrincipal? principal, _Project resource) async =>
      true;
}

void main() {
  test('registerRbacAbilities and rbacGate evaluate role mappings', () async {
    final registry = AuthGateRegistry<String>();
    final registered = registerRbacAbilities<String>(registry, {
      'admin.only': RbacAbility.role('admin'),
    });

    expect(registered, contains('admin.only'));
    final callback = registry.resolve('admin.only');
    expect(callback, isNotNull);

    final allowed = await callback!(
      AuthGateEvaluationContext<String>(
        context: 'ctx',
        principal: AuthPrincipal(id: '1', roles: const ['admin']),
      ),
    );
    expect(allowed, isTrue);
  });

  test(
    'registerRbacAbilitiesSafely keeps unmanaged existing entries',
    () async {
      final registry = AuthGateRegistry<String>();
      var originalCalled = false;
      registry.register('rbac.keep', (_) {
        originalCalled = true;
        return false;
      });

      registerRbacAbilitiesSafely<String>(registry, {
        'rbac.keep': RbacAbility.role('admin'),
      });

      final callback = registry.resolve('rbac.keep');
      expect(callback, isNotNull);
      await callback!(
        AuthGateEvaluationContext<String>(
          context: 'ctx',
          principal: AuthPrincipal(id: '1', roles: const ['admin']),
        ),
      );
      expect(originalCalled, isTrue);
    },
  );

  test('registerPolicyBindings registers typed policy abilities', () async {
    final registry = AuthGateRegistry<String>();
    final registered = registerPolicyBindings<String>(registry, [
      PolicyBinding<_Project>(
        policy: _ProjectPolicy(),
        abilityPrefix: 'project',
        actions: {PolicyAction.update},
      ),
    ]);

    expect(registered, contains('project.update'));
    final callback = registry.resolve('project.update');
    expect(callback, isNotNull);

    final allowed = await callback!(
      AuthGateEvaluationContext<String>(
        context: 'ctx',
        principal: AuthPrincipal(id: 'owner-1', roles: const ['user']),
        payload: _Project(ownerId: 'owner-1'),
      ),
    );
    expect(allowed, isTrue);
  });

  test(
    'registerPolicyBindingsSafely keeps unmanaged existing entries',
    () async {
      final registry = AuthGateRegistry<String>();
      var originalCalled = false;
      registry.register('project.update', (_) {
        originalCalled = true;
        return false;
      });

      registerPolicyBindingsSafely<String>(registry, [
        PolicyBinding<_Project>(
          policy: _ProjectPolicy(),
          abilityPrefix: 'project',
          actions: {PolicyAction.update},
        ),
      ]);

      final callback = registry.resolve('project.update');
      expect(callback, isNotNull);
      await callback!(
        AuthGateEvaluationContext<String>(
          context: 'ctx',
          principal: AuthPrincipal(id: 'owner-1', roles: const ['user']),
          payload: _Project(ownerId: 'owner-1'),
        ),
      );
      expect(originalCalled, isTrue);
    },
  );

  test(
    'registerPolicyBindingsSafely replaces previously managed entries',
    () async {
      final registry = AuthGateRegistry<String>();
      registry.register('project.update', (_) => false);

      registerPolicyBindingsSafely<String>(
        registry,
        [
          PolicyBinding<_Project>(
            policy: _ProjectPolicy(),
            abilityPrefix: 'project',
            actions: {PolicyAction.update},
          ),
        ],
        managed: const <String>{'project.update'},
      );

      final callback = registry.resolve('project.update');
      expect(callback, isNotNull);
      final allowed = await callback!(
        AuthGateEvaluationContext<String>(
          context: 'ctx',
          principal: AuthPrincipal(id: 'owner-1', roles: const ['user']),
          payload: _Project(ownerId: 'owner-1'),
        ),
      );
      expect(allowed, isTrue);
    },
  );

  test('syncManagedGateAbilities unregisters stale managed abilities', () {
    final registry = AuthGateRegistry<String>();
    registry.register('ability.keep', (_) => true);
    registry.register('ability.remove', (_) => true);

    final managed = <String>{'ability.keep', 'ability.remove'};
    syncManagedGateAbilities<String>(
      registry,
      managed: managed,
      nextManaged: const <String>{'ability.keep'},
    );

    expect(registry.resolve('ability.keep'), isNotNull);
    expect(registry.resolve('ability.remove'), isNull);
    expect(managed, equals(const <String>{'ability.keep'}));
  });

  test('syncManagedGateAbilities can clear all managed abilities', () {
    final registry = AuthGateRegistry<String>();
    registry.register('ability.one', (_) => true);

    final managed = <String>{'ability.one'};
    syncManagedGateAbilities<String>(
      registry,
      managed: managed,
      nextManaged: const <String>{},
    );

    expect(registry.resolve('ability.one'), isNull);
    expect(managed, isEmpty);
  });

  test(
    'syncManagedGateDefinitions preserves unmanaged abilities and synchronizes managed ones',
    () async {
      final registry = AuthGateRegistry<String>();
      registry.register('ability.keep', (_) => false);
      registry.register('ability.remove', (_) => true);

      final managed = <String>{'ability.remove'};
      final registered = syncManagedGateDefinitions<String, bool>(
        registry,
        const <String, bool>{
          'ability.keep': true,
          'ability.add': true,
          ' ': true,
        },
        buildGate: (_, allow) =>
            (_) => allow,
        managed: managed,
      );

      expect(registered, equals(const <String>{'ability.add'}));
      expect(registry.resolve('ability.remove'), isNull);
      expect(managed, equals(const <String>{'ability.add'}));

      final kept = await registry.resolve('ability.keep')!(
        AuthGateEvaluationContext<String>(context: 'ctx', principal: null),
      );
      final added = await registry.resolve('ability.add')!(
        AuthGateEvaluationContext<String>(context: 'ctx', principal: null),
      );

      expect(kept, isFalse);
      expect(added, isTrue);
    },
  );

  test('syncManagedRbacAbilities registers and clears managed RBAC gates', () {
    final registry = AuthGateRegistry<String>();
    final managed = <String>{};

    final registered = syncManagedRbacAbilities<String>(
      registry,
      const <String, RbacAbility>{
        'admin.only': RbacAbility(roles: ['admin']),
      },
      managed: managed,
    );

    expect(registered, equals(const <String>{'admin.only'}));
    expect(registry.resolve('admin.only'), isNotNull);
    expect(managed, equals(const <String>{'admin.only'}));

    final cleared = syncManagedRbacAbilities<String>(
      registry,
      const <String, RbacAbility>{},
      managed: managed,
    );

    expect(cleared, isEmpty);
    expect(registry.resolve('admin.only'), isNull);
    expect(managed, isEmpty);
  });

  test(
    'syncManagedPolicyBindings registers and clears managed policy gates',
    () {
      final registry = AuthGateRegistry<String>();
      final managed = <String>{};

      final registered = syncManagedPolicyBindings<String>(registry, [
        PolicyBinding<_Project>(
          policy: _ProjectPolicy(),
          abilityPrefix: 'project',
          actions: {PolicyAction.update},
        ),
      ], managed: managed);

      expect(registered, equals(const <String>{'project.update'}));
      expect(registry.resolve('project.update'), isNotNull);
      expect(managed, equals(const <String>{'project.update'}));

      final cleared = syncManagedPolicyBindings<String>(
        registry,
        const <PolicyBinding>[],
        managed: managed,
      );

      expect(cleared, isEmpty);
      expect(registry.resolve('project.update'), isNull);
      expect(managed, isEmpty);
    },
  );
}
