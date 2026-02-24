import 'dart:async';

import 'gates.dart';
import 'models.dart';

/// Role-based ability definition.
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

/// RBAC configuration options.
class RbacOptions {
  const RbacOptions({this.abilities = const <String, RbacAbility>{}});

  /// Ability -> role mapping.
  final Map<String, RbacAbility> abilities;

  /// Returns `true` when there are abilities to register.
  bool get isEmpty => abilities.isEmpty;
}

/// Available policy actions.
enum PolicyAction { view, create, update, delete }

/// Resource policy contract.
abstract class Policy<T extends Object> {
  const Policy();

  /// Whether the principal can view a resource.
  FutureOr<bool> canView(AuthPrincipal? principal, T resource);

  /// Whether the principal can create a resource.
  FutureOr<bool> canCreate(AuthPrincipal? principal);

  /// Whether the principal can update a resource.
  FutureOr<bool> canUpdate(AuthPrincipal? principal, T resource);

  /// Whether the principal can delete a resource.
  FutureOr<bool> canDelete(AuthPrincipal? principal, T resource);
}

/// Binds a policy to an ability prefix.
class PolicyBinding<T extends Object> {
  const PolicyBinding({
    required this.policy,
    required this.abilityPrefix,
    this.actions = const {
      PolicyAction.view,
      PolicyAction.create,
      PolicyAction.update,
      PolicyAction.delete,
    },
  });

  /// Policy instance used for evaluations.
  final Policy<T> policy;

  /// Prefix used to build ability names (e.g. `project`).
  final String abilityPrefix;

  /// Actions to register for this policy.
  final Set<PolicyAction> actions;
}

/// Policy registration options.
class PolicyOptions {
  const PolicyOptions({this.bindings = const <PolicyBinding>[]});

  /// Policy bindings to register.
  final List<PolicyBinding> bindings;

  /// Returns `true` when there are no policy bindings.
  bool get isEmpty => bindings.isEmpty;
}

/// Builds a gate callback for an RBAC ability.
AuthGateCallback<TContext> rbacGate<TContext>(RbacAbility ability) {
  return (AuthGateEvaluationContext<TContext> context) {
    return ability.evaluate(context.principal);
  };
}

/// Registers RBAC abilities into [registry].
Set<String> registerRbacAbilities<TContext>(
  AuthGateRegistry<TContext> registry,
  Map<String, RbacAbility> abilities,
) {
  final registered = <String>{};
  abilities.forEach((ability, rule) {
    final trimmed = ability.trim();
    if (trimmed.isEmpty) {
      return;
    }
    registry.register(trimmed, rbacGate<TContext>(rule));
    registered.add(trimmed);
  });
  return registered;
}

/// Registers RBAC abilities without overriding unmanaged entries.
Set<String> registerRbacAbilitiesSafely<TContext>(
  AuthGateRegistry<TContext> registry,
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
    registry.register(trimmed, rbacGate<TContext>(rule));
    registered.add(trimmed);
  });
  return registered;
}

/// Builds a gate callback for a specific policy action.
AuthGateCallback<TContext> policyGate<TContext, T extends Object>(
  Policy<T> policy,
  PolicyAction action,
) {
  return (AuthGateEvaluationContext<TContext> context) {
    final principal = context.principal;
    final payload = context.payload;
    switch (action) {
      case PolicyAction.view:
        if (payload is T) {
          return policy.canView(principal, payload);
        }
        return false;
      case PolicyAction.create:
        return policy.canCreate(principal);
      case PolicyAction.update:
        if (payload is T) {
          return policy.canUpdate(principal, payload);
        }
        return false;
      case PolicyAction.delete:
        if (payload is T) {
          return policy.canDelete(principal, payload);
        }
        return false;
    }
  };
}

/// Registers policy abilities into [registry].
Set<String> registerPolicyBindings<TContext>(
  AuthGateRegistry<TContext> registry,
  List<PolicyBinding> bindings,
) {
  final registered = <String>{};
  for (final binding in bindings) {
    registered.addAll(_registerPolicyBinding<TContext>(registry, binding));
  }
  return registered;
}

/// Registers policy abilities without overriding unmanaged entries.
Set<String> registerPolicyBindingsSafely<TContext>(
  AuthGateRegistry<TContext> registry,
  List<PolicyBinding> bindings, {
  Set<String> managed = const <String>{},
}) {
  final registered = <String>{};
  for (final binding in bindings) {
    registered.addAll(
      _registerPolicyBinding<TContext>(registry, binding, managed: managed),
    );
  }
  return registered;
}

Set<String> _registerPolicyBinding<TContext>(
  AuthGateRegistry<TContext> registry,
  PolicyBinding binding, {
  Set<String> managed = const <String>{},
}) {
  final registered = <String>{};
  final prefix = binding.abilityPrefix.trim();
  if (prefix.isEmpty) {
    return registered;
  }

  for (final action in binding.actions) {
    final ability = '$prefix.${action.name}';
    if (registry.resolve(ability) != null && !managed.contains(ability)) {
      continue;
    }
    if (managed.contains(ability)) {
      registry.unregister(ability);
    }
    registry.register(
      ability,
      policyGate<TContext, Object>(binding.policy, action),
    );
    registered.add(ability);
  }

  return registered;
}
