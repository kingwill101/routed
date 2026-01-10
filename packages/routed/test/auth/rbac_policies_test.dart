import 'package:routed/auth.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/request.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/mock/request.dart';
import 'package:test/test.dart';

class Project {
  Project({required this.id, required this.ownerId});

  final String id;
  final String ownerId;
}

class ProjectPolicy extends Policy<Project> {
  @override
  Future<bool> canCreate(AuthPrincipal? principal) async => principal != null;

  @override
  Future<bool> canDelete(AuthPrincipal? principal, Project resource) async {
    return principal != null && principal.id == resource.ownerId;
  }

  @override
  Future<bool> canUpdate(AuthPrincipal? principal, Project resource) async {
    return principal != null && principal.id == resource.ownerId;
  }

  @override
  Future<bool> canView(AuthPrincipal? principal, Project resource) async =>
      true;
}

EngineContext _context() {
  final request = setupRequest('GET', '/rbac');
  final response = Response(request.response);
  final routedRequest = Request(request, {}, EngineConfig());
  return EngineContext(request: routedRequest, response: response);
}

AuthPrincipal _principal(String id, List<String> roles) {
  return AuthPrincipal(id: id, roles: roles, attributes: const {});
}

void main() {
  group('RBAC', () {
    test('evaluates role requirements', () {
      final abilityAny = RbacAbility.any(['admin', 'editor']);
      final abilityAll = RbacAbility.all(['admin', 'editor']);
      final abilityGuest = RbacAbility.role('guest', allowGuest: true);

      expect(abilityAny.evaluate(_principal('1', ['editor'])), isTrue);
      expect(abilityAny.evaluate(_principal('1', ['viewer'])), isFalse);
      expect(abilityAll.evaluate(_principal('1', ['admin', 'editor'])), isTrue);
      expect(abilityAll.evaluate(_principal('1', ['admin'])), isFalse);
      expect(abilityGuest.evaluate(null), isTrue);
    });

    test('does not override existing gates', () {
      final registry = GateRegistry.instance;
      const ability = 'rbac.keep';
      var originalCalled = false;
      registry.register(ability, (_) {
        originalCalled = true;
        return true;
      });

      addTearDown(() => registry.unregister(ability));

      registerRbacAbilitiesSafely(registry, {
        ability: RbacAbility.role('admin'),
      });

      final callback = registry.resolve(ability);
      expect(callback, isNotNull);
      callback!(
        GateEvaluationContext(
          context: _context(),
          principal: _principal('1', ['admin']),
        ),
      );
      expect(originalCalled, isTrue);
    });
  });

  group('Policies', () {
    test('registers policy abilities and evaluates payloads', () async {
      final registry = GateRegistry.instance;
      const prefix = 'project';
      final binding = PolicyBinding<Project>(
        policy: ProjectPolicy(),
        abilityPrefix: prefix,
      );

      final abilities = registerPolicyBindings(registry, [binding]);
      addTearDown(() {
        for (final ability in abilities) {
          registry.unregister(ability);
        }
      });

      final context = _context();
      final owner = _principal('owner-1', ['user']);
      final other = _principal('user-2', ['user']);
      final project = Project(id: 'p1', ownerId: 'owner-1');

      final viewGate = registry.resolve('$prefix.view');
      final updateGate = registry.resolve('$prefix.update');
      final deleteGate = registry.resolve('$prefix.delete');
      final createGate = registry.resolve('$prefix.create');

      expect(viewGate, isNotNull);
      expect(updateGate, isNotNull);
      expect(deleteGate, isNotNull);
      expect(createGate, isNotNull);

      expect(
        await Future.value(
          updateGate!(
            GateEvaluationContext(
              context: context,
              principal: owner,
              payload: project,
            ),
          ),
        ),
        isTrue,
      );
      expect(
        await Future.value(
          updateGate(
            GateEvaluationContext(
              context: context,
              principal: other,
              payload: project,
            ),
          ),
        ),
        isFalse,
      );
      expect(
        await Future.value(
          deleteGate!(
            GateEvaluationContext(
              context: context,
              principal: owner,
              payload: project,
            ),
          ),
        ),
        isTrue,
      );
      expect(
        await Future.value(
          createGate!(
            GateEvaluationContext(context: context, principal: owner),
          ),
        ),
        isTrue,
      );
      expect(
        await Future.value(
          createGate(GateEvaluationContext(context: context, principal: null)),
        ),
        isFalse,
      );
    });
  });
}
