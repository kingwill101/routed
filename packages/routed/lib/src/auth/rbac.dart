import 'package:server_auth/server_auth.dart' show RbacAbility;
import 'package:routed/src/auth/haigate.dart';

/// {@template routed_auth_rbac}
/// Role-based access control helpers built on top of Haigate.
///
/// Use `RbacOptions` from `server_auth` to declare ability -> role mappings
/// and register them with `GateRegistry` or `Haigate` using these helpers.
/// {@endtemplate}

/// Builds a gate callback for an RBAC ability.
GateCallback rbacGate(RbacAbility ability) {
  return (GateEvaluationContext context) {
    return ability.evaluate(context.principal);
  };
}

/// Registers RBAC abilities into a [GateRegistry].
Set<String> registerRbacAbilities(
  GateRegistry registry,
  Map<String, RbacAbility> abilities,
) {
  final registered = <String>{};
  abilities.forEach((ability, rule) {
    final trimmed = ability.trim();
    if (trimmed.isEmpty) {
      return;
    }
    registry.register(trimmed, rbacGate(rule));
    registered.add(trimmed);
  });
  return registered;
}

/// Safely registers RBAC abilities without overriding existing entries.
Set<String> registerRbacAbilitiesSafely(
  GateRegistry registry,
  Map<String, RbacAbility> abilities, {
  Set<String> managed = const <String>{},
}) {
  final registered = <String>{};
  abilities.forEach((ability, rule) {
    final trimmed = ability.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (registry.resolve(trimmed) != null && !managed.contains(trimmed)) {
      return;
    }
    if (managed.contains(trimmed)) {
      registry.unregister(trimmed);
    }
    registry.register(trimmed, rbacGate(rule));
    registered.add(trimmed);
  });
  return registered;
}

/// Helper to apply RBAC abilities to the global Haigate registry.
Set<String> registerRbacWithHaigate(Map<String, RbacAbility> abilities) {
  return registerRbacAbilities(Haigate.registry, abilities);
}
