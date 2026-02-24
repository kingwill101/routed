import 'package:server_auth/server_auth.dart'
    show
        AuthGateCallback,
        AuthGateEvaluationContext,
        AuthGateRegistry,
        Policy,
        PolicyAction,
        PolicyBinding;
import 'package:routed/src/auth/haigate.dart';
import 'package:routed/src/context/context.dart';

/// {@template routed_auth_policy}
/// Policy-based authorization built on top of Haigate.
///
/// Use policy contracts from `server_auth` and register them against Routed
/// gate abilities via these helpers.
/// {@endtemplate}

/// Builds a gate callback for a specific policy action.
AuthGateCallback<EngineContext> policyGate<T extends Object>(
  Policy<T> policy,
  PolicyAction action,
) {
  return (AuthGateEvaluationContext<EngineContext> context) {
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

/// Registers policy abilities into an [AuthGateRegistry].
Set<String> registerPolicyBindings(
  AuthGateRegistry<EngineContext> registry,
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
  AuthGateRegistry<EngineContext> registry,
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
  AuthGateRegistry<EngineContext> registry,
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
