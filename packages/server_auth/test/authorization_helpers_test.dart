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
}
