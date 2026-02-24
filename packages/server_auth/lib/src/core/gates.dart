import 'dart:async';

import 'models.dart';

/// Generic gate callback contract.
typedef AuthGateCallback<TContext> =
    FutureOr<bool> Function(AuthGateEvaluationContext<TContext> context);

/// Observer callback for gate evaluation results.
typedef AuthGateObserver<TContext> =
    void Function(AuthGateEvaluation<TContext> evaluation);

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
