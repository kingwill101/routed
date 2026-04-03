import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

class _Document {}

class _DocumentPolicy extends Policy<_Document> {
  @override
  Future<bool> canCreate(AuthPrincipal? principal) async => principal != null;

  @override
  Future<bool> canDelete(AuthPrincipal? principal, _Document resource) async {
    return principal?.hasRole('admin') ?? false;
  }

  @override
  Future<bool> canUpdate(AuthPrincipal? principal, _Document resource) async {
    return principal?.hasRole('editor') ?? false;
  }

  @override
  Future<bool> canView(AuthPrincipal? principal, _Document resource) async {
    return true;
  }
}

void main() {
  group('RbacAbility', () {
    test('evaluates any/all/guest rules', () {
      final admin = AuthPrincipal(id: '1', roles: const ['admin']);
      final editor = AuthPrincipal(id: '2', roles: const ['editor']);
      final both = AuthPrincipal(id: '3', roles: const ['admin', 'editor']);

      final any = RbacAbility.any(const ['admin', 'editor']);
      final all = RbacAbility.all(const ['admin', 'editor']);
      final guest = RbacAbility.role('guest', allowGuest: true);

      expect(any.evaluate(admin), isTrue);
      expect(any.evaluate(editor), isTrue);
      expect(all.evaluate(both), isTrue);
      expect(all.evaluate(admin), isFalse);
      expect(guest.evaluate(null), isTrue);
    });
  });

  group('Options', () {
    test('RbacOptions and PolicyOptions report emptiness', () {
      const emptyRbac = RbacOptions();
      const emptyPolicy = PolicyOptions();

      expect(emptyRbac.isEmpty, isTrue);
      expect(emptyPolicy.isEmpty, isTrue);
    });

    test('PolicyBinding preserves configured actions', () {
      final binding = PolicyBinding<_Document>(
        policy: _DocumentPolicy(),
        abilityPrefix: 'document',
        actions: const {PolicyAction.view, PolicyAction.update},
      );

      expect(binding.abilityPrefix, 'document');
      expect(
        binding.actions,
        containsAll(const [PolicyAction.view, PolicyAction.update]),
      );
      expect(binding.actions, isNot(contains(PolicyAction.delete)));
    });
  });
}
