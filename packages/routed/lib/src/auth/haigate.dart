import 'dart:async';
import 'dart:io';

import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/support/named_registry.dart';

/// A callback function used to evaluate whether a specific ability is allowed
/// in the given [GateEvaluationContext].
typedef GateCallback = FutureOr<bool> Function(GateEvaluationContext context);

/// A function that observes the result of a gate evaluation.
typedef GateObserver = void Function(GateEvaluation evaluation);

/// A function that provides a payload for a specific ability in the given
/// [EngineContext].
typedef GatePayloadProvider =
    Object? Function(EngineContext ctx, String ability);

/// A handler function that is called when a gate denies access.
typedef GateDeniedHandler =
    FutureOr<Response?> Function(GateViolation violation, EngineContext ctx);

/// Exception thrown when there is an error during gate registration.
class GateRegistrationException implements Exception {
  GateRegistrationException(this.message);

  /// The error message describing the registration issue.
  final String message;

  @override
  String toString() => 'GateRegistrationException: $message';
}

/// Exception thrown when a gate denies access to a specific ability.
class GateViolation implements Exception {
  /// Creates a new [GateViolation].
  ///
  /// - [ability]: The name of the denied ability.
  /// - [context]: The [EngineContext] in which the violation occurred.
  /// - [message]: An optional message describing the violation.
  /// - [payload]: An optional payload associated with the violation.
  GateViolation({
    required this.ability,
    required this.context,
    this.message,
    this.payload,
  });

  /// The name of the denied ability.
  final String ability;

  /// The [EngineContext] in which the violation occurred.
  final EngineContext context;

  /// An optional message describing the violation.
  final String? message;

  /// An optional payload associated with the violation.
  final Object? payload;

  @override
  String toString() =>
      'GateViolation(ability: $ability, message: ${message ?? 'denied'})';
}

/// Context provided during the evaluation of a gate.
///
/// This contains information about the current [EngineContext], the
/// authenticated principal, and any additional payload.
class GateEvaluationContext {
  /// Creates a new [GateEvaluationContext].
  ///
  /// - [context]: The current [EngineContext].
  /// - [principal]: The authenticated principal, if available.
  /// - [payload]: An optional payload for the evaluation.
  GateEvaluationContext({
    required this.context,
    required this.principal,
    this.payload,
  });

  /// The current [EngineContext].
  final EngineContext context;

  /// The authenticated principal, if available.
  final AuthPrincipal? principal;

  /// An optional payload for the evaluation.
  final Object? payload;
}

/// Represents the result of a gate evaluation.
///
/// This includes the evaluated ability, whether it was allowed, and
/// additional context such as the principal and payload.
class GateEvaluation {
  /// Creates a new [GateEvaluation].
  ///
  /// - [ability]: The name of the evaluated ability.
  /// - [allowed]: Whether the ability was allowed.
  /// - [context]: The [EngineContext] in which the evaluation occurred.
  /// - [principal]: The authenticated principal, if available.
  /// - [payload]: An optional payload associated with the evaluation.
  GateEvaluation({
    required this.ability,
    required this.allowed,
    required this.context,
    required this.principal,
    this.payload,
  });

  /// The name of the evaluated ability.
  final String ability;

  /// Whether the ability was allowed.
  final bool allowed;

  /// The [EngineContext] in which the evaluation occurred.
  final EngineContext context;

  /// The authenticated principal, if available.
  final AuthPrincipal? principal;

  /// An optional payload associated with the evaluation.
  final Object? payload;
}

/// A registry for managing gate callbacks.
///
/// This allows registering, unregistering, and resolving gate callbacks
/// by their ability names.
class GateRegistry extends NamedRegistry<GateCallback> {
  GateRegistry._();

  /// The singleton instance of [GateRegistry].
  static final GateRegistry instance = GateRegistry._();

  @override
  String normalizeName(String name) => name.trim();

  @override
  bool onDuplicate(String name, GateCallback existing, bool overrideExisting) {
    if (!overrideExisting) {
      return false;
    }
    throw GateRegistrationException('Ability "$name" is already registered.');
  }

