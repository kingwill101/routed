import 'dart:async';

import 'package:routed/src/auth/haigate.dart';
import 'package:routed/src/auth/session_auth.dart';

/// {@template routed_auth_policy}
/// Policy-based authorization built on top of Haigate.
///
/// Policies encapsulate authorization decisions for a specific resource type
/// (e.g. `ProjectPolicy`). Use [PolicyBinding] with an ability prefix to
/// register Haigate abilities like `project.view` or `project.update`.
/// {@endtemplate}

/// Available policy actions.
enum PolicyAction { view, create, update, delete }

/// {@macro routed_auth_policy}
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

/// Binds a policy to a Haigate ability prefix.
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

/// Options that configure policy bindings.
class PolicyOptions {
  const PolicyOptions({this.bindings = const <PolicyBinding>[]});

  /// Policy bindings to register with Haigate.
  final List<PolicyBinding> bindings;

  /// Returns `true` when there are no policy bindings.
  bool get isEmpty => bindings.isEmpty;
}

/// Builds a gate callback for a specific policy action.
GateCallback policyGate<T extends Object>(
  Policy<T> policy,
  PolicyAction action,
) {
  return (GateEvaluationContext context) {
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

/// Registers policy abilities into a [GateRegistry].
Set<String> registerPolicyBindings(
  GateRegistry registry,
  List<PolicyBinding> bindings,
) {
  final registered = <String>{};
  for (final binding in bindings) {
    registered.addAll(_registerBinding(registry, binding));
  }
  return registered;
}

/// Registers policy abilities without overriding existing entries.
Set<String> registerPolicyBindingsSafely(
  GateRegistry registry,
  List<PolicyBinding> bindings, {
  Set<String> managed = const <String>{},
}) {
  final registered = <String>{};
  for (final binding in bindings) {
    registered.addAll(_registerBinding(registry, binding, managed: managed));
  }
  return registered;
}

Set<String> _registerBinding(
  GateRegistry registry,
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
    registry.register(ability, policyGate(binding.policy, action));
    registered.add(ability);
  }

  return registered;
}

/// Helper to apply policy bindings to the global Haigate registry.
Set<String> registerPoliciesWithHaigate(List<PolicyBinding> bindings) {
  return registerPolicyBindings(Haigate.registry, bindings);
}
