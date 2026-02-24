import 'dart:async';

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
