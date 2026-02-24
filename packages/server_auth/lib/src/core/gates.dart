import 'dart:async';

import 'models.dart';

/// Generic gate callback contract.
typedef AuthGateCallback<TContext> =
    FutureOr<bool> Function(AuthGateEvaluationContext<TContext> context);

/// Observer callback for gate evaluation results.
typedef AuthGateObserver<TContext> =
    void Function(AuthGateEvaluation<TContext> evaluation);

/// Resolves payloads for gate ability checks.
typedef AuthGatePayloadResolver<TContext> =
    Object? Function(TContext context, String ability);

/// Creates a gate callback that allows only guests.
AuthGateCallback<TContext> guestGate<TContext>() {
  return (AuthGateEvaluationContext<TContext> context) =>
      context.principal == null;
}

/// Creates a gate callback that allows only authenticated principals.
AuthGateCallback<TContext> authenticatedGate<TContext>() {
  return (AuthGateEvaluationContext<TContext> context) =>
      context.principal != null;
}

/// Creates a roles gate callback.
///
/// When [requiredRoles] is empty, authenticated users are allowed and guests
/// follow [allowGuest].
AuthGateCallback<TContext> rolesGate<TContext>(
  Iterable<String> requiredRoles, {
  bool any = false,
  bool allowGuest = false,
}) {
  final normalized = requiredRoles
      .map((role) => role.trim())
      .where((role) => role.isNotEmpty)
      .toList(growable: false);

  return (AuthGateEvaluationContext<TContext> context) {
    final principal = context.principal;
    if (principal == null) {
      return allowGuest;
    }
    if (normalized.isEmpty) {
      return true;
    }
    return any
        ? normalized.any(principal.hasRole)
        : normalized.every(principal.hasRole);
  };
}

/// Exception thrown when there is an error during gate registration.
class AuthGateRegistrationException implements Exception {
  AuthGateRegistrationException(this.message);

  /// The error message describing the registration issue.
  final String message;

  @override
  String toString() => 'AuthGateRegistrationException: $message';
}

/// Exception thrown when a gate denies access to a specific ability.
class AuthGateViolation<TContext> implements Exception {
  AuthGateViolation({
    required this.ability,
    required this.context,
    this.message,
    this.payload,
  });

  /// The name of the denied ability.
  final String ability;

  /// The context in which the violation occurred.
  final TContext context;

  /// Optional message describing the violation.
  final String? message;

  /// Optional payload associated with the violation.
  final Object? payload;

  @override
  String toString() =>
      'AuthGateViolation(ability: $ability, message: ${message ?? 'denied'})';
}

/// Context provided during gate evaluation.
class AuthGateEvaluationContext<TContext> {
  AuthGateEvaluationContext({
    required this.context,
    required this.principal,
    this.payload,
  });

  /// Framework/runtime context.
  final TContext context;

  /// The authenticated principal, if available.
  final AuthPrincipal? principal;

  /// Optional payload for the evaluation.
  final Object? payload;
}

/// Result payload emitted after a gate evaluation.
class AuthGateEvaluation<TContext> {
  AuthGateEvaluation({
    required this.ability,
    required this.allowed,
    required this.context,
    required this.principal,
    this.payload,
  });

  /// The evaluated ability.
  final String ability;

  /// Whether the ability was allowed.
  final bool allowed;

  /// Framework/runtime context.
  final TContext context;

  /// The authenticated principal, if available.
  final AuthPrincipal? principal;

  /// Optional payload associated with the evaluation.
  final Object? payload;
}

/// Registry for gate callbacks keyed by ability.
class AuthGateRegistry<TContext> {
  final Map<String, AuthGateCallback<TContext>> _entries =
      <String, AuthGateCallback<TContext>>{};

  /// Registers a gate callback for [ability].
  void register(
    String ability,
    AuthGateCallback<TContext> callback, {
    bool overrideExisting = true,
  }) {
    final key = ability.trim();
    if (key.isEmpty) {
      throw AuthGateRegistrationException('Ability name cannot be empty.');
    }
    final exists = _entries.containsKey(key);
    if (exists) {
      if (!overrideExisting) {
        return;
      }
      throw AuthGateRegistrationException(
        'Ability "$key" is already registered.',
      );
    }
    _entries[key] = callback;
  }