  /// Registers a new gate callback for the given [ability].
  ///
  /// Throws a [GateRegistrationException] if the ability name is empty.
  void register(String ability, GateCallback callback) {
    final key = normalizeName(ability);
    if (key.isEmpty) {
      throw GateRegistrationException('Ability name cannot be empty.');
    }
    registerEntry(key, callback);
  }

  /// Registers multiple gate callbacks from the given [entries].
  void registerAll(Map<String, GateCallback> entries) {
    entries.forEach(register);
  }

  /// Unregisters the gate callback for the given [ability].
  void unregister(String ability) {
    unregisterEntry(ability);
  }

  /// Resolves the gate callback for the given [ability].
  ///
  /// Returns `null` if no callback is registered for the ability.
  GateCallback? resolve(String ability) => getEntry(ability);

  /// Returns a list of all registered ability names.
  Iterable<String> get abilities => entryNames;
}

class Haigate {
  Haigate._();

  static final GateRegistry _registry = GateRegistry.instance;
  static final List<GateObserver> _observers = <GateObserver>[];

  static GateRegistry get registry => _registry;

  static void register(String ability, GateCallback callback) {
    _registry.register(ability, callback);
  }

  static void registerAll(Map<String, GateCallback> entries) {
    _registry.registerAll(entries);
  }

  static void unregister(String ability) {
    _registry.unregister(ability);
  }

  static void addObserver(GateObserver observer) {
    _observers.add(observer);
  }

  static void removeObserver(GateObserver observer) {
    _observers.remove(observer);
  }

  static Future<bool> can(
    String ability, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    final callback = _registry.resolve(ability);
    if (callback == null) {
      throw GateRegistrationException('Ability "$ability" is not registered.');
    }

    AuthPrincipal? resolvedPrincipal = principal;
    if (resolvedPrincipal == null) {
      try {
        resolvedPrincipal = SessionAuth.current(ctx);
      } on StateError {
        resolvedPrincipal = null;
      }
    }
    final evaluationContext = GateEvaluationContext(
      context: ctx,
      principal: resolvedPrincipal,
      payload: payload,
    );

    final allowed = await Future<bool>.value(callback(evaluationContext));
    _notifyObservers(
      GateEvaluation(
        ability: ability,
        allowed: allowed,
        context: ctx,
        principal: resolvedPrincipal,
        payload: payload,
      ),
    );
    return allowed;
  }

  static Future<void> authorize(
    String ability, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
    String? message,
  }) async {
    final allowed = await can(
      ability,
      ctx: ctx,
      principal: principal,
      payload: payload,
    );
    if (!allowed) {
      throw GateViolation(
        ability: ability,
        context: ctx,
        message: message,
        payload: payload,
      );
    }
  }

  static Future<bool> any(
    Iterable<String> abilities, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    for (final ability in abilities) {
      if (await can(
        ability,
        ctx: ctx,
        principal: principal,
        payload: payload,
      )) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> all(
    Iterable<String> abilities, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    for (final ability in abilities) {
      if (!await can(
        ability,
        ctx: ctx,
        principal: principal,
        payload: payload,
      )) {
        return false;
      }
    }
    return true;
  }

  static void _notifyObservers(GateEvaluation eval) {
    for (final observer in List<GateObserver>.from(_observers)) {
      observer(eval);
    }
  }

  static Middleware middleware(
    List<String> abilities, {
    GatePayloadProvider? payloadProvider,
    GateDeniedHandler? onDenied,
    int deniedStatusCode = HttpStatus.forbidden,
    String? deniedMessage,
  }) {
    final requested = abilities
        .map((ability) => ability.trim())
        .where((ability) => ability.isNotEmpty)
        .toList(growable: false);

    return (EngineContext ctx, Next next) async {
      for (final ability in requested) {
        final payload = payloadProvider?.call(ctx, ability);
        final allowed = await can(ability, ctx: ctx, payload: payload);
        if (!allowed) {
          final violation = GateViolation(
            ability: ability,
            context: ctx,
            message: deniedMessage,
            payload: payload,
          );
          final custom = await onDenied?.call(violation, ctx);
          if (custom != null) {
            return custom;
          }
          ctx.response
            ..statusCode = deniedStatusCode
            ..write(deniedMessage ?? 'Forbidden by gate: $ability');
          return ctx.response;
        }
      }
      return next();
    };
  }
}
