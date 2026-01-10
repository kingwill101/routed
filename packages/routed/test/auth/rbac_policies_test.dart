import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

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

Future<T> _withContext<T>(Future<T> Function(EngineContext ctx) action) async {
  final engine = testEngine();
  late T result;
  engine.get('/rbac', (ctx) async {
    result = await action(ctx);
    return ctx.json({'ok': true});
  });

  await engine.initialize();
  final client = TestClient(
    RoutedRequestHandler(engine),
    mode: TransportMode.ephemeralServer,
  );
  await client.get('/rbac');
  await client.close();
  await engine.close();
  return result;
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

    test('does not override existing gates', () async {
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

      await _withContext((ctx) async {
        callback!(
          GateEvaluationContext(
            context: ctx,
            principal: _principal('1', ['admin']),
          ),
        );
        return true;
      });

      expect(originalCalled, isTrue);
    });

    test('registers and overrides managed abilities', () async {
      final registry = GateRegistry.instance;
      const ability = 'rbac.swap';
      var firstCalled = false;
      registry.register(ability, (_) {
        firstCalled = true;
        return false;
      });

      addTearDown(() => registry.unregister(ability));

      registerRbacAbilitiesSafely(
        registry,
        {ability: RbacAbility.role('admin')},
        managed: {ability},
      );

      final callback = registry.resolve(ability);
      expect(callback, isNotNull);

      final allowed = await _withContext((ctx) async {
        return await Future.value(
          callback!(
            GateEvaluationContext(
              context: ctx,
              principal: _principal('1', ['admin']),
            ),
          ),
        );
      });

      expect(firstCalled, isFalse);
      expect(allowed, isTrue);
    });

    test('registers abilities and skips empty keys', () {
      final registry = GateRegistry.instance;
      const ability = 'rbac.trim';
      addTearDown(() => registry.unregister(ability));

      final registered = registerRbacAbilities(registry, {
        '  $ability  ': RbacAbility.role('admin'),
        ' ': RbacAbility.role('guest'),
      });

      expect(registered, contains(ability));
      expect(registry.resolve(ability), isNotNull);
    });

    test('returns true when roles are empty', () {
      const ability = RbacAbility(roles: []);
      expect(ability.evaluate(_principal('1', ['user'])), isTrue);
      expect(ability.evaluate(null), isFalse);
    });

    test('reports empty options', () {
      const options = RbacOptions();
      expect(options.isEmpty, isTrue);
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

      final results = await _withContext((ctx) async {
        final updateOwner = await Future.value(
          updateGate!(
            GateEvaluationContext(
              context: ctx,
              principal: owner,
              payload: project,
            ),
          ),
        );
        final updateOther = await Future.value(
          updateGate(
            GateEvaluationContext(
              context: ctx,
              principal: other,
              payload: project,
            ),
          ),
        );
        final deleteOwner = await Future.value(
          deleteGate!(
            GateEvaluationContext(
              context: ctx,
              principal: owner,
              payload: project,
            ),
          ),
        );
        final createOwner = await Future.value(
          createGate!(GateEvaluationContext(context: ctx, principal: owner)),
        );
        final createGuest = await Future.value(
          createGate(GateEvaluationContext(context: ctx, principal: null)),
        );

        return {
          'updateOwner': updateOwner,
          'updateOther': updateOther,
          'deleteOwner': deleteOwner,
          'createOwner': createOwner,
          'createGuest': createGuest,
        };
      });

      expect(results['updateOwner'], isTrue);
      expect(results['updateOther'], isFalse);
      expect(results['deleteOwner'], isTrue);
      expect(results['createOwner'], isTrue);
      expect(results['createGuest'], isFalse);
    });
  });
}
