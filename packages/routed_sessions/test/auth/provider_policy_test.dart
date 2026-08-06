import 'package:routed/routed.dart';
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

void main() {
  test('AuthServiceProvider registers RBAC and policy abilities', () async {
    final engine = await Engine.create(
      providers: [CoreServiceProvider(), RoutingServiceProvider()],
      options: [
        (engine) {
          engine.container.instance<AuthOptions>(
            AuthOptions(
              providers: const [],
              rbac: RbacOptions(
                abilities: {'admin.only': RbacAbility.role('admin')},
              ),

              policies: PolicyOptions(
                bindings: [
                  PolicyBinding<Project>(
                    policy: ProjectPolicy(),
                    abilityPrefix: 'project',
                    actions: {PolicyAction.update},
                  ),
                ],
              ),
            ),
          );
        },
      ],
    );

    final registry = GateRegistry.instance;
    expect(registry.resolve('admin.only'), isNotNull);
    expect(registry.resolve('project.update'), isNotNull);

    addTearDown(() async {
      registry.unregister('admin.only');
      registry.unregister('project.update');
      await engine.close();
    });
  });
}
