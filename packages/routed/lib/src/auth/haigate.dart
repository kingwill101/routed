import 'dart:async';
import 'dart:io';

import 'package:server_auth/server_auth.dart'
    show
        AuthGateCallback,
        AuthGateEvaluation,
        AuthGateEvaluationContext,
        AuthGateObserver,
        AuthGateRegistry,
        AuthGateRegistrationException,
        AuthGateViolation,
        AuthPrincipal;
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';

/// A function that provides a payload for a specific ability in the given
/// [EngineContext].
typedef GatePayloadProvider =
    Object? Function(EngineContext ctx, String ability);

/// A handler function that is called when a gate denies access.
typedef GateDeniedHandler =
    FutureOr<Response?> Function(
      AuthGateViolation<EngineContext> violation,
      EngineContext ctx,
    );

/// Global gate registry used by [Haigate].
final AuthGateRegistry<EngineContext> gateRegistry =
    AuthGateRegistry<EngineContext>();

class Haigate {
  Haigate._();

  static final AuthGateRegistry<EngineContext> _registry = gateRegistry;
  static final List<AuthGateObserver<EngineContext>> _observers =
      <AuthGateObserver<EngineContext>>[];

  static AuthGateRegistry<EngineContext> get registry => _registry;

  static void register(
    String ability,
    AuthGateCallback<EngineContext> callback,
  ) {
    _registry.register(ability, callback);
  }

  static void registerAll(
    Map<String, AuthGateCallback<EngineContext>> entries,
  ) {
    _registry.registerAll(entries);
  }

  static void unregister(String ability) {
    _registry.unregister(ability);
  }

  static void addObserver(AuthGateObserver<EngineContext> observer) {
    _observers.add(observer);
  }

  static void removeObserver(AuthGateObserver<EngineContext> observer) {
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
      throw AuthGateRegistrationException(
        'Ability "$ability" is not registered.',
      );
    }

    AuthPrincipal? resolvedPrincipal = principal;
    if (resolvedPrincipal == null) {
      try {
        resolvedPrincipal = SessionAuth.current(ctx);
      } on StateError {
        resolvedPrincipal = null;
      }
    }
    final evaluationContext = AuthGateEvaluationContext<EngineContext>(
      context: ctx,
      principal: resolvedPrincipal,
      payload: payload,
    );

    final allowed = await Future<bool>.value(callback(evaluationContext));
    _notifyObservers(
      AuthGateEvaluation<EngineContext>(
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
      throw AuthGateViolation<EngineContext>(
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

  static void _notifyObservers(AuthGateEvaluation<EngineContext> eval) {
    for (final observer in List<AuthGateObserver<EngineContext>>.from(
      _observers,
    )) {
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
          final violation = AuthGateViolation<EngineContext>(
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
