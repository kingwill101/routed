import 'dart:async';

import 'dart:io';

import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/support/named_registry.dart';

typedef GateCallback = FutureOr<bool> Function(GateEvaluationContext context);
typedef GateObserver = void Function(GateEvaluation evaluation);
typedef GatePayloadProvider =
    Object? Function(EngineContext ctx, String ability);
typedef GateDeniedHandler =
    FutureOr<Response?> Function(GateViolation violation, EngineContext ctx);

class GateRegistrationException implements Exception {
  GateRegistrationException(this.message);

  final String message;

  @override
  String toString() => 'GateRegistrationException: $message';
}

class GateViolation implements Exception {
  GateViolation({
    required this.ability,
    required this.context,
    this.message,
    this.payload,
  });

  final String ability;
  final EngineContext context;
  final String? message;
  final Object? payload;

  @override
  String toString() =>
      'GateViolation(ability: $ability, message: ${message ?? 'denied'})';
}

class GateEvaluationContext {
  GateEvaluationContext({
    required this.context,
    required this.principal,
    this.payload,
  });

  final EngineContext context;
  final AuthPrincipal? principal;
  final Object? payload;
}

class GateEvaluation {
  GateEvaluation({
    required this.ability,
    required this.allowed,
    required this.context,
    required this.principal,
    this.payload,
  });

  final String ability;
  final bool allowed;
  final EngineContext context;
  final AuthPrincipal? principal;
  final Object? payload;
}

class GateRegistry extends NamedRegistry<GateCallback> {
  GateRegistry._();

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

  void register(String ability, GateCallback callback) {
    final key = normalizeName(ability);
    if (key.isEmpty) {
      throw GateRegistrationException('Ability name cannot be empty.');
    }
    registerEntry(key, callback);
  }

  void registerAll(Map<String, GateCallback> entries) {
    entries.forEach(register);
  }

  void unregister(String ability) {
    unregisterEntry(ability);
  }

  GateCallback? resolve(String ability) => getEntry(ability);

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
