import 'dart:async';

import 'package:routed/src/auth/haigate.dart';
import 'package:routed/src/auth/session_auth.dart';

/// {@template routed_auth_rbac}
/// Role-based access control helpers built on top of Haigate.
///
/// Use [RbacOptions] to declare ability → role mappings and register them with
/// `GateRegistry` or `Haigate`. Each ability is evaluated against the
/// authenticated principal's roles.
/// {@endtemplate}
class RbacAbility {
  const RbacAbility({
    required this.roles,
    this.any = false,
    this.allowGuest = false,
  });

  /// Creates a role ability that requires a single role.
  factory RbacAbility.role(String role, {bool allowGuest = false}) {
    return RbacAbility(roles: [role], allowGuest: allowGuest);
  }

  /// Creates a role ability that allows any role in [roles].
  factory RbacAbility.any(List<String> roles, {bool allowGuest = false}) {
    return RbacAbility(roles: roles, any: true, allowGuest: allowGuest);
  }

  /// Creates a role ability that requires all roles in [roles].
  factory RbacAbility.all(List<String> roles, {bool allowGuest = false}) {
    return RbacAbility(roles: roles, any: false, allowGuest: allowGuest);
  }

  /// Roles required to satisfy the ability.
  final List<String> roles;

  /// Whether any role is sufficient (`true`) or all roles are required.
  final bool any;

  /// Whether to allow guests when no principal is present.
  final bool allowGuest;

  /// Evaluates the ability against the current principal.
  bool evaluate(AuthPrincipal? principal) {
    if (principal == null) {
      return allowGuest;
    }
    if (roles.isEmpty) {
      return true;
    }
    return any ? roles.any(principal.hasRole) : roles.every(principal.hasRole);
  }
}

/// {@macro routed_auth_rbac}
class RbacOptions {
  const RbacOptions({this.abilities = const <String, RbacAbility>{}});

  /// Ability → role mapping.
  final Map<String, RbacAbility> abilities;

  /// Returns `true` when there are abilities to register.
  bool get isEmpty => abilities.isEmpty;
}

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