  /// Registers multiple gate callbacks.
  void registerAll(
    Map<String, AuthGateCallback<TContext>> entries, {
    bool overrideExisting = true,
  }) {
    entries.forEach((ability, callback) {
      register(ability, callback, overrideExisting: overrideExisting);
    });
  }

  /// Unregisters [ability].
  void unregister(String ability) {
    _entries.remove(ability.trim());
  }

  /// Resolves callback for [ability].
  AuthGateCallback<TContext>? resolve(String ability) =>
      _entries[ability.trim()];

  /// All registered ability names.
  Iterable<String> get abilities => _entries.keys;
}

/// Framework-agnostic gate evaluation service.
class AuthGateService<TContext> {
  AuthGateService({
    AuthGateRegistry<TContext>? registry,
    this.principalResolver,
  }) : registry = registry ?? AuthGateRegistry<TContext>();

  /// Backing registry for ability callbacks.
  final AuthGateRegistry<TContext> registry;

  /// Optional resolver used when [can] is called without an explicit principal.
  final AuthPrincipal? Function(TContext context)? principalResolver;

  final List<AuthGateObserver<TContext>> _observers =
      <AuthGateObserver<TContext>>[];

  void register(String ability, AuthGateCallback<TContext> callback) {
    registry.register(ability, callback);
  }

  void registerAll(Map<String, AuthGateCallback<TContext>> entries) {
    registry.registerAll(entries);
  }

  void unregister(String ability) {
    registry.unregister(ability);
  }

  void addObserver(AuthGateObserver<TContext> observer) {
    _observers.add(observer);
  }

  void removeObserver(AuthGateObserver<TContext> observer) {
    _observers.remove(observer);
  }

  Future<bool> can(
    String ability, {
    required TContext context,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    final callback = registry.resolve(ability);
    if (callback == null) {
      throw AuthGateRegistrationException(
        'Ability "$ability" is not registered.',
      );
    }

    final resolvedPrincipal = principal ?? principalResolver?.call(context);
    final evaluationContext = AuthGateEvaluationContext<TContext>(
      context: context,
      principal: resolvedPrincipal,
      payload: payload,
    );

    final allowed = await Future<bool>.value(callback(evaluationContext));
    _notifyObservers(
      AuthGateEvaluation<TContext>(
        ability: ability,
        allowed: allowed,
        context: context,
        principal: resolvedPrincipal,
        payload: payload,
      ),
    );
    return allowed;
  }

  Future<void> authorize(
    String ability, {
    required TContext context,
    AuthPrincipal? principal,
    Object? payload,
    String? message,
  }) async {
    final allowed = await can(
      ability,
      context: context,
      principal: principal,
      payload: payload,
    );
    if (!allowed) {
      throw AuthGateViolation<TContext>(
        ability: ability,
        context: context,
        message: message,
        payload: payload,
      );
    }
  }

  Future<bool> any(
    Iterable<String> abilities, {
    required TContext context,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    for (final ability in abilities) {
      if (await can(
        ability,
        context: context,
        principal: principal,
        payload: payload,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<bool> all(
    Iterable<String> abilities, {
    required TContext context,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    for (final ability in abilities) {
      if (!await can(
        ability,
        context: context,
        principal: principal,
        payload: payload,
      )) {
        return false;
      }
    }
    return true;
  }

  /// Returns the first denied ability as a violation, if any.
  Future<AuthGateViolation<TContext>?> firstDenied(
    Iterable<String> abilities, {
    required TContext context,
    AuthPrincipal? principal,
    AuthGatePayloadResolver<TContext>? payloadResolver,
    String? message,
  }) async {
    for (final ability in abilities) {
      final payload = payloadResolver?.call(context, ability);
      final allowed = await can(
        ability,
        context: context,
        principal: principal,
        payload: payload,
      );
      if (!allowed) {
        return AuthGateViolation<TContext>(
          ability: ability,
          context: context,
          message: message,
          payload: payload,
        );
      }
    }
    return null;
  }

  void _notifyObservers(AuthGateEvaluation<TContext> evaluation) {
    for (final observer in List<AuthGateObserver<TContext>>.from(_observers)) {
      observer(evaluation);
    }
  }
}
