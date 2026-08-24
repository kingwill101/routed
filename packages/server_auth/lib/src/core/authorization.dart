import 'dart:async';

import 'gates.dart';
import 'models.dart';

/// Role-based ability definition.
class RbacAbility {
  /// Creates an ability from the required [roles].
  ///
  /// A null principal is allowed only when [allowGuest] is true. An
  /// authenticated principal is allowed when [roles] is empty; otherwise
  /// [any] selects whether one or every role must match.
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
  /// Creates options from an ability-name-to-rule map.
  const RbacOptions({this.abilities = const <String, RbacAbility>{}});

  /// Ability -> role mapping.
  final Map<String, RbacAbility> abilities;

  /// Returns `true` when there are abilities to register.
  bool get isEmpty => abilities.isEmpty;
}

/// Available policy actions.
enum PolicyAction {
  /// Evaluates access to an existing resource using a payload of `T`.
  view,

  /// Evaluates creation access without a resource payload.
  create,

  /// Evaluates modification access using a payload of `T`.
  update,

  /// Evaluates deletion access using a payload of `T`.
  delete,
}

/// Resource policy contract.
abstract class Policy<T extends Object> {
  /// Creates a policy contract for resources of type `T`.
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
  /// Binds [policy] to abilities beginning with [abilityPrefix].
  ///
  /// Unless [actions] is supplied, view, create, update, and delete abilities
  /// are registered.
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
  /// Creates options from [bindings].
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
///
/// Ability names are trimmed and blank names are skipped. Duplicate names are
/// delegated to [AuthGateRegistry.register] and therefore throw. Returns the
/// normalized names that were successfully registered.
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
///
/// Blank names are skipped. Existing names are replaced only when listed in
/// [managed]; unmanaged duplicates remain unchanged. Returns normalized names
/// registered by this call.
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
    registered.addAll(
      registerGateCallbacksSafely<TContext>(
        registry,
        <String, AuthGateCallback<TContext>>{trimmed: rbacGate<TContext>(rule)},
        managed: managed,
      ),
    );
  });
  return registered;
}

/// Synchronizes [managed] with [nextManaged], unregistering stale abilities.
///
/// Stale registrations are removed from [registry], and the caller-owned
/// [managed] set is cleared and updated in place.
void syncManagedGateAbilities<TContext>(
  AuthGateRegistry<TContext> registry, {
  required Set<String> managed,
  required Set<String> nextManaged,
}) {
  for (final ability in managed.difference(nextManaged)) {
    registry.unregister(ability);
  }
  managed
    ..clear()
    ..addAll(nextManaged);
}

/// Builds and synchronizes managed gate registrations from [definitions].
///
/// Ability names are trimmed; blank names and definitions whose [buildGate]
/// result is `null` are skipped. Managed entries are replaced while unmanaged
/// duplicates are preserved. Returns and updates [managed] with normalized
/// successful registrations.
Set<String> syncManagedGateDefinitions<TContext, TDefinition extends Object>(
  AuthGateRegistry<TContext> registry,
  Map<String, TDefinition> definitions, {
  required AuthGateCallback<TContext>? Function(
    String ability,
    TDefinition definition,
  )
  buildGate,
  required Set<String> managed,
}) {
  final entries = <String, AuthGateCallback<TContext>>{};
  definitions.forEach((ability, definition) {
    final trimmed = ability.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final callback = buildGate(trimmed, definition);
    if (callback == null) {
      return;
    }
    entries[trimmed] = callback;
  });

  final nextManaged = registerGateCallbacksSafely<TContext>(
    registry,
    entries,
    managed: managed,
  );
  syncManagedGateAbilities<TContext>(
    registry,
    managed: managed,
    nextManaged: nextManaged,
  );
  return nextManaged;
}

/// Registers RBAC abilities and synchronizes the managed ability set.
///
/// An empty [abilities] map removes every previously managed registration.
/// The caller-owned [managed] set is updated in place.
Set<String> syncManagedRbacAbilities<TContext>(
  AuthGateRegistry<TContext> registry,
  Map<String, RbacAbility> abilities, {
  required Set<String> managed,
}) {
  final nextManaged = abilities.isEmpty
      ? const <String>{}
      : registerRbacAbilitiesSafely<TContext>(
          registry,
          abilities,
          managed: managed,
        );
  syncManagedGateAbilities<TContext>(
    registry,
    managed: managed,
    nextManaged: nextManaged,
  );
  return nextManaged;
}

/// Registers policy abilities and synchronizes the managed ability set.
///
/// An empty [bindings] list removes every previously managed registration.
/// The caller-owned [managed] set is updated in place.
Set<String> syncManagedPolicyBindings<TContext>(
  AuthGateRegistry<TContext> registry,
  List<PolicyBinding> bindings, {
  required Set<String> managed,
}) {
  final nextManaged = bindings.isEmpty
      ? const <String>{}
      : registerPolicyBindingsSafely<TContext>(
          registry,
          bindings,
          managed: managed,
        );
  syncManagedGateAbilities<TContext>(
    registry,
    managed: managed,
    nextManaged: nextManaged,
  );
  return nextManaged;
}

/// Builds a gate callback for a specific policy action.
///
/// [PolicyAction.create] ignores the payload. View, update, and delete return
/// `false` when the payload is not a `T`; policy results may be synchronous or
/// asynchronous.
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
///
/// Each non-empty trimmed prefix produces abilities named `$prefix.$action`.
/// Duplicate names are delegated to the registry and throw. Returns names
/// successfully registered by this call.
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
///
/// Empty trimmed prefixes are skipped. Managed duplicate names are replaced;
/// unmanaged duplicates remain unchanged. Returns normalized names registered.
Set<String> registerPolicyBindingsSafely<TContext>(
  AuthGateRegistry<TContext> registry,
  List<PolicyBinding> bindings, {
  Set<String> managed = const <String>{},
}) {
  final registered = <String>{};
  for (final binding in bindings) {
    registered.addAll(
      _registerPolicyBindingSafely<TContext>(
        registry,
        binding,
        managed: managed,
      ),
    );
  }
  return registered;
}

Set<String> _registerPolicyBinding<TContext>(
  AuthGateRegistry<TContext> registry,
  PolicyBinding binding,
) {
  final registered = <String>{};
  final prefix = binding.abilityPrefix.trim();
  if (prefix.isEmpty) {
    return registered;
  }

  for (final action in binding.actions) {
    final ability = '$prefix.${action.name}';
    registry.register(
      ability,
      policyGate<TContext, Object>(binding.policy, action),
    );
    registered.add(ability);
  }

  return registered;
}

Set<String> _registerPolicyBindingSafely<TContext>(
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
    registered.addAll(
      registerGateCallbacksSafely<TContext>(
        registry,
        <String, AuthGateCallback<TContext>>{
          ability: policyGate<TContext, Object>(binding.policy, action),
        },
        managed: managed,
      ),
    );
  }

  return registered;
}
